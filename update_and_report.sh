#!/bin/bash

# ==============================================================================
# Script: update_and_report.sh
# Description: Automates apt updates, upgrades, and reports to Google Chat and Email.
# Steps:
#  1. Initialization: Check for root, rotate logs and log that we are starting.
#  2. Run Apt Update: Updates APT cache.
#  3. Check for upgradable packages: Creates a list of upgradable packages.
#  4. Run Apt Upgrade: Install upgradeable packets.
#  5. Check for Reboot Requirement.
#  6. Prepare the Report: Lists all packages with upgrades, which are 
#     upgraded and which are held back for inclusion in the log and report.
#  7. Send to Google Chat & Email: Sends the report to Google chat webhook and configured email address.
#  8. Reboot the server if needed and empowered to do so.
#
# ==============================================================================


# ----------------- Configuration -----------------

# Replace with your actual Google Chat Webhook URL, leave blank if you do not wish to use a webhook
WEBHOOK_URL=""

LOG_FILE="/var/log/server_update_manager.log"

MAX_LOG_LINES=1000

HOSTNAME=$(hostname)

# Email settings, leave TO_ADDRESS blank to not use email for reporting.
TO_ADDRESS=""
#Add your domain here after the @
FROM_ADDRESS="$HOSTNAME@domain.tld"

# Set this to 1 to allow this script to perform the reboot. 
# If set to 0 you will be alerted, but the server won't be rebooted.
REBOOT_THE_SERVER=1

# --------------- End Configuration ---------------

# ------------------- Functions -------------------

# Function to ensure script is run as root
check_root () {
    if [[ $EUID -ne 0 ]]; then
        echo "This script must be run as root"
        exit 1
    fi
}

# Function to keep only the most recent N lines of the log
rotate_logs() {
    if [ -f "$LOG_FILE" ]; then
        # Create a temporary file with the last N lines
        tail -n "$MAX_LOG_LINES" "$LOG_FILE" > "${LOG_FILE}.tmp"
        # Overwrite the original log file with the truncated version
        mv "${LOG_FILE}.tmp" "$LOG_FILE"
        chmod 644 "$LOG_FILE"
    fi
}

# Function to log and echo with dynamic timestamp
log_message() {
    local CURRENT_TIME
    CURRENT_TIME=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[$CURRENT_TIME] $1" | tee -a "$LOG_FILE"
}

# --------------- End of Functions ---------------

# --------------- 1. Initialization ---------------

# Check for root access
check_root

log_message "Starting updates on $HOSTNAME..."

# Perform log rotation
log_message "Rotating Log file..."
rotate_logs

# --------------- 2. Run Apt Update ---------------
# Refresh package cache before doing anything else.
log_message "Refreshing package repositories (apt-get update)..."
apt-get update -y >> "$LOG_FILE" 2>&1

# --------------- 3. Check for upgradable packages now that cache is fresh ---------------
log_message "Checking for available updates..."
UPGRADABLE_LIST=$(apt list --upgradable 2>/dev/null | grep -v "Listing...")

if [ -z "$UPGRADABLE_LIST" ]; then
    UPGRADABLE_SUMMARY="None"
else
    # Parse the list into a comma-separated format
    UPGRADABLE_SUMMARY=$(echo "$UPGRADABLE_LIST" | awk -F/ '{print $1}' | paste -sd ", " -)
fi

# --------------- 4. Run Apt Upgrade ---------------
log_message "Applying updates (apt-get upgrade)..."
# Using DEBIAN_FRONTEND=noninteractive to prevent prompts during cron execution
UPGRADE_OUTPUT=$(DEBIAN_FRONTEND=noninteractive apt-get upgrade -y 2>&1)
UPGRADE_STATUS=$?
echo "$UPGRADE_OUTPUT" >> "$LOG_FILE"

# Parsing the upgrade output for the report
# We use ^[^ ] to stop capture when a line does NOT start with a space (indented lists)
# Extract packages that were actually upgraded
ACTUALLY_UPGRADED=$(echo "$UPGRADE_OUTPUT" | awk '/The following packages will be upgraded:/{f=1;next} /^[^ ]/ {f=0} f' | xargs)
[ -z "$ACTUALLY_UPGRADED" ] && ACTUALLY_UPGRADED="None"

