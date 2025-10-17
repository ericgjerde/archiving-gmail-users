# Google Workspace User Archive Automation

A comprehensive bash script for automating the archival of Google Workspace users who have been moved to a "FormerEmployees" organizational unit.

**IMPORTANT**: This script uses GAM **ONLY** for read-only user discovery (listing users in the target OU). GAM makes no modifications to your Workspace. That being said, as a good admin, you should always review usage of GAM commands in the script to verify read-only operations before running. Trust but verify :)

## Features

- Automated discovery of users in specified organizational units (GAM used read-only to query user lists)
- Sequential backup using GYB (Got Your Back)
- **Real-time progress monitoring** - Shows backup progress every 500 messages with percentage updates
- Automatic compression of backups into tar.gz archives
- Resume capability (skips already archived users)
- Comprehensive logging with timestamps
- Detailed reports generation
- Error handling with retry logic for rate limits
- Dry-run mode for testing
- Single user mode for targeted backups
- **Solarized color-coded console output** for improved readability
- Progress tracking and statistics
- Enhanced security with input validation and audit logging
- OU path validation to prevent command injection
- Email address format validation
- Path validation before file deletion

## Prerequisites

### IMPORTANT: Pre-Installation Required

This script **DOES NOT** install or configure GAM or GYB. You must install and configure these tools separately **BEFORE** using this script. The script assumes you have working GAM and GYB installations with proper OAuth credentials already configured.

### Required Tools

1. **Bash 4.0+**
   ```bash
   bash --version
   ```

2. **GAM (Google Apps Manager) - PRE-INSTALLED & CONFIGURED**
   - Installation guide: https://github.com/GAM-team/GAM
   - Must be fully configured with OAuth credentials for your domain
   - Configuration stored in `~/.gam/` (or custom `GAMCFGDIR`)
   - Test your installation:
     ```bash
     gam version
     gam info domain
     ```
   - If GAM is not configured, this script will fail

3. **GYB (Got Your Back) - PRE-INSTALLED & CONFIGURED**
   - Installation guide: https://github.com/GAM-team/got-your-back
   - Must be fully configured with service account and OAuth scopes
   - Configuration typically in `~/.gyb/` or alongside GAM config
   - Test your installation:
     ```bash
     gyb --version
     ```
   - Required OAuth scopes for GYB:
     - `https://www.googleapis.com/auth/gmail.readonly`
     - `https://www.googleapis.com/auth/gmail.modify`
     - `https://mail.google.com/`

4. **Standard Unix Utilities**
   - tar, gzip, bc, tee (typically pre-installed)

### GAM/GYB Configuration Location

By default, GAM stores its configuration in `~/.gam/` including:
- `oauth2.txt` - OAuth credentials
- `oauth2service.json` - Service account file
- `client_secrets.json` - API credentials

You can customize this location using the `GAMCFGDIR` environment variable:
```bash
export GAMCFGDIR="/opt/gam-config"
```

**Security Best Practice:**
```bash
# Restrict access to GAM/GYB configuration
chmod 700 ~/.gam
chmod 600 ~/.gam/*
```

### Verifying Your Setup

Before using this script, verify GAM and GYB work correctly:

```bash
# Test GAM can list users
gam print users query "orgUnitPath='/FormerEmployees'" fields primaryEmail

# Test GYB can estimate a backup (without actually backing up)
gyb --email test@yourdomain.com --action estimate
```

If either command fails, you need to configure GAM/GYB before using this script.

## Installation

1. **Verify GAM and GYB are installed and configured** (see Prerequisites above)

2. Clone or download this repository:
   ```bash
   git clone https://github.com/ericgjerde/archiving-gmail-users.git
   cd archiving-gmail-users
   ```

3. Ensure the script is executable:
   ```bash
   chmod +x archive-workspace-users.sh
   ```

4. Test the script with dry-run mode:
   ```bash
   ./archive-workspace-users.sh --dry-run
   ```

That's it! The script will use your existing GAM/GYB configuration automatically.

## Usage

### Basic Usage

Archive all users in the default "FormerEmployees" OU:
```bash
./archive-workspace-users.sh
```

### Command Line Options

