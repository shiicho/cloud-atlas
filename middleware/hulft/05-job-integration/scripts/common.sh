#!/bin/bash
#==============================================================================
# common.sh - HULFT Batch Processing Common Functions
#==============================================================================
# Source this file in other scripts:
#   source /opt/batch/daily_report/scripts/common.sh
#==============================================================================

# Configuration
HULFT_HOME=${HULFT_HOME:-/opt/hulft8}
BATCH_HOME=${BATCH_HOME:-/opt/batch/daily_report}
LOG_DIR="${BATCH_HOME}/logs/$(date '+%Y%m%d')"

# Create log directory if needed
mkdir -p "$LOG_DIR"

#------------------------------------------------------------------------------
# Logging Functions
#------------------------------------------------------------------------------
log() {
    local MESSAGE=$1
    local TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[$TIMESTAMP] INFO: $MESSAGE" | tee -a "${LOG_DIR}/batch.log"
}

log_error() {
    local MESSAGE=$1
    local TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[$TIMESTAMP] ERROR: $MESSAGE" | tee -a "${LOG_DIR}/batch.log" >&2
}

log_warn() {
    local MESSAGE=$1
    local TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[$TIMESTAMP] WARN: $MESSAGE" | tee -a "${LOG_DIR}/batch.log"
}

#------------------------------------------------------------------------------
# HULFT Status Check
#------------------------------------------------------------------------------
check_hulft_running() {
    if ! ${HULFT_HOME}/bin/hulstat > /dev/null 2>&1; then
        log_error "HULFT is not running"
        return 8
    fi
    return 0
}

#------------------------------------------------------------------------------
# Disk Space Check
#------------------------------------------------------------------------------
check_disk_space() {
    local PATH_TO_CHECK=${1:-${HULFT_HOME}/spool}
    local THRESHOLD=${2:-90}

    local USAGE=$(df "$PATH_TO_CHECK" | tail -1 | awk '{print $5}' | tr -d '%')

    if [ "$USAGE" -gt "$THRESHOLD" ]; then
        log_error "Disk usage at ${USAGE}% exceeds threshold ${THRESHOLD}%"
        return 8
    fi

    log "Disk usage OK: ${USAGE}%"
    return 0
}

#------------------------------------------------------------------------------
# File Existence Check
#------------------------------------------------------------------------------
check_file_exists() {
    local FILE=$1
    if [ ! -f "$FILE" ]; then
        log_error "File not found: $FILE"
        return 8
    fi
    return 0
}

#------------------------------------------------------------------------------
# RC Handling Helper
#------------------------------------------------------------------------------
handle_rc() {
    local RC=$1
    local STEP_NAME=$2

    case $RC in
        0)
            log "$STEP_NAME completed successfully (RC=0)"
            return 0
            ;;
        4)
            log_warn "$STEP_NAME completed with warning (RC=4)"
            return 4
            ;;
        *)
            log_error "$STEP_NAME failed (RC=$RC)"
            return 8
            ;;
    esac
}