# Extract packages that were kept back
KEPT_BACK=$(echo "$UPGRADE_OUTPUT" | awk '/The following packages have been kept back:/{f=1;next} /^[^ ]/ {f=0} f' | xargs)
[ -z "$KEPT_BACK" ] && KEPT_BACK="None"

# --------------- 5. Check for Reboot Requirement ---------------
REBOOT_REQUIRED="✅ No"
[ -f /var/run/reboot-required ] && REBOOT_REQUIRED="⚠️ YES (Reboot Required)"

# --------------- 6. Prepare the Report ---------------
OUTCOME="❌ Failed (Check log: $LOG_FILE, exit code was $UPGRADE_STATUS)"
[ "$UPGRADE_STATUS" -eq 0 ] && OUTCOME="✅ Success"

# Format the message for Google Chat (JSON)
SUMMARY_VAL="${UPGRADABLE_SUMMARY:0:500}"
[[ ${#UPGRADABLE_SUMMARY} -gt 500 ]] && SUMMARY_VAL+="..."

UPGRADED_VAL="${ACTUALLY_UPGRADED:0:500}"
[[ ${#ACTUALLY_UPGRADED} -gt 500 ]] && UPGRADED_VAL+="..."

KEPT_VAL="${KEPT_BACK:0:500}"
[[ ${#KEPT_BACK} -gt 500 ]] && KEPT_VAL+="..."

# 6a. Google Chat JSON format (uses markdown bold notation and \n literals)
REPORT_TEXT="*Server Update Report: $HOSTNAME*\n"
REPORT_TEXT+="*Time:* $(date '+%Y-%m-%d %H:%M:%S')\n"
REPORT_TEXT+="*Outcome:* $OUTCOME\n"
REPORT_TEXT+="*Reboot Needed:* $REBOOT_REQUIRED\n\n"
REPORT_TEXT+="*Packages with Updates Available:* $SUMMARY_VAL\n\n"
REPORT_TEXT+="*Actually Upgraded:* $UPGRADED_VAL\n"
REPORT_TEXT+="*Packages Kept Back:* $KEPT_VAL"

# 6b. Plain Text Email Format (uses actual newlines and removes Chat markdown asterisks)
EMAIL_TEXT="Server Update Report: $HOSTNAME
Time: $(date '+%Y-%m-%d %H:%M:%S')
Outcome: $OUTCOME
Reboot Needed: $REBOOT_REQUIRED

Packages with Updates Available: $SUMMARY_VAL

Actually Upgraded: $UPGRADED_VAL
Packages Kept Back: $KEPT_VAL"

# --------------- 7. Send the Report ---------------

# 7a. Google Webhook
if [ -n "$WEBHOOK_URL" ]; then
    # Escape double quotes for JSON safety
    ESCAPED_TEXT=$(echo "$REPORT_TEXT" | sed 's/"/\\"/g')
    PAYLOAD=$(printf '{"text": "%s"}' "$ESCAPED_TEXT")

    log_message "Sending the report to Google Chat..."
    curl -s -X POST -H 'Content-Type: application/json; charset=UTF-8' \
        --data "$PAYLOAD" \
        "$WEBHOOK_URL" >> "$LOG_FILE" 2>&1
else
    log_message "Webhook URL not configured. Skipping notification..."
fi

#7b. Email Report
if [ -n "$TO_ADDRESS" ]; then
   # Sending report via email.
   log_message "Sending report to $TO_ADDRESS from $HOSTNAME <$FROM_ADDRESS>..."
   echo "$EMAIL_TEXT" | mail -s "Server Update Report for $HOSTNAME" "$TO_ADDRESS" -a "From: $HOSTNAME <$FROM_ADDRESS>"
else
   log_message "Email not configured or set for use. Skipping email notification..."
fi

# --------------- 8. Reboot the server if needed ---------------
if [ -f /var/run/reboot-required ]; then
    log_message "Reboot is required."
    
    if [ "$REBOOT_THE_SERVER" -eq 1 ]; then
        log_message "REBOOT_THE_SERVER is set to 1. Rebooting the system now..."
        log_message "--------------------------------------------------------------------------------------------"
        systemctl reboot >> "$LOG_FILE" 2>&1
    else
        log_message "REBOOT_THE_SERVER is set to 0. Skipping automatic reboot."
        log_message "--------------------------------------------------------------------------------------------"
    fi
else
    log_message "Update process completed. No reboot is needed."
    log_message "--------------------------------------------------------------------------------------------"
fi
