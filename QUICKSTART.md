# Quick Start Guide

Get started with the Google Workspace User Archive script in 5 minutes.

## Prerequisites

**IMPORTANT**: This script requires pre-installed and configured GAM and GYB. If you haven't set these up yet, stop here and configure them first. See the [GAM Installation Guide](https://github.com/GAM-team/GAM) and [GYB Installation Guide](https://github.com/GAM-team/got-your-back).

## Step 1: Verify GAM and GYB Configuration

Before using this script, verify that GAM and GYB are properly installed and configured:

### Test GAM Installation

```bash
# Check GAM version
gam version

# Verify GAM can access your domain
gam info domain

# Test listing users
gam print users maxResults 5
```

If any of these commands fail, you need to configure GAM first. GAM configuration is typically stored in `~/.gam/`.

### Test GYB Installation

```bash
# Check GYB version
gyb --version

# Test GYB with an estimate (doesn't actually download emails)
gyb --email test.user@yourdomain.com --action estimate
```

If GYB fails, ensure it's configured with a service account that has domain-wide delegation. GYB uses the same configuration directory as GAM (`~/.gam/` by default).

### Verify GAM Configuration Location

```bash
# Check default location
ls -la ~/.gam/

# Should see files like:
# - oauth2.txt (OAuth credentials)
# - oauth2service.json (Service account)
# - client_secrets.json (API credentials)
```

**Security Check:**
```bash
# Ensure proper permissions on GAM config
chmod 700 ~/.gam
chmod 600 ~/.gam/*
```

## Step 2: Download and Setup Script

```bash
# Clone the repository
git clone <repository-url>
cd archiving-gmail-users

# Make script executable
chmod +x archive-workspace-users.sh

# Verify script can find GAM and GYB
./archive-workspace-users.sh --help
```

## Step 3: Test with Dry Run

Test the script without making any changes:

```bash
./archive-workspace-users.sh --dry-run
```

This will:
- Verify GAM and GYB are accessible
- Check for users in the FormerEmployees OU
- Show what would be done (without actually doing it)
- Validate directory structure

If you see errors about GAM or GYB not being configured, return to Step 1.

## Step 4: Test with a Single User

Before processing all users, test with one account:

```bash
./archive-workspace-users.sh --user test.user@yourdomain.com
```

This verifies:
- GAM can query user information
- GYB can backup the user's email
- Compression works correctly
- Archive is created properly

Monitor the progress:
```bash
# In another terminal, watch the log
tail -f logs/archive_*.log
```

## Step 5: Archive All Users

Once the single user test succeeds:

```bash
./archive-workspace-users.sh
```

The script will:
1. Query GAM for all users in the FormerEmployees OU
2. Display the list of users
3. **Ask you to type the exact OU path** to confirm (security feature)
4. Process each user sequentially (with 30s delay between users)
5. Generate a comprehensive report

**Note:** You must type `/FormerEmployees` exactly - this prevents accidental archival of wrong OUs.

## Common First-Time Issues

### "GAM is not properly configured or accessible"

**Solution:**
```bash
# Verify GAM is in PATH
which gam

# Check GAM configuration
gam version
gam info domain

# If using custom config location
export GAMCFGDIR="/path/to/gam-config"
gam version
```

### "GYB is not properly configured or accessible"

**Solution:**
```bash
# Verify GYB is in PATH
which gyb

# Test GYB
gyb --version

# Check service account configuration
ls -l ~/.gam/oauth2service.json

# Test with a user
gyb --email test@domain.com --action estimate
```

### "Failed to retrieve user list from GAM"

**Solution:**
```bash
# Verify OU path
gam print orgs

# Check users in the OU
gam print users query "orgUnitPath='/FormerEmployees'"

# Verify GAM authentication
gam oauth info
```

### "GYB backup failed"

**Solution:**
```bash
# Check detailed GYB log
tail -50 logs/gyb_*.log

# Verify service account has domain-wide delegation
# Check in Google Cloud Console:
# IAM & Admin > Service Accounts > View delegated scopes

# Test GYB manually
gyb --email test@domain.com --action backup --local-folder /tmp/test-backup
```

