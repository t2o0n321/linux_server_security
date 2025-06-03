#! /bin/bash
# Refer https://gist.github.com/mirajehossain/59c6e62fcdc84ca1e28b6a048038676c

set -euo pipefail
IFS=$'\n\t'

# --------------------------------------------------
# Arts
# --------------------------------------------------
ARTS_TITLE=$(cat <<EOF
    ██╗                                                           
   ██╔╝                                                           
  ██╔╝█████╗█████╗█████╗█████╗█████╗█████╗█████╗█████╗█████╗█████╗
 ██╔╝ ╚════╝╚════╝╚════╝╚════╝╚════╝╚════╝╚════╝╚════╝╚════╝╚════╝
██╔╝███████╗███████╗██████╗ ██╗   ██╗███████╗██████╗              
╚═╝ ██╔════╝██╔════╝██╔══██╗██║   ██║██╔════╝██╔══██╗             
    ███████╗█████╗  ██████╔╝██║   ██║█████╗  ██████╔╝             
    ╚════██║██╔══╝  ██╔══██╗╚██╗ ██╔╝██╔══╝  ██╔══██╗             
    ███████║███████╗██║  ██║ ╚████╔╝ ███████╗██║  ██║             
    ╚══════╝╚══════╝╚═╝  ╚═╝  ╚═══╝  ╚══════╝╚═╝  ╚═╝             
███████╗███████╗ ██████╗██╗   ██╗██████╗ ██╗████████╗██╗   ██╗    
██╔════╝██╔════╝██╔════╝██║   ██║██╔══██╗██║╚══██╔══╝╚██╗ ██╔╝    
███████╗█████╗  ██║     ██║   ██║██████╔╝██║   ██║    ╚████╔╝     
╚════██║██╔══╝  ██║     ██║   ██║██╔══██╗██║   ██║     ╚██╔╝      
███████║███████╗╚██████╗╚██████╔╝██║  ██║██║   ██║      ██║    ██╗
╚══════╝╚══════╝ ╚═════╝ ╚═════╝ ╚═╝  ╚═╝╚═╝   ╚═╝      ╚═╝   ██╔╝
█████╗█████╗█████╗█████╗█████╗█████╗█████╗█████╗█████╗█████╗ ██╔╝ 
╚════╝╚════╝╚════╝╚════╝╚════╝╚════╝╚════╝╚════╝╚════╝╚════╝██╔╝  
                                                           ██╔╝   
                                                           ╚═╝    
EOF
)

# --------------------------------------------------
# Constants
# --------------------------------------------------
# Global
CURRENT_DIR="$(realpath "$(dirname "${BASH_SOURCE[0]}")")"
ASSETS_DIR="$CURRENT_DIR/assets"
LOG_FILE="/var/log/secure_your_server.log"

# Auto-confirm flag
AUTO_CONFIRM=0
while getopts "y" opt; do
    case "$opt" in
        y) AUTO_CONFIRM=1 ;;
        *) echo "Usage: $0 [-y]"; exit 1 ;;
    esac
done

# fail2ban
ASSETS_JAIL_LOCAL="$ASSETS_DIR/fail2ban/jail.local"
ASSETS_UFW_AGGRESSIVE_CONF="$ASSETS_DIR/fail2ban/ufw.aggressive.conf"
WORKING_FAIL2BAN_CONF="/etc/fail2ban/fail2ban.conf"
WORKING_JAIL_LOCAL_PATH="/etc/fail2ban/jail.local"
WORKING_UFW_AGGRESSIVE_CONF="/etc/fail2ban/filter.d/ufw.aggressive.conf"

# Shared Memory
WORKING_FSTAB="/etc/fstab"
WORKING_SYSCTL_CONF="/etc/sysctl.conf"
WORKING_SHM="/run/shm"
MOUNT_ACTION="tmpfs /run/shm tmpfs defaults,noexec,nosuid,nodev 0 0"
KERNEL_SHMMAX=16777216
KERNEL_SHMALL=4096

# Remove insecure services
INSECURE_SERVICES=(
    "xinetd"
    "nis"
    "yp-tools"
    "tftpd"
    "atftpd"
    "tftpd-hpa"
    "telnetd"
    "rsh-server"
    "rsh-redone-server"
)

# SSH configuration file and setting
SSH_CONFIG="/etc/ssh/sshd_config"
SSH_PERMIT_ROOT_LOGIN="PermitRootLogin no"

# --------------------------------------------------
# Functions
# --------------------------------------------------
# Get timestamp
get_timestamp() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')]"
}

# Check permission
check_permission() {
    if [ "$EUID" -ne 0 ]; then
        echo "$(get_timestamp) This script should be run as root or with sudo."
        exit 1
    fi
}

# Logging
log() {
    local level="$1"
    local message="$2"
    echo "$(get_timestamp) [$level] $message" | tee -a "$LOG_FILE"
}