```
--dry-run              Show what would be done without executing
--user <email>         Archive only the specified user
--ou <path>            Use custom organizational unit path
--help                 Display help message
```

### Examples

1. **Dry Run (Test Mode)**
   ```bash
   ./archive-workspace-users.sh --dry-run
   ```
   Shows what would happen without making changes.

2. **Archive a Specific User**
   ```bash
   ./archive-workspace-users.sh --user john.doe@example.com
   ```

3. **Use Custom Organizational Unit**
   ```bash
   ./archive-workspace-users.sh --ou "/SuspendedUsers"
   ```

4. **Combine Options**
   ```bash
   ./archive-workspace-users.sh --dry-run --ou "/FormerEmployees/2024"
   ```

## Directory Structure

The script creates and manages the following directories:

```
.
├── archives/          # Final compressed backups (.tar.gz files)
├── temp/             # Working directory during backup (auto-cleaned)
├── logs/             # Detailed execution logs
└── reports/          # Human-readable summary reports
```

## Output Files

### Archive Files

- **Location**: `archives/`
- **Naming**: `user@domain.com_YYYYMMDD_HHMMSS.tar.gz`
- **Permissions**: 600 (read/write for owner only)
- **Contents**: Complete email backup from GYB

### Log Files

- **Location**: `logs/`
- **Naming**: `archive_YYYYMMDD_HHMMSS.log`
- **Contents**:
  - Timestamped events
  - GYB command output
  - Error messages
  - Processing details

### Report Files

- **Location**: `reports/`
- **Naming**: `archive_report_YYYYMMDD_HHMMSS.txt`
- **Contents**:
  - Execution summary
  - List of archives created with sizes
  - Success/failure statistics
  - Reference to detailed log

### Example Report

```
======================================
Google Workspace Archive Report
======================================
Timestamp: 2024-10-16 14:30:45
Status: COMPLETED
OU: /FormerEmployees

Archives Created:
--------------------------------------
  john.doe@example.com_20241016_143045.tar.gz - 2.34 GB
  jane.smith@example.com_20241016_144512.tar.gz - 1.87 GB

Summary:
  Total Users Processed: 2
  Successful: 2
  Failed: 0
  Skipped (Already Archived): 0

Full log: /path/to/logs/archive_20241016_143045.log
======================================
```

## Features in Detail

### Resume Capability

The script automatically skips users who already have archives, allowing you to:
- Resume interrupted operations
- Re-run the script safely without duplicating work
- Process new users added to the OU

### Real-Time Progress Monitoring

During GYB backups, the script displays real-time progress updates:
```
[INFO] Found 5925 message(s) to backup for user@example.com
[INFO] Progress: 500/5925 messages (8%)
[INFO] Progress: 1000/5925 messages (16%)
[INFO] Progress: 1500/5925 messages (25%)
...
[INFO] Progress: 5710/5925 messages (96%)
[SUCCESS] GYB backup completed for: user@example.com
```

Features:
- Shows total message count when backup starts
- Progress updates every 500 messages
- Displays both count and percentage
- No silent periods during long backups
- Background monitoring doesn't interfere with GYB

### Rate Limiting

- **Default delay**: 0 seconds (no delay between users for maximum speed)
- **Retry logic**: Automatically retries on rate limit errors
- **Max retries**: 3 attempts per user
- **Backoff**: 60 second delay on rate limit detection
- **Configurable**: Set `DELAY_BETWEEN_USERS` environment variable to add delays if needed

### Error Handling

- Strict error checking (`set -euo pipefail`)
- Graceful handling of Ctrl+C interruptions
- Continues processing remaining users if one fails
- Detailed error logging for troubleshooting
- Separate success/failure tracking

### Security

The script includes multiple layers of security protection:

**Input Validation:**
- OU path validation to prevent command injection attacks
- Email address format validation (regex)
- Path validation before `rm -rf` operations
- Rejects dangerous characters (quotes, semicolons, pipes, backticks, etc.)

**Access Controls:**
- Restrictive permissions on directories (700 - owner-only)
- Restrictive permissions on archive files (600)
- Secure handling of temporary files with automatic cleanup
- No sensitive data in logs (no passwords or tokens)