## Configuration Tips

### Using Custom GAM Config Directory

If your GAM config is not in `~/.gam/`:

```bash
export GAMCFGDIR="/opt/gam-config"
./archive-workspace-users.sh
```

### Archiving a Specific OU

```bash
./archive-workspace-users.sh --ou "/SuspendedUsers"
```

### Testing Without Changes

```bash
./archive-workspace-users.sh --dry-run --ou "/FormerEmployees"
```

## What to Expect

### Time Estimates
- Small mailbox (< 1 GB): 5-15 minutes
- Medium mailbox (1-10 GB): 15-45 minutes
- Large mailbox (> 10 GB): 45-120+ minutes

### Disk Space Requirements
Ensure at least 2x the size of the largest mailbox is available.

### Rate Limiting
The script automatically waits 30 seconds between users to comply with Google API rate limits. This is normal and expected.

## Viewing Results

### Check the Report
```bash
cat reports/archive_report_*.txt
```

### View Logs in Real-Time
```bash
tail -f logs/archive_*.log
```

### List Created Archives
```bash
ls -lh archives/
```

### Verify Archive Integrity
```bash
tar -tzf archives/user@domain.com_*.tar.gz > /dev/null && echo "Archive OK"
```

## Quick Reference Commands

```bash
# Verify prerequisites
gam version && gyb --version

# Dry run
./archive-workspace-users.sh --dry-run

# Single user test
./archive-workspace-users.sh --user email@domain.com

# Archive all in FormerEmployees OU
./archive-workspace-users.sh

# Archive specific OU
./archive-workspace-users.sh --ou "/SuspendedUsers"

# Show help
./archive-workspace-users.sh --help

# Monitor progress
tail -f logs/archive_*.log

# Check disk space
df -h .

# Verify GAM config
ls -la ~/.gam/
gam info domain
```

## Troubleshooting Checklist

If something isn't working:

- [ ] GAM is installed and in PATH
- [ ] GYB is installed and in PATH
- [ ] `gam version` works
- [ ] `gam info domain` shows your domain
- [ ] `gyb --version` works
- [ ] `~/.gam/` directory exists with proper permissions (700)
- [ ] `~/.gam/oauth2service.json` exists (for GYB)
- [ ] Service account has domain-wide delegation enabled
- [ ] Adequate disk space available
- [ ] Stable internet connection

## Next Steps

1. Review the full [README.md](README.md) for advanced features
2. Set up automated backups (cron/systemd)
3. Establish a regular review schedule
4. Document your backup procedures
5. Test archive restoration process

## Safety Features

The script includes multiple layers of security and safety:

**Input Validation:**
- ✅ OU path validation (prevents command injection)
- ✅ Email address format validation
- ✅ Path validation before file deletions

**Confirmation & Control:**
- ✅ Must type exact OU path to confirm (not just "yes")
- ✅ Single-user mode requires confirmation
- ✅ Dry-run mode for safe testing
- ✅ Can be safely interrupted with Ctrl+C

**Operational Safety:**
- ✅ Uses existing GAM/GYB configuration (doesn't manage credentials)
- ✅ Skips already archived users (resume capability)
- ✅ Continues on individual user failures
- ✅ Detailed audit logging (user, host, timestamp)
- ✅ Automatic cleanup of temporary files
- ✅ Owner-only permissions (700/600)

## Getting Help

1. Check the error message in the console
2. Review the detailed log file in `logs/`
3. Verify GAM and GYB work independently:
   - `gam print users maxResults 1`
   - `gyb --email test@domain.com --action estimate`
4. Consult the [README.md](README.md) troubleshooting section
5. Verify all prerequisites are properly configured

## Important Reminders

- This script does NOT configure GAM or GYB
- GAM and GYB must be working BEFORE running this script
- OAuth credentials are managed by GAM/GYB in `~/.gam/`
- Never commit `~/.gam/` directory to version control
- Keep GAM and GYB updated regularly
- Test restore procedures periodically
