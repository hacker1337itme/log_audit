#!/bin/bash

# Script: Log Auditor
# Description: Extracts and compresses log files for a specified date range
# Author: System Administrator
# Version: 2.0

# Exit immediately if a command exits with a non-zero status
set -e

# Configuration Section
CONFIG_FILE="/etc/log_audit.conf"

# Load configuration if exists
if [ -f "$CONFIG_FILE" ]; then
    source "$CONFIG_FILE"
else
    # Default configuration
    LOG_DIRS=("/var/log" "/var/log/audit")
    LOG_PATTERNS=("*.log" "*.log.*" "syslog*" "messages*" "secure*")
    LOG_LEVELS=("DEBUG" "INFO" "WARN" "ERROR" "CRITICAL")
    START_DATE="2022-01-01"
    END_DATE="2022-01-31"
    OUTPUT_DIR="/secure/audit_logs"
    TEMP_DIR="/tmp/log_audit_$(date +%Y%m%d_%H%M%S)"
    MAX_LOG_SIZE="100M"
    RETENTION_DAYS=30
fi

# Timestamp for unique file naming
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
OUTPUT_FILE="${OUTPUT_DIR}/audit_${TIMESTAMP}.log"
LOCK_FILE="/tmp/log_audit.lock"

# Function to display usage
usage() {
    echo "Usage: $0 [options]"
    echo "Options:"
    echo "  -s, --start-date DATE    Start date (YYYY-MM-DD)"
    echo "  -e, --end-date DATE      End date (YYYY-MM-DD)"
    echo "  -o, --output-dir DIR     Output directory"
    echo "  -l, --log-level LEVEL    Log level to filter"
    echo "  -h, --help               Display this help message"
    exit 1
}

# Function to parse command line arguments
parse_args() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            -s|--start-date)
                START_DATE="$2"
                shift 2
                ;;
            -e|--end-date)
                END_DATE="$2"
                shift 2
                ;;
            -o|--output-dir)
                OUTPUT_DIR="$2"
                shift 2
                ;;
            -l|--log-level)
                LOG_LEVEL="$2"
                shift 2
                ;;
            -h|--help)
                usage
                ;;
            *)
                echo "Unknown option: $1"
                usage
                ;;
        esac
    done
}

# Function to check if date is valid
validate_date() {
    local date=$1
    if ! date -d "$date" >/dev/null 2>&1; then
        echo "Error: Invalid date format: $date. Use YYYY-MM-DD"
        exit 1
    fi
}

# Function to check dependencies
check_dependencies() {
    local dependencies=("zgrep" "gzip" "find" "date")
    for cmd in "${dependencies[@]}"; do
        if ! command -v "$cmd" >/dev/null 2>&1; then
            echo "Error: Required command '$cmd' not found"
            exit 1
        fi
    done
}

# Function to ensure directories exist
setup_directories() {
    mkdir -p "$OUTPUT_DIR"
    mkdir -p "$TEMP_DIR"
    
    # Check write permissions
    if [ ! -w "$OUTPUT_DIR" ]; then
        echo "Error: No write permission for output directory: $OUTPUT_DIR"
        exit 1
    fi
}

# Function to acquire lock
acquire_lock() {
    if [ -e "$LOCK_FILE" ]; then
        echo "Error: Script is already running. Lock file exists: $LOCK_FILE"
        exit 1
    fi
    echo $$ > "$LOCK_FILE"
    trap 'rm -f "$LOCK_FILE"; exit' INT TERM EXIT
}

# Function to convert date to epoch for comparison
date_to_epoch() {
    date -d "$1" +%s 2>/dev/null || date -j -f "%Y-%m-%d" "$1" +%s 2>/dev/null
}

# Function to extract logs from a file
extract_logs_from_file() {
    local log_file="$1"
    local temp_output="$2"
    
    echo "Processing: $log_file" >> "${TEMP_DIR}/processing.log"
    
    # Handle compressed files
    if [[ "$log_file" == *.gz ]] || [[ "$log_file" == *.bz2 ]] || [[ "$log_file" == *.xz ]]; then
        local decompress_cmd
        case "$log_file" in
            *.gz) decompress_cmd="zcat" ;;
            *.bz2) decompress_cmd="bzcat" ;;
            *.xz) decompress_cmd="xzcat" ;;
        esac
        
        if command -v "$decompress_cmd" >/dev/null 2>&1; then
            $decompress_cmd "$log_file" 2>/dev/null | \
            awk -v start_date="$START_DATE" -v end_date="$END_DATE" -v log_level="$LOG_LEVEL" '
                $1 ~ /^[0-9]{4}-[0-9]{2}-[0-9]{2}/ {
                    log_date = $1
                    if (log_date >= start_date && log_date <= end_date) {
                        if (log_level == "" || $0 ~ log_level) {
                            print
                        }
                    }
                }
            ' >> "$temp_output"
        fi
    else
        # Handle regular text files
        awk -v start_date="$START_DATE" -v end_date="$END_DATE" -v log_level="$LOG_LEVEL" '
            $1 ~ /^[0-9]{4}-[0-9]{2}-[0-9]{2}/ {
                log_date = $1
                if (log_date >= start_date && log_date <= end_date) {
                    if (log_level == "" || $0 ~ log_level) {
                        print
                    }
                }
            }
        ' "$log_file" >> "$temp_output" 2>/dev/null
    fi
}

