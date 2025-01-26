#
# Proxmox-ZFS-Migrate library functions
#

# Print error message
function error_message {
    local MESSAGE=$1
    echo ""
    echo "ERROR: ${MESSAGE}"
}

# Print message and wait given seconds
function ensure {
    local MESSAGE=$1
    local WAIT_TIME=$2
    echo "Wait ${MESSAGE} ..."
    sleep $WAIT_TIME
}
