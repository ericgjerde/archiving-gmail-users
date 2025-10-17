#!/bin/bash

################################################################################
# Google Workspace User Archive Automation Script
################################################################################
#
# Description:
#   Automates the archival of Google Workspace users who have been moved to
#   a "FormerEmployees" organizational unit. Uses GAM (read-only) to discover
#   users and GYB (Got Your Back) to backup user data, compresses it, and
#   generates comprehensive reports.
#
# IMPORTANT: GAM is used ONLY for read-only operations (querying users in the
#   target OU). This script makes NO modifications to your Google Workspace
#   via GAM. Always review GAM commands in scripts before execution.
#
# Prerequisites:
#   - Bash 4.0+
#   - GAM (Google Apps Manager) - pre-installed and configured with OAuth
#   - GYB (Got Your Back) - pre-installed and configured with service account
#   - GAM config typically in ~/.gam/ (or custom GAMCFGDIR location)
#   - GYB must be configured with proper OAuth scopes and service account
#
# Usage:
#   ./archive-workspace-users.sh [OPTIONS]
#
# Options:
#   --dry-run                 Show what would be done without executing
#   --user <email>            Archive only the specified user
#   --ou <path>               Use custom organizational unit path
#   --help                    Display this help message
#
# Examples:
#   # Archive all users in FormerEmployees OU
#   ./archive-workspace-users.sh
#
#   # Dry run to see what would happen
#   ./archive-workspace-users.sh --dry-run
#
#   # Archive a specific user
#   ./archive-workspace-users.sh --user user@domain.com
#
#   # Use custom OU
#   ./archive-workspace-users.sh --ou "/SuspendedUsers"
#
# Author: Generated for Google Workspace Administration
# Version: 1.2.0
################################################################################

# Strict error handling
set -euo pipefail

################################################################################
# CONFIGURATION SECTION
################################################################################

# Organizational unit containing former employees
FORMER_EMPLOYEES_OU="${FORMER_EMPLOYEES_OU:-/FormerEmployees}"

# Directory structure
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ARCHIVE_BASE_DIR="${ARCHIVE_BASE_DIR:-${SCRIPT_DIR}/archives}"
TEMP_DIR="${TEMP_DIR:-${SCRIPT_DIR}/temp}"
LOG_DIR="${LOG_DIR:-${SCRIPT_DIR}/logs}"
REPORT_DIR="${REPORT_DIR:-${SCRIPT_DIR}/reports}"

# Rate limiting and performance
DELAY_BETWEEN_USERS=0   # Seconds to wait between processing users (0 = no delay)
RETRY_DELAY=60          # Seconds to wait before retrying after rate limit
MAX_RETRIES=3           # Maximum number of retries for failed operations

# Tool paths (auto-detect if not set)
# Default to simple command names - user can override with environment variables
: "${GAM_BIN:=gam}"

# Auto-detect GYB location if not set
if [[ -z "${GYB_BIN:-}" ]]; then
    # Try common GYB installation locations
    if [[ -x "/usr/local/bin/gyb/gyb" ]]; then
        GYB_BIN="/usr/local/bin/gyb/gyb"
    elif [[ -x "/usr/local/bin/gyb" ]]; then
        GYB_BIN="/usr/local/bin/gyb"
    elif command -v gyb &> /dev/null; then
        GYB_BIN="gyb"
    else
        GYB_BIN="gyb"  # fallback
    fi
fi

# Script execution flags
DRY_RUN=false
SINGLE_USER=""
CUSTOM_OU=""

# Statistics tracking
TOTAL_USERS=0
SUCCESSFUL_COUNT=0
FAILED_COUNT=0
SKIPPED_COUNT=0

# Solarized-inspired color palette for better readability
if [[ -t 1 ]]; then
    RED='\033[0;31m'      # Solarized red for errors
    GREEN='\033[0;32m'    # Solarized green for success
    YELLOW='\033[1;33m'   # Solarized yellow for warnings
    CYAN='\033[1;36m'     # Solarized cyan for info (replaces hard-to-read dark blue)
    NC='\033[0m'          # No Color