# Error handling
error_exit() {
    log "ERROR" "$1"
    exit 1
}

# User confirmation
confirm() {
    local splitline_length=100
    local prompt_message="$1"
    local log_message="$2"
    log "INFO" "$log_message"

    # Skip prompt if AUTO_CONFIRM is set
    if [ "$AUTO_CONFIRM" -eq 1 ]; then
        log "INFO" "Auto-confirmed with -y flag: Proceeding with action"
        return 0
    fi
    
    # Display prompt message
    echo
    printf '%*s\n' "$splitline_length" | tr ' ' '='
    echo "WARNING: $prompt_message"
    printf '%*s\n' "$splitline_length" | tr ' ' '='
    echo
    echo "Enter 'yes' or 'y' to proceed, or any other input to skip:"
    
    local response
    read -r response
    case "$response" in
        [yY][eE][sS]|[yY])
            log "INFO" "User confirmed: Proceeding with action"
            return 0
            ;;
        *)
            log "INFO" "User declined: Action skipped"
            return 1
            ;;
    esac
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

# Secure shared memory
secure_shared_memory() {
    log "INFO" "Starting shared memory hardening process"
    
    # -----------------------------------------------
    # Configure /run/shm mount options in /etc/fstab
    # -----------------------------------------------
    # Backup fstab to prevent data loss
    log "INFO" "Backing up $WORKING_FSTAB"
    sudo cp "$WORKING_FSTAB" "$WORKING_FSTAB.bak" \
        || error_exit "Failed to backup $WORKING_FSTAB"
    
    # Check if /run/shm entry exists in fstab
    if grep -q "^tmpfs.*$WORKING_SHM" "$WORKING_FSTAB"; then
        log "INFO" "Updating existing /run/shm entry in $WORKING_FSTAB"
        sudo sed -i.bak "s|^tmpfs.*$WORKING_SHM.*|$MOUNT_ACTION|" "$WORKING_FSTAB" \
            || error_exit "Failed to update /run/shm entry in $WORKING_FSTAB"
    else
        log "INFO" "Appending new /run/shm entry to $WORKING_FSTAB"
        echo "$MOUNT_ACTION" | sudo tee -a "$WORKING_FSTAB" > /dev/null \
            || error_exit "Failed to append /run/shm entry to $WORKING_FSTAB"
    fi
    
    # Verify the fstab entry
    if ! grep -q "^$MOUNT_ACTION" "$WORKING_FSTAB"; then
        error_exit "Failed to verify /run/shm entry in $WORKING_FSTAB"
    fi
    log "INFO" "Applied noexec,nosuid,nodev,size=256m to $WORKING_SHM in $WORKING_FSTAB"
    
    # Remount /run/shm to apply changes immediately
    log "INFO" "Remounting $WORKING_SHM to apply mount options"
    sudo mount -o remount "$WORKING_SHM" || error_exit "Failed to remount $WORKING_SHM"
    
    # -----------------------------------------------
    # Limit System V IPC shared memory usage
    # -----------------------------------------------
    # Backup sysctl.conf to prevent data loss
    log "INFO" "Backing up $WORKING_SYSCTL_CONF"
    sudo cp "$WORKING_SYSCTL_CONF" "$WORKING_SYSCTL_CONF.bak" \
        || error_exit "Failed to backup $WORKING_SYSCTL_CONF"
    
    # Update or append kernel.shmmax
    if grep -q "^kernel.shmmax" "$WORKING_SYSCTL_CONF"; then
        log "INFO" "Updating existing kernel.shmmax in $WORKING_SYSCTL_CONF"
        sudo sed -i.bak "s|^kernel.shmmax.*|kernel.shmmax=$KERNEL_SHMMAX|" "$WORKING_SYSCTL_CONF" \
            || error_exit "Failed to update kernel.shmmax in $WORKING_SYSCTL_CONF"
    else
        log "INFO" "Appending kernel.shmmax to $WORKING_SYSCTL_CONF"
        echo "kernel.shmmax=$KERNEL_SHMMAX" | sudo tee -a "$WORKING_SYSCTL_CONF" > /dev/null \
            || error_exit "Failed to append kernel.shmmax to $WORKING_SYSCTL_CONF"
    fi
    
    # Update or append kernel.shmall
    if grep -q "^kernel.shmall" "$WORKING_SYSCTL_CONF"; then
        log "INFO" "Updating existing kernel.shmall in $WORKING_SYSCTL_CONF"
        sudo sed -i.bak "s|^kernel.shmall.*|kernel.shmall=$KERNEL_SHMALL|" "$WORKING_SYSCTL_CONF" \
            || error_exit "Failed to update kernel.shmall in $WORKING_SYSCTL_CONF"
    else
        log "INFO" "Appending kernel.shmall to $WORKING_SYSCTL_CONF"
        echo "kernel.shmall=$KERNEL_SHMALL" | sudo tee -a "$WORKING_SYSCTL_CONF" > /dev/null \
            || error_exit "Failed to append kernel.shmall to $WORKING_SYSCTL_CONF"
    fi
    
    # Verify sysctl entries
    if ! grep -q "^kernel.shmmax=$KERNEL_SHMMAX" "$WORKING_SYSCTL_CONF" || \
       ! grep -q "^kernel.shmall=$KERNEL_SHMALL" "$WORKING_SYSCTL_CONF"; then
        error_exit "Failed to verify sysctl entries in $WORKING_SYSCTL_CONF"
    fi
    
    # Apply sysctl changes
    log "INFO" "Applying sysctl changes"
    sudo sysctl -p "$WORKING_SYSCTL_CONF" || error_exit "Failed to apply sysctl changes"
    log "INFO" "Limited System V IPC shared memory usage (shmmax=$KERNEL_SHMMAX, shmall=$KERNEL_SHMALL)"
    
    # -----------------------------------------------
    # Restrict /run/shm access to root and sudo group
    # -----------------------------------------------
    log "INFO" "Setting permissions (750) and ownership (root:sudo) on $WORKING_SHM"
    sudo chmod 750 "$WORKING_SHM" || error_exit "Failed to set permissions on $WORKING_SHM"
    sudo chown root:sudo "$WORKING_SHM" || error_exit "Failed to set ownership of $WORKING_SHM"
    
    # Verify permissions and ownership
    local perms owner
    perms=$(stat -c "%a" "$WORKING_SHM")
    owner=$(stat -c "%U:%G" "$WORKING_SHM")
    if [ "$perms" != "750" ] || [ "$owner" != "root:sudo" ]; then
        error_exit "Failed to verify permissions (750) or ownership (root:sudo) on $WORKING_SHM"
    fi
    log "INFO" "Restricted $WORKING_SHM access to root and sudo group"
    
    log "INFO" "Shared memory hardening completed successfully"
}