# Function to cleanup old files
cleanup_old_files() {
    echo "Cleaning up files older than $RETENTION_DAYS days in $OUTPUT_DIR"
    find "$OUTPUT_DIR" -name "audit_*.log.gz" -type f -mtime +$RETENTION_DAYS -delete 2>/dev/null || true
}

# Main execution
main() {
    # Parse command line arguments
    parse_args "$@"
    
    # Validate dates
    validate_date "$START_DATE"
    validate_date "$END_DATE"
    
    # Check dependencies
    check_dependencies()
    
    # Convert dates to epoch for comparison
    START_EPOCH=$(date_to_epoch "$START_DATE")
    END_EPOCH=$(date_to_epoch "$END_DATE")
    
    if [ "$START_EPOCH" -gt "$END_EPOCH" ]; then
        echo "Error: Start date cannot be after end date"
        exit 1
    fi
    
    # Acquire lock to prevent multiple executions
    acquire_lock
    
    # Setup directories
    setup_directories
    
    # Create temporary output file
    TEMP_OUTPUT="${TEMP_DIR}/extracted.log"
    > "$TEMP_OUTPUT"
    
    echo "Starting log audit at $(date)"
    echo "Period: $START_DATE to $END_DATE"
    if [ -n "$LOG_LEVEL" ]; then
        echo "Log level filter: $LOG_LEVEL"
    fi
    echo "Output directory: $OUTPUT_DIR"
    
    # Find and process log files
    total_files=0
    processed_files=0
    
    for log_dir in "${LOG_DIRS[@]}"; do
        if [ -d "$log_dir" ]; then
            for pattern in "${LOG_PATTERNS[@]}"; do
                while IFS= read -r log_file; do
                    ((total_files++))
                    if [ -s "$log_file" ] && [ -r "$log_file" ]; then
                        extract_logs_from_file "$log_file" "$TEMP_OUTPUT"
                        ((processed_files++))
                    else
                        echo "Skipping (unreadable or empty): $log_file" >> "${TEMP_DIR}/skipped.log"
                    fi
                done < <(find "$log_dir" -type f -name "$pattern" 2>/dev/null)
            done
        fi
    done
    
    # Check if we extracted any data
    if [ ! -s "$TEMP_OUTPUT" ]; then
        echo "No logs found for the specified criteria"
        echo "No logs found for period $START_DATE to $END_DATE" > "$TEMP_OUTPUT"
    fi
    
    # Compress the output
    echo "Compressing output..."
    gzip -c "$TEMP_OUTPUT" > "${OUTPUT_FILE}.gz"
    
    # Generate summary report
    SUMMARY_FILE="${OUTPUT_DIR}/audit_summary_${TIMESTAMP}.txt"
    {
        echo "=== Log Audit Summary ==="
        echo "Timestamp: $(date)"
        echo "Audit Period: $START_DATE to $END_DATE"
        echo "Log Level Filter: ${LOG_LEVEL:-None}"
        echo "Total Files Found: $total_files"
        echo "Files Processed: $processed_files"
        echo "Output File: ${OUTPUT_FILE}.gz"
        echo "File Size: $(du -h "${OUTPUT_FILE}.gz" | cut -f1)"
        echo "Lines Extracted: $(wc -l < "$TEMP_OUTPUT")"
    } > "$SUMMARY_FILE"
    
    # Cleanup temporary files
    rm -rf "$TEMP_DIR"
    
    # Cleanup old audit files
    cleanup_old_files
    
    # Release lock
    rm -f "$LOCK_FILE"
    
    echo "Audit completed successfully"
    echo "Output: ${OUTPUT_FILE}.gz"
    echo "Summary: $SUMMARY_FILE"
}

# Execute main function
main "$@"
