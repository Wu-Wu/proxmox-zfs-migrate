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

# Check if ZFS pool exists
function is_zfs_pool_exists {
    local POOL_NAME=$1

    found=`zpool list -H $POOL_NAME 2>/dev/null`
    if [[ $? -eq 0 ]]; then
        error_message "${POOL_NAME} found!"
        exit
    fi
}

# Check if ZFS pool does not exists
function is_zfs_pool_not_exists {
    local POOL_NAME=$1

    found=`zpool list -H $POOL_NAME 2>/dev/null`
    if [[ $? -eq 1 ]]; then
        error_message "${POOL_NAME} not found!"
        exit
    fi
}