**Confirmation Requirements:**
- Requires typing exact OU path to confirm bulk operations
- Single-user mode requires yes/no confirmation
- Dry-run mode available for safe testing

**Audit Trail:**
- Logs execution user (USER), hostname (HOSTNAME)
- Logs working directory and GAM version
- Comprehensive timestamped logging of all operations
- Separate tracking of success/failure/skipped operations

**Credential Management:**
- Uses existing GAM/GYB OAuth configuration (not managed by this script)
- Credentials stored in ~/.gam/ with proper permissions (700)
- Service account files managed by GAM/GYB, not this script

**GAM Read-Only Usage:**
- GAM is used **ONLY** for read-only operations (querying users in target OU)
- The only GAM command used: `gam print users query "orgUnitPath='...'" fields primaryEmail,name.fullName`
- No modifications are made to your Google Workspace via GAM
- Always review GAM commands in any script before execution

## Performance Considerations

### Expected Duration

- **Small mailbox** (< 1 GB): 5-15 minutes
- **Medium mailbox** (1-10 GB): 15-45 minutes
- **Large mailbox** (> 10 GB): 45-120+ minutes

Total time depends on:
- Number of users
- Mailbox sizes
- Network speed
- Google API rate limits

### Disk Space

Ensure adequate disk space:
- Temporary storage: ~2x largest expected mailbox
- Archive storage: ~1x total of all mailboxes
- Recommended minimum: 50 GB free space

### Network Requirements

- Stable internet connection required throughout
- Recommended: 10+ Mbps download/upload speeds
- Avoid running on metered connections

## Troubleshooting

### Common Issues

1. **"GAM is not properly configured or accessible"**
   - GAM is not installed or not in PATH
   - Run `gam version` to verify installation
   - Check `GAMCFGDIR` environment variable if using custom location
   - Verify OAuth credentials in `~/.gam/oauth2.txt` exist
   - Re-run GAM initial setup if needed

2. **"GYB is not properly configured or accessible"**
   - GYB is not installed or not in PATH
   - Run `gyb --version` to verify installation
   - Verify service account configuration in GYB
   - Check that `~/.gam/oauth2service.json` exists
   - Ensure service account has required OAuth scopes

3. **"Failed to retrieve user list from GAM"**
   - Verify organizational unit path is correct
   - Test: `gam print orgs` to see available OUs
   - Test: `gam print users query "orgUnitPath='/FormerEmployees'"`
   - Check GAM authentication: `gam info domain`

4. **"GYB backup failed"**
   - Check detailed GYB logs in `logs/gyb_*.log`
   - Test GYB manually: `gyb --email test@domain.com --action estimate`
   - Verify service account has domain-wide delegation
   - Ensure all required OAuth scopes are granted

5. **Rate limit errors**
   - Script will automatically retry (up to 3 times)
   - Consider increasing `DELAY_BETWEEN_USERS`
   - May need to spread processing over multiple days

6. **Disk space issues**
   - Monitor available space during operation
   - Consider changing `ARCHIVE_BASE_DIR` to larger volume
   - Clean up old archives if needed

### Debug Mode

Enable verbose output:
```bash
bash -x ./archive-workspace-users.sh --dry-run
```

### Checking Logs

View real-time progress:
```bash
tail -f logs/archive_*.log
```

Search for errors:
```bash
grep ERROR logs/archive_*.log
```

## Maintenance

### Regular Tasks

1. **Monitor disk space**
   ```bash
   df -h archives/
   ```

2. **Clean old archives** (after verification)
   ```bash
   find archives/ -name "*.tar.gz" -mtime +365 -ls
   ```

3. **Verify archive integrity**
   ```bash
   tar -tzf archives/user@domain.com_*.tar.gz > /dev/null
   ```

4. **Review logs for errors**
   ```bash
   grep -i error logs/*.log
   ```

### Restoring from Archive

To restore a user's data:
```bash
# Extract archive
tar -xzf archives/user@domain.com_20241016_143045.tar.gz -C /tmp/restore

# Use GYB to restore (uses your configured GYB settings)
gyb --email user@domain.com --action restore --local-folder /tmp/restore/user@domain.com
```

GYB will use its configured service account automatically from `~/.gam/` or your `GAMCFGDIR` location.

