#!/bin/bash
# =============================================================================
# investigate.sh - Investigate the unauthorized change using ausearch
# =============================================================================
# Part of: Ghost Configuration Change Scenario
# Course: LX08-SECURITY Lesson 07 - auditd
# =============================================================================

set -e

echo "=========================================="
echo "Investigating SSH config change"
echo "=========================================="
echo ""

# Check if running as root
if [[ $EUID -ne 0 ]]; then
   echo "Error: This script must be run as root"
   echo "Usage: sudo bash investigate.sh"
   exit 1
fi

echo "=== Step 1: Confirm the unauthorized change ==="
echo ""
echo "Current PermitRootLogin setting:"
grep "^PermitRootLogin" /etc/ssh/sshd_config || echo "  (not explicitly set)"
echo ""

echo "File modification time:"
stat /etc/ssh/sshd_config | grep -E "Modify|Access|Change"
echo ""

echo "=== Step 2: Search audit logs by key ==="
echo ""
echo "Command: ausearch -k ssh_config_scenario --format text"
echo ""
echo "--- Audit Events ---"
ausearch -k ssh_config_scenario --format text 2>/dev/null || echo "No events found (audit rules may not have been set up)"
echo "--- End of Events ---"
echo ""

echo "=== Step 3: Interpret the key fields ==="
echo ""
echo "Looking for the most recent event..."
echo ""

# Get the raw event for detailed analysis
RAW_EVENT=$(ausearch -k ssh_config_scenario -ts recent --raw 2>/dev/null | grep "type=SYSCALL" | tail -1)

if [[ -n "$RAW_EVENT" ]]; then
    echo "Raw event:"
    echo "$RAW_EVENT" | fold -w 80
    echo ""

    # Extract key fields
    AUID=$(echo "$RAW_EVENT" | grep -oP 'auid=\K[0-9]+' || echo "unknown")
    UID_VAL=$(echo "$RAW_EVENT" | grep -oP ' uid=\K[0-9]+' | head -1 || echo "unknown")
    COMM=$(echo "$RAW_EVENT" | grep -oP 'comm="\K[^"]+' || echo "unknown")
    EXE=$(echo "$RAW_EVENT" | grep -oP 'exe="\K[^"]+' || echo "unknown")

    echo "=== Key Findings ==="
    echo ""
    echo "  auid (Audit User ID): $AUID"

    if [[ "$AUID" != "unknown" && "$AUID" != "4294967295" ]]; then
        AUID_NAME=$(getent passwd "$AUID" | cut -d: -f1 || echo "unknown")
        echo "  Original login user: $AUID_NAME"
    else
        echo "  Original login user: (system or unknown)"
    fi

    echo ""
    echo "  uid (Effective User ID): $UID_VAL"

    if [[ "$UID_VAL" != "unknown" ]]; then
        UID_NAME=$(getent passwd "$UID_VAL" | cut -d: -f1 || echo "unknown")
        echo "  Running as user: $UID_NAME"
    fi

    echo ""
    echo "  Command used: $COMM"
    echo "  Executable: $EXE"
    echo ""

    echo "=== Interpretation ==="
    echo ""
    if [[ "$AUID" != "unknown" && "$AUID" != "4294967295" ]]; then
        echo "  The user '$AUID_NAME' (auid=$AUID) modified sshd_config."
        echo ""
        echo "  Even though the command ran as uid=$UID_VAL ($UID_NAME),"
        echo "  the auid tells us the ORIGINAL user who logged in was '$AUID_NAME'."
        echo ""
        echo "  This is the key value of auid: it tracks who is responsible"
        echo "  for an action, even after sudo or su."
    else
        echo "  Could not determine the original user."
        echo "  This might happen if:"
        echo "    - The action was taken by a system process"
        echo "    - The audit rules were not properly configured"
        echo "    - The session was started before auditd"
    fi
else
    echo "No SYSCALL events found for ssh_config_scenario."
    echo ""
    echo "Possible reasons:"
    echo "  1. Audit rules were not set up (run setup-audit.sh first)"
    echo "  2. No changes were made to sshd_config (run simulate-change.sh)"
    echo "  3. auditd was not running during the change"
fi

echo ""
echo "=== Step 4: Timeline reconstruction ==="
echo ""

if [[ -n "$AUID" && "$AUID" != "unknown" && "$AUID" != "4294967295" ]]; then
    echo "All actions by user with auid=$AUID in the last hour:"
    echo ""
    echo "Command: ausearch -ua $AUID -ts '1 hour ago' --format text | head -50"
    echo ""
    ausearch -ua "$AUID" -ts "1 hour ago" --format text 2>/dev/null | head -50 || echo "No events found"
fi

echo ""
echo "=========================================="
echo "Investigation complete!"
echo "=========================================="
echo ""
echo "Summary:"
if [[ -n "$AUID_NAME" && "$AUID_NAME" != "unknown" ]]; then
    echo "  - Responsible user: $AUID_NAME"
    echo "  - Action: Modified /etc/ssh/sshd_config"
    echo "  - Tool used: $COMM"
fi
echo ""
echo "Next step: Generate an incident report using the template"
echo "           See: incident-report-template.md"
echo ""
echo "Don't forget to run cleanup.sh to restore the configuration!"
echo ""