# Remove insecure services
remove_insecure_services() {
    log "INFO" "Removing insecure services: ${INSECURE_SERVICES[*]}"
    sudo apt --purge remove -y "${INSECURE_SERVICES[@]}" \
        || error_exit "Failed to remove insecure services"

    # Verify removal by checking if packages are still installed
    local pattern=$(IFS="|"; echo "${INSECURE_SERVICES[*]}")
    if dpkg -l | grep -E "$pattern" > /dev/null; then
        error_exit "Some insecure services could not be fully removed"
    fi
    log "INFO" "Insecure services removed successfully"
}

disable_root_ssh() {
    local prompt_message=$(cat << EOF
Disabling root SSH login requires a non-root user with sudo privileges to avoid lockout.
On Vultr VPS, the default 'ubuntu' user has sudo privileges. Ensure you have another sudo user.
Do you want to disable root SSH login? (yes/no)
EOF
)
    local log_message="Prompting user to disable root SSH login"

    log "INFO" "Disabling root SSH login"

    # Confirm before making changes
    confirm "$prompt_message" "$log_message"

    # Backup sshd_config
    sudo cp "$SSH_CONFIG" "$SSH_CONFIG.bak" \
        || error_exit "Failed to backup $SSH_CONFIG"

    # Check if PermitRootLogin is already set, and update or append it
    if grep -q "^PermitRootLogin" "$SSH_CONFIG"; then
        sudo sed -i.bak "s/^PermitRootLogin.*/$PERMIT_ROOT_LOGIN/" "$SSH_CONFIG" \
            || error_exit "Failed to update PermitRootLogin in $SSH_CONFIG"
    else
        echo "$PERMIT_ROOT_LOGIN" | sudo tee -a "$SSH_CONFIG" > /dev/null \
            || error_exit "Failed to append PermitRootLogin to $SSH_CONFIG"
    fi

    # Verify the setting
    if ! grep -q "^$PERMIT_ROOT_LOGIN" "$SSH_CONFIG"; then
        error_exit "Failed to verify PermitRootLogin setting in $SSH_CONFIG"
    fi

    # Restart SSH service to apply changes
    sudo /etc/init.d/ssh restart || error_exit "Failed to restart sshd service"
    log "INFO" "Root SSH login disabled successfully"
}

# Main function
main() {
    # Show arts and check permission
    echo "$ARTS_TITLE"
    check_permission

    # Init
    init

    # Disable ssh root login
    disable_root_ssh

    # Fail2ban
    install_fail2ban
    setup_fail2ban
    check_fail2ban_health

    # Secure shared memory
    secure_shared_memory
    
    # Remove insecure services
    remove_insecure_services
}

# --------------------------------------------------
# Main
# --------------------------------------------------
main
# Ask reboot or not