else
    RED=''
    GREEN=''
    YELLOW=''
    CYAN=''
    NC=''
fi

################################################################################
# LOGGING FUNCTIONS
################################################################################

# Log file with timestamp
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
LOG_FILE="${LOG_DIR}/archive_${TIMESTAMP}.log"

###
# log_message - Write timestamped message to log file and stdout
#
# Parameters:
#   $1 - Log level (INFO, WARN, ERROR, SUCCESS)
#   $@ - Message to log
#
# Returns:
#   None
###
log_message() {
    local level="$1"
    shift
    local message="$*"
    local timestamp
    timestamp=$(date '+%Y-%m-%d %H:%M:%S')

    local color=""
    case "$level" in
        ERROR)   color="$RED" ;;
        SUCCESS) color="$GREEN" ;;
        WARN)    color="$YELLOW" ;;
        INFO)    color="$CYAN" ;;
    esac

    # Log to file without color
    echo "[${timestamp}] [${level}] ${message}" >> "$LOG_FILE"

    # Display to stdout with color (using >&2 to avoid polluting function returns)
    echo -e "${color}[${timestamp}] [${level}] ${message}${NC}" >&2
}

###
# log_separator - Write a visual separator to log
#
# Parameters:
#   $1 - Optional title for the section
#
# Returns:
#   None
###
log_separator() {
    local title="${1:-}"
    local separator="========================================"

    if [[ -n "$title" ]]; then
        log_message "INFO" "$separator"
        log_message "INFO" "$title"
        log_message "INFO" "$separator"
    else
        log_message "INFO" "$separator"
    fi
}

################################################################################
# UTILITY FUNCTIONS
################################################################################

###
# show_help - Display usage information
#
# Parameters:
#   None
#
# Returns:
#   None
###
show_help() {
    cat << EOF
Google Workspace User Archive Automation Script

Usage: $(basename "$0") [OPTIONS]

Options:
    --dry-run           Show what would be done without executing
    --user <email>      Archive only the specified user
    --ou <path>         Use custom organizational unit path
    --help              Display this help message

Examples:
    # Archive all users in FormerEmployees OU
    $(basename "$0")

    # Dry run to see what would happen
    $(basename "$0") --dry-run

    # Archive a specific user
    $(basename "$0") --user user@domain.com

    # Use custom OU
    $(basename "$0") --ou "/SuspendedUsers"

Configuration:
    The following environment variables can be set:
    - FORMER_EMPLOYEES_OU: Default OU path (default: /FormerEmployees)
    - ARCHIVE_BASE_DIR: Archive storage location
    - GAM_BIN: Path to GAM binary
    - GYB_BIN: Path to GYB binary

    Note: GAM and GYB must be pre-configured with proper OAuth credentials.
    This script does not manage authentication - it uses your existing
    GAM/GYB configuration (typically in ~/.gam/ or custom GAMCFGDIR).

EOF
    exit 0
}

###
# cleanup_on_exit - Cleanup handler for script interruption
#
# Parameters:
#   None
#
# Returns:
#   None
###
cleanup_on_exit() {
    log_message "WARN" "Script interrupted. Cleaning up..."

    # Generate partial report if any users were processed
    if [[ $SUCCESSFUL_COUNT -gt 0 || $FAILED_COUNT -gt 0 ]]; then
        generate_report "INTERRUPTED"
    fi

    # Clean up temporary user list files
    rm -f "${TEMP_DIR}/users_"*.csv 2>/dev/null

    log_message "INFO" "Cleanup complete. Exiting."
    exit 130
}

###
# format_size - Format byte size into human-readable format
#
# Parameters:
#   $1 - Size in bytes
#
# Returns:
#   Formatted size string (e.g., "1.5 GB")
###
format_size() {
    local size=$1
    local units=("B" "KB" "MB" "GB" "TB")
    local unit_index=0
    local size_float=$size

    while (( $(echo "$size_float >= 1024" | bc -l) )) && [[ $unit_index -lt 4 ]]; do
        size_float=$(echo "scale=2; $size_float / 1024" | bc)
        ((unit_index++)) || true
    done

    printf "%.2f %s" "$size_float" "${units[$unit_index]}"
}

