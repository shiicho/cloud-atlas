#!/bin/bash
#==============================================================================
# notify_ops.sh - Operations Team Notification Script
#==============================================================================
# Usage: notify_ops.sh <STEP_NAME> <RC>
#
# This script sends alerts to operations team when batch jobs fail.
# Configure NOTIFICATION_METHOD and recipients for your environment.
#==============================================================================

# Source common functions
SCRIPT_DIR=$(dirname "$0")
source "${SCRIPT_DIR}/common.sh"

#------------------------------------------------------------------------------
# Configuration
#------------------------------------------------------------------------------
NOTIFICATION_METHOD="${NOTIFICATION_METHOD:-log}"  # log, email, slack
MAIL_TO="${MAIL_TO:-ops-team@example.com}"
SLACK_WEBHOOK="${SLACK_WEBHOOK:-}"
HOSTNAME=$(hostname)

#------------------------------------------------------------------------------
# Arguments
#------------------------------------------------------------------------------
STEP_NAME=${1:-"Unknown Step"}
RC=${2:-99}

#------------------------------------------------------------------------------
# Notification Functions
#------------------------------------------------------------------------------
notify_by_log() {
    log_error "=== ALERT: Batch Job Failed ==="
    log_error "Host: $HOSTNAME"
    log_error "Step: $STEP_NAME"
    log_error "Return Code: $RC"
    log_error "Time: $(date '+%Y-%m-%d %H:%M:%S')"
    log_error "=============================="
}

notify_by_email() {
    local SUBJECT="[ALERT] HULFT Batch Failed: $STEP_NAME (RC=$RC)"
    local BODY="
HULFT Batch Job Alert

Host: $HOSTNAME
Failed Step: $STEP_NAME
Return Code: $RC
Time: $(date '+%Y-%m-%d %H:%M:%S')

Please investigate immediately.

Log location: ${LOG_DIR}/batch.log
"

    # Check if mail command is available
    if command -v mail > /dev/null 2>&1; then
        echo "$BODY" | mail -s "$SUBJECT" "$MAIL_TO"
        log "Email notification sent to: $MAIL_TO"
    else
        log_warn "mail command not available, falling back to log notification"
        notify_by_log
    fi
}

notify_by_slack() {
    if [ -z "$SLACK_WEBHOOK" ]; then
        log_warn "SLACK_WEBHOOK not configured, falling back to log notification"
        notify_by_log
        return
    fi

    local PAYLOAD=$(cat <<EOF
{
    "text": ":rotating_light: *HULFT Batch Failed*",
    "attachments": [
        {
            "color": "danger",
            "fields": [
                {"title": "Host", "value": "$HOSTNAME", "short": true},
                {"title": "Step", "value": "$STEP_NAME", "short": true},
                {"title": "Return Code", "value": "$RC", "short": true},
                {"title": "Time", "value": "$(date '+%Y-%m-%d %H:%M:%S')", "short": true}
            ]
        }
    ]
}
EOF
)

    # Check if curl is available
    if command -v curl > /dev/null 2>&1; then
        curl -s -X POST -H 'Content-type: application/json' --data "$PAYLOAD" "$SLACK_WEBHOOK"
        log "Slack notification sent"
    else
        log_warn "curl not available, falling back to log notification"
        notify_by_log
    fi
}

#------------------------------------------------------------------------------
# Main
#------------------------------------------------------------------------------
main() {
    log "Sending notification for failed step: $STEP_NAME (RC=$RC)"

    case "$NOTIFICATION_METHOD" in
        email)
            notify_by_email
            ;;
        slack)
            notify_by_slack
            ;;
        log|*)
            notify_by_log
            ;;
    esac

    return 0
}

main
exit $?
