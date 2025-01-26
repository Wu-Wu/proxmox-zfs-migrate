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

# Turn off swap
function swap_turn_off {
    echo "Turn off swap"
    swapoff --all
}

# Turn on swap
function swap_turn_on {
    echo "Turn on swap"
    swapon --all
}

# Wipe all data and partitions
function disk_wipe {
    local DISK=$1
    echo "Wipe disk ${DISK}"
    wipefs -q -a $DISK
    sgdisk --zap-all $DISK
}

# Clone disk partitions from another disk
function disk_clone {
    local DISK_SRC=$1
    local DISK_DST=$2

    echo "Clone partitions to ${DISK_DST}"
    sgdisk -R $DISK_DST $DISK_SRC

    ensure "/dev/disk/by-id/* being populated" 5

    echo "Reset disk GUID"
    sgdisk -G $DISK_DST

    ensure "/dev/disk/by-id/* being populated" 5
}
