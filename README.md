# **Ubuntu Update and Reporter Script**

This directory contains `update_report.sh`, an automated Bash script designed for Ubuntu Server administration. The script automates package updates and upgrades, maintains a local log of all activities, provides detailed status reporting to a Google Chat webhook and/or an email recipient, and handles automated reboots when required by system updates.

## **Features**

1. **APT Cache Update:** Refreshes local package indexes.  
2. **Pre-Upgrade Analysis:** Captures the list of packages with updates available.  
3. **Non-Interactive Upgrade:** Safely applies upgrades using `DEBIAN_FRONTEND=noninteractive` to prevent blocking on prompts.  
4. **Post-Upgrade Parsing:** Extracts which packages were successfully upgraded and which packages were kept back by the system.  
5. **Reboot Detection:** Identifies if a reboot is required by the operating system.  
6. **Google Chat Integration:** Sends a formatted Markdown report to a specified Google Chat webhook.  
7. **Email Integration:** Sends a plain-text report to a specified email address.  
8. **Automated Maintenance:** Automatically rotates the local log file to retain only the most recent 1,000 lines.  
9. **Controlled Rebooting:** Optionally reboots the system immediately if required by updates and permitted by configuration.

## **Prerequisites**

To use all features of this script, ensure the following utilities are installed and configured on your Ubuntu Server.

### **1. Webhook Reporting (Required for Google Chat)**

The script uses curl to transmit JSON payloads to the Google Chat API.

* **Install curl:**  
  `sudo apt-get update && sudo apt-get install -y curl`

### **2. Email Reporting (Required for Email notifications)**

The script uses the local system's mail handler to route email alerts. You must install mailutils and a Mail Transfer Agent (MTA) such as postfix.

* **Install Mail Utilities and Postfix:**  
  `sudo apt-get update && sudo apt-get install -y mailutils postfix`

* **Configuration Note:** During the Postfix installation, you will be prompted to select a configuration type.  
  * For home or simple environments, **Internet Site** is typically used.  
  * Enter your system's fully qualified domain name (FQDN) or primary domain as the **System mail name**.  
  * Ensure your server has external outbound SMTP access permitted (e.g., port 25, 465, or 587 is not blocked by your ISP or firewall), or configure Postfix to use a relay host (like SendGrid, Mailgun, or Google Workspace SMTP relay).

## **Configuration**

Open the script (`update_report.sh`) and configure the variables in the **Configuration** block:

```
# Replace with your actual Google Chat Webhook URL (leave blank to disable)  
WEBHOOK_URL="https://chat.googleapis.com/v1/spaces/..."

# Email settings (leave TO_ADDRESS blank to disable email reports)  
TO_ADDRESS="user@domain.com"  
FROM_ADDRESS="hostname@domain.com"

# Set to 1 to allow automatic reboots, or 0 for manual reboots  
REBOOT_THE_SERVER=1
```

## **Deployment and Automation**

To schedule the script to run automatically every week:

1. Move the script to a system binary path:  
   `sudo mv update_report.sh /usr/local/bin/update_report.sh`

2. Make the script executable:  
   `sudo chmod +x /usr/local/bin/update_report.sh`

3. Open the root user's crontab:  
   `sudo crontab -e`

4. Add a cron job entry to execute the script weekly (e.g., every Sunday at 3:00 AM):  
   `0 3 * * 0 /usr/local/bin/update_report.sh`

## **Logging and Troubleshooting**

The script logs all activity, standard output, and standard error to the following path:

* `/var/log/server_update_manager.log`

If an upgrade fails, refer to this log file to inspect the raw output of the apt-get commands.
