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

# Create required partitions on disk
function disk_create_partitions {
    local DISK=$1
    local -n TABLE=$2
    echo "Create partitions on ${DISK}"
    # sgdisk -L
    # BIOS boot: EF02
    # EFI System: EF00
    # Solaris boot: BE00
    # Solaris root: BF00
    sgdisk -a1 -n1:24K:${TABLE[bios]} -t1:EF02 $DISK
    sgdisk     -n2:0:${TABLE[efi]}    -t2:EF00 $DISK
    sgdisk     -n3:0:${TABLE[boot]}   -t3:BE00 $DISK
    sgdisk     -n4:0:${TABLE[root]}   -t4:BF00 $DISK

    ensure "/dev/disk/by-id/* being populated" 5
}

# Create ZFS boot pool
function zfs_create_bpool {
    local POOL_NAME=$1
    local POOL_VDEV=$2

    echo "Create ZFS pool: ${POOL_NAME}"

    zpool create \
        -o ashift=12 \
        -o autotrim=on \
        -o compatibility=grub2 \
        -o cachefile=/etc/zfs/zpool.cache \
        -O devices=off \
        -O acltype=posixacl \
        -O xattr=sa \
        -O compression=lz4 \
        -O relatime=on \
        -O canmount=off \
        -O mountpoint=/boot \
        -R /mnt \
        $POOL_NAME $POOL_VDEV

    ensure "${POOL_NAME} being created" 2
}

# Create ZFS root pool
function zfs_create_rpool {
    local POOL_NAME=$1
    local POOL_VDEV=$2

    echo "Create ZFS pool: ${POOL_NAME}"
    zpool create \
        -o ashift=12 \
        -o autotrim=on \
        -o cachefile=/etc/zfs/zpool.cache \
        -O acltype=posixacl \
        -O xattr=sa \
        -O dnodesize=auto \
        -O compression=lz4 \
        -O relatime=on \
        -O canmount=off \
        -O mountpoint=/ \
        -R /mnt \
        $POOL_NAME $POOL_VDEV

    ensure "${POOL_NAME} being created" 2
}

# Create ZFS volume for swap
function zfs_create_swap {
    local SIZE=$1
    local NAME=$2

    echo "Create swap volume"
    zfs create -V $SIZE \
        -o compression=zle \
        -o logbias=throughput \
        -o sync=always \
        -o primarycache=metadata \
        -o secondarycache=none \
        -o com.sun:auto-snapshot=false \
        $NAME

    ensure "${NAME} being created" 2

    mkswap -q -f /dev/zvol/${NAME}

    ensure "${NAME} being set up" 2
}

# Set root defaults for grub
function tune_grub_defaults {
    local ROOT_FS=$1

    echo "Set up GRUB defaults"

    local key="GRUB_CMDLINE_LINUX"
    local val="root=ZFS=${ROOT_FS} boot=zfs"

    sed -i.bak \
        "/^$key\=/ { s/^#//; s%=.*%=\"$val\"%; }" \
        /etc/default/grub
}

# Sync root filesystem
function sync_root_fs {
    cd /mnt
    rsync -ax --include '/*' --exclude 'boot/*' / ./
}

# Sync boot filesystem
function sync_boot_fs {
    cd /mnt/boot
    rsync -ax --include '/*' --exclude 'efi/*' /boot/ ./
}

# Syncs boot and root filesystems
function sync_filesystems {
    echo "Syncing boot and root filesystems"
    sync_boot_fs
    sync_root_fs
}