################################################################################
# VALIDATION FUNCTIONS
################################################################################

###
# check_dependencies - Verify all required tools are installed
#
# Parameters:
#   None
#
# Returns:
#   0 if all dependencies are met
#   1 if any dependency is missing
###
check_dependencies() {
    log_message "INFO" "Checking dependencies..."

    local missing_deps=()

    # Check for required utilities
    for cmd in tar gzip bc tee; do
        if ! command -v "$cmd" &> /dev/null; then
            missing_deps+=("$cmd")
        fi
    done

    # Verify GAM is functional
    # This will fail if it's not properly configured with OAuth credentials
    log_message "INFO" "Verifying GAM configuration..."
    if ! $GAM_BIN version &> /dev/null; then
        log_message "ERROR" "GAM is not properly configured or accessible"
        log_message "ERROR" "Tried to run: $GAM_BIN"
        missing_deps+=("GAM (Google Apps Manager)")
    else
        log_message "SUCCESS" "GAM verified: $GAM_BIN"
    fi

    # Verify GYB is functional
    log_message "INFO" "Verifying GYB configuration..."
    if ! $GYB_BIN --version &> /dev/null; then
        log_message "ERROR" "GYB is not properly configured or accessible"
        log_message "ERROR" "Tried to run: $GYB_BIN"
        log_message "ERROR" "If you have gyb aliased, set the actual path:"
        log_message "ERROR" "  export GYB_BIN=/path/to/gyb"
        log_message "ERROR" "Common locations: /usr/local/bin/gyb/gyb or /usr/local/bin/gyb"
        missing_deps+=("GYB (Got Your Back)")
    else
        log_message "SUCCESS" "GYB verified: $GYB_BIN"
    fi

    # Report missing dependencies
    if [[ ${#missing_deps[@]} -gt 0 ]]; then
        log_message "ERROR" "Missing required dependencies:"
        for dep in "${missing_deps[@]}"; do
            log_message "ERROR" "  - $dep"
        done
        return 1
    fi

    log_message "SUCCESS" "All dependencies satisfied"
    return 0
}

###
# create_directories - Create required directory structure
#
# Parameters:
#   None
#
# Returns:
#   0 on success
###
create_directories() {
    log_message "INFO" "Creating directory structure..."

    local dirs=("$ARCHIVE_BASE_DIR" "$TEMP_DIR" "$LOG_DIR" "$REPORT_DIR")

    for dir in "${dirs[@]}"; do
        if [[ ! -d "$dir" ]]; then
            mkdir -p "$dir"
            log_message "SUCCESS" "Created directory: $dir"
        else
            log_message "INFO" "Directory exists: $dir"
        fi
    done

    # Set restrictive permissions on directories (owner-only)
    chmod 700 "$ARCHIVE_BASE_DIR" "$TEMP_DIR" "$LOG_DIR" "$REPORT_DIR"

    return 0
}


################################################################################
# USER DISCOVERY FUNCTIONS
################################################################################

###
# validate_ou_path - Validate OU path to prevent injection attacks
#
# Parameters:
#   $1 - OU path to validate
#
# Returns:
#   0 if valid
#   1 if invalid
###
validate_ou_path() {
    local ou_path="$1"

    # OU paths must start with /
    if [[ ! "$ou_path" =~ ^/ ]]; then
        log_message "ERROR" "Invalid OU path: must start with forward slash"
        return 1
    fi

    # Only allow safe characters: alphanumeric, /, -, _, and space
    # Explicitly reject quotes, backticks, semicolons, pipes, etc.
    local dangerous_chars='['\''";\|&$`()<>\\]'
    if [[ "$ou_path" =~ $dangerous_chars ]]; then
        log_message "ERROR" "Invalid OU path: contains dangerous characters (quotes, semicolons, pipes, etc.)"
        return 1
    fi

    # Check length (reasonable limit)
    if [[ ${#ou_path} -gt 200 ]]; then
        log_message "ERROR" "Invalid OU path: exceeds maximum length of 200 characters"
        return 1
    fi

    return 0
}

###
# discover_users - Query Google Workspace for users in target OU
#
# Parameters:
#   None (uses global OU configuration)
#
# Returns:
#   0 on success
#   1 on failure
###
discover_users() {
    local ou_path="${CUSTOM_OU:-$FORMER_EMPLOYEES_OU}"

    # Validate OU path to prevent injection attacks
    if ! validate_ou_path "$ou_path"; then
        log_message "ERROR" "OU path validation failed: $ou_path"
        return 1
    fi

    log_message "INFO" "Discovering users in OU: $ou_path"

    # Temporary file for user list
    local user_list_file="${TEMP_DIR}/users_${TIMESTAMP}.csv"

    # Execute GAM command to list users (READ-ONLY operation)
    # Query for users in the specific OU and get their email and full name
    # OU path has been validated above to prevent injection
    # This is the ONLY GAM command used by this script - it makes no modifications
    if ! $GAM_BIN print users query "orgUnitPath='${ou_path}'" fields primaryEmail,fullname > "$user_list_file" 2>> "$LOG_FILE"; then
        log_message "ERROR" "Failed to retrieve user list from GAM"
        return 1
    fi

    # Count users (excluding header line)
    # Use arithmetic to ensure we get a clean integer value
    TOTAL_USERS=$(tail -n +2 "$user_list_file" | wc -l | tr -d ' \t\n\r')
    TOTAL_USERS=$((TOTAL_USERS + 0))  # Force integer conversion

    if [[ $TOTAL_USERS -eq 0 ]]; then
        log_message "WARN" "No users found in OU: $ou_path"
        return 1
    fi

    log_message "SUCCESS" "Found $TOTAL_USERS user(s) to process"

    # Store user list path in global variable
    USER_LIST_FILE="$user_list_file"
    return 0
}

###
# confirm_processing - Display user list and request confirmation
#
# Parameters:
#   $1 - Path to user list CSV file
#
# Returns:
#   0 if user confirms
#   1 if user cancels
###
confirm_processing() {
    local user_list_file="$1"
    local ou_path="${CUSTOM_OU:-$FORMER_EMPLOYEES_OU}"

    echo ""
    log_message "INFO" "Users to be archived from OU: $ou_path"
    echo ""

    # Display user list (skip header)
    while IFS=',' read -r email fullname; do
        # Remove quotes if present
        email=$(echo "$email" | tr -d '"')
        fullname=$(echo "$fullname" | tr -d '"')
        echo "  - $email ($fullname)"
    done < <(tail -n +2 "$user_list_file" 2>/dev/null)

    echo ""

    if [[ "$DRY_RUN" == "true" ]]; then
        log_message "INFO" "DRY RUN MODE - No changes will be made"
        return 0
    fi

    # Require exact OU path confirmation for safety
    log_message "WARN" "This will archive Gmail data for all users listed above. This does not delete or modify the accounts in any way."
    read -r -p "Type the exact OU path to confirm: " confirmation

    if [[ "$confirmation" != "$ou_path" ]]; then
        log_message "ERROR" "Confirmation '$confirmation' does not match OU path '$ou_path'. Aborting."
        return 1
    fi

    log_message "INFO" "User confirmed. Proceeding with archival..."
    return 0
}

################################################################################
# BACKUP FUNCTIONS
################################################################################

###
# check_existing_archive - Check if user already has an archive
#
# Parameters:
#   $1 - User email address
#
# Returns:
#   0 if archive exists (skip user)
#   1 if no archive exists (process user)
###
check_existing_archive() {
    local user_email="$1"

    # Look for any archive file matching this user
    # Pattern: user@domain.com_*.tar.gz
    local existing_archives
    existing_archives=$(find "$ARCHIVE_BASE_DIR" -name "${user_email}_*.tar.gz" 2>/dev/null)

    if [[ -n "$existing_archives" ]]; then
        log_message "INFO" "Archive already exists for $user_email:"
        echo "$existing_archives" | while read -r archive; do
            local size
            size=$(stat -f%z "$archive" 2>/dev/null || stat -c%s "$archive" 2>/dev/null)
            log_message "INFO" "  - $(basename "$archive") ($(format_size "$size"))"
        done
        return 0
    fi

    return 1
}

###
# monitor_gyb_progress - Monitor GYB backup progress in background
#
# Parameters:
#   $1 - Path to GYB log file to monitor
#   $2 - User email (for logging)
#
# Returns:
#   None (runs in background)
###
monitor_gyb_progress() {
    local gyb_log="$1"
    local user_email="$2"
    local last_reported=0
    local total_messages=0
    local discovered=false

    # Wait for log file to be created (up to 10 seconds)
    local wait_count=0
    while [[ ! -f "$gyb_log" && $wait_count -lt 20 ]]; do
        sleep 0.5
        ((wait_count++)) || true
    done

    if [[ ! -f "$gyb_log" ]]; then
        return 0  # Log file never created, exit silently
    fi

    # Poll the log file periodically for progress updates
    # GYB uses carriage returns, so all progress updates are on one line
    while true; do
        # Check if log file still exists (might be removed when done)
        if [[ ! -f "$gyb_log" ]]; then
            break
        fi

        # Extract total message count if not yet discovered
        if [[ ! "$discovered" == "true" ]]; then
            if grep -q "GYB needs to backup" "$gyb_log" 2>/dev/null; then
                local line
                line=$(grep "GYB needs to backup" "$gyb_log" 2>/dev/null | tail -1)
                if [[ "$line" =~ "GYB needs to backup "([0-9]+)" messages" ]]; then
                    total_messages="${BASH_REMATCH[1]}"
                    if [[ $total_messages -gt 0 ]]; then
                        discovered=true
                        log_message "INFO" "Found $total_messages message(s) to backup for $user_email"
                    fi
                fi
            fi
        fi

        # Extract latest progress - use grep -o to get all matches, then take the last one
        # GYB writes all progress on one line with carriage returns
        if grep -q "backed up" "$gyb_log" 2>/dev/null; then
            local last_progress
            last_progress=$(grep -o "backed up [0-9]* of [0-9]* messages" "$gyb_log" 2>/dev/null | tail -1)

            if [[ -n "$last_progress" ]]; then
                # Parse the numbers from the last progress line
                if [[ "$last_progress" =~ backed\ up\ ([0-9]+)\ of\ ([0-9]+)\ messages ]]; then
                    local current="${BASH_REMATCH[1]}"
                    local total="${BASH_REMATCH[2]}"

                    # Only report every 500 messages to avoid spam
                    if [[ $((current - last_reported)) -ge 500 ]] || [[ $current -eq $total ]]; then
                        local percent=$((current * 100 / total))
                        log_message "INFO" "Progress: $current/$total messages ($percent%)"
                        last_reported=$current

                        # If we've reached the total, stop monitoring
                        if [[ $current -eq $total ]]; then
                            break
                        fi
                    fi
                fi
            fi
        fi

        # Check every 2 seconds
        sleep 2
    done
}

###
# backup_user_data - Execute GYB backup for a single user
#
# Parameters:
#   $1 - User email address
#   $2 - Retry attempt number (default: 1)
#
# Returns:
#   0 on success
#   1 on failure
###
backup_user_data() {
    local user_email="$1"
    local retry_attempt="${2:-1}"
    local user_temp_dir="${TEMP_DIR}/${user_email}"

    log_message "INFO" "Starting GYB backup for: $user_email (Attempt $retry_attempt/$MAX_RETRIES)"

    if [[ "$DRY_RUN" == "true" ]]; then
        log_message "INFO" "[DRY RUN] Would execute: $GYB_BIN --email $user_email --service-account --action backup --local-folder $user_temp_dir"
        sleep 2  # Simulate some work
        return 0
    fi

    # Create temporary directory for this user
    mkdir -p "$user_temp_dir"

    # Execute GYB backup command with service account for domain-wide delegation
    # Capture both stdout and stderr to log file
    # GYB will use its configured service account with domain-wide delegation
    local gyb_log="${LOG_DIR}/gyb_${user_email}_${TIMESTAMP}.log"

    # Start progress monitor in background
    monitor_gyb_progress "$gyb_log" "$user_email" &
    local monitor_pid=$!

    if $GYB_BIN --email "$user_email" \
                --service-account \
                --action backup \
                --local-folder "$user_temp_dir" \
                >> "$gyb_log" 2>&1; then

        # Kill the progress monitor (it may have already exited)
        kill "$monitor_pid" 2>/dev/null || true
        wait "$monitor_pid" 2>/dev/null || true

        log_message "SUCCESS" "GYB backup completed for: $user_email"

        # Check if any data was actually backed up
        local file_count
        file_count=$(find "$user_temp_dir" -type f | wc -l | tr -d ' ')

        if [[ $file_count -eq 0 ]]; then
            log_message "WARN" "No files backed up for $user_email (empty mailbox?)"
        else
            log_message "INFO" "Backed up $file_count file(s) for $user_email"
        fi

        return 0
    else
        # Kill the progress monitor
        kill "$monitor_pid" 2>/dev/null || true
        wait "$monitor_pid" 2>/dev/null || true

        # Check for mail service not enabled (user has no Gmail license)
        if grep -qi "Mail service not enabled\|failedPrecondition" "$gyb_log"; then
            log_message "WARN" "User $user_email has no Gmail license (mail service not enabled)"
            log_message "WARN" "Skipping backup - mailbox may have been deleted when license was removed"
            # Return special code 2 to indicate skip rather than failure
            return 2
        fi

        # Check for rate limit errors
        if grep -qi "rate limit\|quota\|429" "$gyb_log"; then
            log_message "WARN" "Rate limit detected for $user_email"

            if [[ $retry_attempt -lt $MAX_RETRIES ]]; then
                log_message "INFO" "Waiting ${RETRY_DELAY}s before retry..."
                sleep "$RETRY_DELAY"
                return backup_user_data "$user_email" $((retry_attempt + 1))
            fi
        fi

        log_message "ERROR" "GYB backup failed for: $user_email"
        log_message "ERROR" "Check log file: $gyb_log"
        return 1
    fi
}

###
# compress_backup - Compress user backup into tar.gz archive
#
# Parameters:
#   $1 - User email address
#
# Returns:
#   0 on success
#   1 on failure
###
compress_backup() {
    local user_email="$1"
    local user_temp_dir="${TEMP_DIR}/${user_email}"
    local archive_name="${user_email}_${TIMESTAMP}.tar.gz"
    local archive_path="${ARCHIVE_BASE_DIR}/${archive_name}"

    log_message "INFO" "Compressing backup for: $user_email"

    if [[ "$DRY_RUN" == "true" ]]; then
        log_message "INFO" "[DRY RUN] Would create archive: $archive_path"
        return 0
    fi

    # Check if temp directory exists and has files
    if [[ ! -d "$user_temp_dir" ]]; then
        log_message "ERROR" "Temp directory not found: $user_temp_dir"
        return 1
    fi

    local file_count
    file_count=$(find "$user_temp_dir" -type f | wc -l | tr -d ' ')

    if [[ $file_count -eq 0 ]]; then
        log_message "WARN" "No files to compress for $user_email"
        # Still create an archive to mark this user as processed
    fi

    # Create tar.gz archive
    # Use -C to change to temp directory and archive relative paths
    if tar -czf "$archive_path" -C "$TEMP_DIR" "$(basename "$user_temp_dir")" 2>> "$LOG_FILE"; then

        # Get archive size
        local size
        size=$(stat -f%z "$archive_path" 2>/dev/null || stat -c%s "$archive_path" 2>/dev/null)

        log_message "SUCCESS" "Archive created: $archive_name ($(format_size "$size"))"

        # Set restrictive permissions on archive
        chmod 600 "$archive_path"

        # Clean up temporary directory with path validation
        if [[ "$user_temp_dir" == "${TEMP_DIR}/"* && -d "$user_temp_dir" ]]; then
            rm -rf "$user_temp_dir"
            log_message "INFO" "Cleaned up temporary files for: $user_email"
        else
            log_message "ERROR" "Unsafe temp directory path: $user_temp_dir - skipping cleanup"
        fi

        return 0
    else
        log_message "ERROR" "Failed to create archive for: $user_email"
        return 1
    fi
}

###
# process_single_user - Process backup and compression for one user
#
# Parameters:
#   $1 - User email address
#
# Returns:
#   0 on success
#   1 on failure
###
process_single_user() {
    local user_email="$1"

    log_separator "Processing: $user_email"

    # Check for existing archive (resume capability)
    if check_existing_archive "$user_email"; then
        log_message "INFO" "Skipping $user_email (already archived)"
        ((SKIPPED_COUNT++)) || true
        return 0
    fi

    # Execute GYB backup
    backup_user_data "$user_email"
    local backup_result=$?

    if [[ $backup_result -eq 2 ]]; then
        # User has no Gmail license - skip but don't fail
        log_message "INFO" "Skipping $user_email (no Gmail license)"
        ((SKIPPED_COUNT++)) || true
        return 0
    elif [[ $backup_result -ne 0 ]]; then
        # Actual backup failure
        log_message "ERROR" "Backup failed for: $user_email"
        ((FAILED_COUNT++)) || true
        return 1
    fi

    # Compress the backup
    if ! compress_backup "$user_email"; then
        log_message "ERROR" "Compression failed for: $user_email"
        ((FAILED_COUNT++)) || true
        return 1
    fi

    ((SUCCESSFUL_COUNT++)) || true
    log_message "SUCCESS" "Successfully processed: $user_email"

    return 0
}

################################################################################
# REPORT GENERATION
################################################################################

###
# generate_report - Create comprehensive report of archive operation
#
# Parameters:
#   $1 - Status (COMPLETED or INTERRUPTED)
#
# Returns:
#   Path to generated report file
###
generate_report() {
    local status="${1:-COMPLETED}"
    local report_file="${REPORT_DIR}/archive_report_${TIMESTAMP}.txt"
    local ou_path="${CUSTOM_OU:-$FORMER_EMPLOYEES_OU}"

    log_message "INFO" "Generating report..."

    {
        echo "======================================"
        echo "Google Workspace Archive Report"
        echo "======================================"
        echo "Timestamp: $(date '+%Y-%m-%d %H:%M:%S')"
        echo "Status: $status"
        echo "OU: $ou_path"
        echo ""

        echo "Archives Created:"
        echo "--------------------------------------"

        if [[ -d "$ARCHIVE_BASE_DIR" ]]; then
            # List all archives created in this run
            find "$ARCHIVE_BASE_DIR" -name "*_${TIMESTAMP}.tar.gz" -type f | while read -r archive; do
                local size
                size=$(stat -f%z "$archive" 2>/dev/null || stat -c%s "$archive" 2>/dev/null)
                echo "  $(basename "$archive") - $(format_size "$size")"
            done
        fi

        # If no archives were created in this run, note it
        if [[ $SUCCESSFUL_COUNT -eq 0 ]]; then
            echo "  (No new archives created)"
        fi

        echo ""
        echo "Summary:"
        echo "  Total Users Processed: $TOTAL_USERS"
        echo "  Successful: $SUCCESSFUL_COUNT"
        echo "  Failed: $FAILED_COUNT"
        echo "  Skipped (Already Archived): $SKIPPED_COUNT"
        echo ""

        if [[ $FAILED_COUNT -gt 0 ]]; then
            echo "Errors Encountered:"
            echo "  Check log file for details"
            echo ""
        fi

        echo "Full log: $LOG_FILE"
        echo "======================================"

    } > "$report_file"

    # Also display report to stdout
    cat "$report_file"

    log_message "SUCCESS" "Report saved to: $report_file"
    echo "$report_file"
}

################################################################################
# MAIN EXECUTION
################################################################################

###
# main - Main script execution flow
#
# Parameters:
#   Command line arguments
#
# Returns:
#   0 on success
#   1 on failure
###
main() {
    # Parse command line arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            --dry-run)
                DRY_RUN=true
                shift
                ;;
            --user)
                SINGLE_USER="$2"
                shift 2
                ;;
            --ou)
                CUSTOM_OU="$2"
                shift 2
                ;;
            --help)
                show_help
                ;;
            *)
                echo "Unknown option: $1"
                show_help
                ;;
        esac
    done

    # Create directories first (including log directory)
    mkdir -p "$LOG_DIR" "$REPORT_DIR"

    # Start logging
    log_separator "Google Workspace User Archive Script Started"

    # Log audit trail information
    log_message "INFO" "Executed by: ${USER:-unknown} on ${HOSTNAME:-unknown}"
    log_message "INFO" "Working directory: $PWD"
    gam_version=$($GAM_BIN version 2>&1 | head -1 || echo 'unknown')
    log_message "INFO" "GAM version: $gam_version"

    if [[ "$DRY_RUN" == "true" ]]; then
        log_message "INFO" "Running in DRY RUN mode - no changes will be made"
    fi

    # Setup trap for graceful interruption
    trap cleanup_on_exit SIGINT SIGTERM

    # Validate environment
    if ! check_dependencies; then
        log_message "ERROR" "Dependency check failed. Exiting."
        exit 1
    fi

    if ! create_directories; then
        log_message "ERROR" "Failed to create directory structure. Exiting."
        exit 1
    fi

    # Handle single user mode
    if [[ -n "$SINGLE_USER" ]]; then
        log_message "INFO" "Single user mode: $SINGLE_USER"

        # Request confirmation for single user
        if [[ "$DRY_RUN" != "true" ]]; then
            read -r -p "Archive user $SINGLE_USER? (yes/no): " response
            if [[ ! "$response" =~ ^[yY][eE][sS]$|^[yY]$ ]]; then
                log_message "INFO" "Operation cancelled by user"
                exit 0
            fi
        fi

        TOTAL_USERS=1
        process_single_user "$SINGLE_USER"

        # Generate report
        generate_report "COMPLETED"

        log_separator "Script Completed"
        exit 0
    fi

    # Discover users (sets global USER_LIST_FILE variable)
    if ! discover_users; then
        log_message "ERROR" "User discovery failed. Exiting."
        exit 1
    fi

    # Confirm with user before proceeding
    if ! confirm_processing "$USER_LIST_FILE"; then
        log_message "INFO" "Operation cancelled by user"
        exit 0
    fi

    log_separator "Beginning Sequential Processing"

    # Process each user sequentially
    # Use process substitution to avoid subshell issue with counters
    local user_count=0
    while IFS=',' read -r email fullname; do
        # Remove quotes if present
        email=$(echo "$email" | tr -d '"')

        # Validate email format
        if [[ ! "$email" =~ ^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$ ]]; then
            log_message "WARN" "Invalid email format: $email - skipping"
            continue
        fi

        ((user_count++)) || true
        log_message "INFO" "Processing user $user_count of $TOTAL_USERS"

        # Process the user
        process_single_user "$email" || true

        # Rate limiting delay (except for last user, and only if delay is set)
        if [[ $user_count -lt $TOTAL_USERS && $DELAY_BETWEEN_USERS -gt 0 ]]; then
            log_message "INFO" "Waiting ${DELAY_BETWEEN_USERS}s before next user (rate limiting)..."
            if [[ "$DRY_RUN" != "true" ]]; then
                sleep "$DELAY_BETWEEN_USERS"
            fi
        fi
    done < <(tail -n +2 "$USER_LIST_FILE")

    # Clean up temporary user list file
    rm -f "$USER_LIST_FILE"

    # Generate final report
    log_separator "Processing Complete"
    generate_report "COMPLETED"

    log_separator "Script Completed Successfully"

    # Final summary
    log_message "INFO" "Total: $TOTAL_USERS | Success: $SUCCESSFUL_COUNT | Failed: $FAILED_COUNT | Skipped: $SKIPPED_COUNT"
}

# Execute main function with all command line arguments
main "$@"
