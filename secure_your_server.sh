#! /bin/bash

set -euo pipefail
IFS=$'\n\t'

# --------------------------------------------------
# Constants
# --------------------------------------------------
# Global
CURRENT_DIR="$(realpath "$(dirname "${BASH_SOURCE[0]}")")"
ASSETS_DIR="$CURRENT_DIR/assets"
LOG_FILE="/var/log/secure_your_server.log"

# fail2ban
ASSETS_JAIL_LOCAL="$ASSETS_DIR/fail2ban/jail.local"
ASSETS_UFW_AGGRESSIVE_CONF="$ASSETS_DIR/fail2ban/ufw.aggressive.conf"
WORKING_FAIL2BAN_CONF="/etc/fail2ban/fail2ban.conf"
WORKING_JAIL_LOCAL_PATH="/etc/fail2ban/jail.local"
WORKING_UFW_AGGRESSIVE_CONF="/etc/fail2ban/filter.d/ufw.aggressive.conf"

# --------------------------------------------------
# Functions
# --------------------------------------------------
# Logging
log() {
    local level="$1"
    local message="$2"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [$level] $message" | tee -a "$LOG_FILE"
}

# Error handling
error_exit() {
    log "ERROR" "$1"
    exit 1
}

# Init
init() {
    log "INFO" "Initializing the server"
    sudo apt update -y
    sudo apt upgrade -y
    sudo apt install -y apprise
    sudo ufw logging medium
    log "INFO" "Initialization ended successfully"
}

# Install fail2ban
install_fail2ban() {
    log "INFO" "Installing fail2ban"
    sudo apt install fail2ban -y
    sudo systemctl start fail2ban
    sudo systemctl enable fail2ban
    log "INFO" "Installation of fail2ban ended successfully"
}

# Setup fail2ban
setup_fail2ban() {
    log "INFO" "Setting up fail2ban"
    # Set loglevel to INFO
    sudo sed -i.bak 's/^loglevel\s*=\s*.*/loglevel = INFO/' "$WORKING_FAIL2BAN_CONF" \
        || error_exit "Failed to set loglevel for fail2ban"
    # Increase dbpurgeage
    sudo sed -i.bak 's/^dbpurgeage\s*=\s*.*/dbpurgeage = 648000/' "$WORKING_FAIL2BAN_CONF" \
        || error_exit "Failed to edit dbpurgeage for fail2ban"
    # Copy configuration files
    sudo cp "$WORKING_JAIL_LOCAL_PATH" "$WORKING_JAIL_LOCAL_PATH.bak"
    sudo cp "$WORKING_UFW_AGGRESSIVE_CONF" "$WORKING_UFW_AGGRESSIVE_CONF.bak"
    sudo cp "$ASSETS_JAIL_LOCAL" "$WORKING_JAIL_LOCAL_PATH"
    sudo cp "$ASSETS_UFW_AGGRESSIVE_CONF" "$WORKING_UFW_AGGRESSIVE_CONF"
    # Set permissions
    sudo chmod 600 "$WORKING_JAIL_LOCAL_PATH" "$WORKING_UFW_AGGRESSIVE_CONF"
    sudo chown root:root "$WORKING_JAIL_LOCAL_PATH" "$WORKING_UFW_AGGRESSIVE_CONF"
    # Restart fail2ban
    sudo systemctl reload fail2ban \
        || error_exit "Failed to reload fail2ban.service"
    sudo systemctl restart fail2ban \
        || error_exit "Failed to restart fail2ban.service"
    log "INFO" "Fail2Ban setup completed"
}

# Check Fail2Ban health
check_fail2ban_health() {
    log "INFO" "Checking Fail2Ban health"
    if ! systemctl is-active --quiet fail2ban; then
        error_exit "Fail2Ban service is not running"
    fi
    if ! [ -r /var/log/fail2ban.log ]; then
        error_exit "Fail2Ban log file is not readable"
    fi
    log "INFO" "Fail2Ban health check passed"
}

# Main function
main() {
    init
    install_fail2ban
    setup_fail2ban
    check_fail2ban_health
}

# --------------------------------------------------
# Main
# --------------------------------------------------
main