# log_audit
log_audit 

## Key Improvements Made:

### 1. **Better Error Handling**
- Added `set -e` to exit on errors
- Added validation for dates and directories
- Added file permission checks

### 2. **Command Line Arguments**
- Added option parsing for flexibility
- Can override defaults via command line

### 3. **Configuration File Support**
- Can load settings from `/etc/log_audit.conf`
- Separates configuration from code

### 4. **Improved Log Processing**
- Uses `awk` for more reliable date range filtering
- Handles multiple compression formats (gz, bz2, xz)
- Processes multiple log directories and patterns

### 5. **Locking Mechanism**
- Prevents multiple instances from running simultaneously
- Ensures data integrity

### 6. **Temporary File Management**
- Creates unique temp directories
- Proper cleanup on exit

### 7. **Better File Discovery**
- Searches multiple directories and patterns
- Handles permission issues gracefully

### 8. **Summary Reporting**
- Generates detailed summary of the audit
- Includes statistics about processed files

### 9. **Retention Policy**
- Automatically cleans up old audit files
- Configurable retention period

### 10. **Dependency Checking**
- Verifies required tools are available
- Provides clear error messages

## Usage Examples:

```bash
# Basic usage with defaults
./log_audit.sh

# Custom date range
./log_audit.sh --start-date 2023-01-01 --end-date 2023-01-15

# Specify output directory
./log_audit.sh --output-dir /backups/audit_logs

# Filter by log level
./log_audit.sh --log-level ERROR

# Show help
./log_audit.sh --help
```

## Configuration File Example (`/etc/log_audit.conf`):

```bash
# Log directories to search
LOG_DIRS=("/var/log" "/var/log/audit" "/opt/application/logs")

# Log file patterns
LOG_PATTERNS=("*.log" "*.log.*" "syslog*" "messages*")

# Default date range (can be overridden by command line)
START_DATE="2023-01-01"
END_DATE="2023-12-31"

# Output directory
OUTPUT_DIR="/secure/audit_logs"

# Retention period in days
RETENTION_DAYS=90
```