## Automation

### Cron Job Example

Run weekly on Sunday at 2 AM:
```bash
0 2 * * 0 /path/to/archive-workspace-users.sh >> /var/log/archive-cron.log 2>&1
```

### Systemd Timer Example

Create `/etc/systemd/system/workspace-archive.service`:
```ini
[Unit]
Description=Google Workspace User Archive

[Service]
Type=oneshot
ExecStart=/path/to/archive-workspace-users.sh
User=backup
# Optional: Set custom GAM config directory
# Environment="GAMCFGDIR=/home/backup/.gam"
```

Create `/etc/systemd/system/workspace-archive.timer`:
```ini
[Unit]
Description=Weekly Google Workspace Archive

[Timer]
OnCalendar=Sun 02:00
Persistent=true

[Install]
WantedBy=timers.target
```

Enable:
```bash
systemctl enable workspace-archive.timer
systemctl start workspace-archive.timer
```

## Best Practices

1. **Review the Script**: Always review GAM commands in the script to verify read-only operations
2. **Verify GAM/GYB First**: Ensure they work before running this script
3. **Test First**: Always run with `--dry-run` first
4. **Single User Test**: Test with `--user` on a small mailbox
5. **Monitor Initial Runs**: Watch logs during first few executions
6. **Schedule Wisely**: Run during off-peak hours
7. **Verify Backups**: Periodically test archive restoration
8. **Document Changes**: Keep track of configuration changes
9. **Regular Reviews**: Review logs and reports monthly
10. **Disk Space**: Monitor and maintain adequate free space
11. **Version Control**: Track script changes in git
12. **Secure GAM Config**: Protect `~/.gam/` directory (chmod 700)
13. **Keep Tools Updated**: Regularly update GAM and GYB

## Security Notes

- GAM/GYB OAuth credentials are stored in `~/.gam/` (or `GAMCFGDIR`)
- Ensure proper permissions on GAM config directory:
  ```bash
  chmod 700 ~/.gam
  chmod 600 ~/.gam/*
  ```
- Service account files managed by GAM/GYB, not this script
- Consider encrypting archives for sensitive data
- Implement access controls on archive directory
- Regularly rotate service account keys in Google Cloud Console
- Audit access to archived data
- Follow your organization's data retention policies
- Never commit `~/.gam/` directory to version control

## Support

For issues or questions:
1. Check the troubleshooting section
2. Review detailed logs in `logs/`
3. Test with `--dry-run` mode
4. Verify all prerequisites are met

## License

This script is provided as-is for Google Workspace administration purposes.

## Version History

- **1.2.0** - Performance and UX improvements (Current)
  - **Added real-time progress monitoring** during GYB backups
    - Shows message count and percentage every 500 messages
    - Eliminates silent periods during long backups
    - Background polling avoids pipeline buffering issues
  - **Removed rate limiting delay** between users (0 seconds default for maximum speed)
  - **Switched to Solarized color palette** for improved terminal readability
    - Cyan INFO messages instead of hard-to-read dark blue
  - **Fixed TOTAL_USERS display** showing "of 0" (subshell variable scope issue)
  - **Fixed arithmetic increment errors** with `set -euo pipefail`
  - **Enhanced user feedback** throughout backup process
  - Users without Gmail licenses are gracefully skipped with clear messaging

- **1.1.0** - Security hardening release
  - **CRITICAL FIX**: Fixed subshell counter bug (reports now show correct statistics)
  - Added OU path validation to prevent command injection
  - Added email address format validation
  - Added path validation before file deletions
  - Enhanced confirmation (requires typing exact OU path)
  - Added single-user mode confirmation
  - Added audit trail logging (user, host, working directory)
  - Tightened directory permissions (750 → 700)
  - Automatic cleanup of temporary user list files
  - Removed disk space check (admin responsibility)
  - Changed default OU paths to remove spaces (/FormerEmployees, /SuspendedUsers)

- **1.0.0** - Initial release with full feature set
  - User discovery and confirmation
  - Sequential processing with rate limiting
  - Comprehensive logging and reporting
  - Resume capability
  - Dry-run mode
  - Single user mode
  - Error handling and retry logic
