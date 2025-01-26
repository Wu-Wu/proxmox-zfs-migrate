#!/bin/bash

PWD=`pwd`
VARS_FILE="${PWD}/vars"
STAGE_FILE="${PWD}/.migrate-stage"
THIS_FILE="${PWD}/$(basename $0)"

if [[ ! -f $VARS_FILE ]]; then
    echo ""
    echo "ERROR: ${VARS_FILE} not found!"
    exit
fi

source $VARS_FILE

if [[ -f $STAGE_FILE ]]; then
    source $STAGE_FILE
fi

# current stage
MIGRATE_STAGE=${MIGRATE_STAGE:="base"}

case $MIGRATE_STAGE in
    storage)
        echo "Continue migration @${MIGRATE_STAGE}"
        ;;
    *)
        echo "Begin migration to ZFS"
        stage_base_prereqs
        ;;
esac

# Base stage prerequisites
function stage_base_prereqs {
    # ZFS pools does not exist
    is_zfs_pool_not_exists $BPOOL
    is_zfs_pool_not_exists $RPOOL

    continue_stage
}

# Base stage actions
function stage_base_actions {
    # using disks
    DISK1=${DISK_NEW}
    DISK2=${DISK_OLD}

    # Turn off swap
    swap_turn_off

    # Create partitions on disk
    disk_wipe $DISK1
    disk_create_partitions $DISK1 PARTITION_TABLE

    # create ZFS pools
    zfs_create_bpool $BPOOL ${DISK1}-part3
    zfs_create_rpool $RPOOL ${DISK1}-part4

    # create ZFS datasets
    # TODO: very messy!
    zfs_create_datasets \
        $ROOT_DS \
        $BOOT_DS \
        $ROOT_FS \
        $BOOT_FS \
        $TMP_FS \
        $DATA_FS

    zfs_create_swap $SWAP_SIZE $SWAP_VOL

    tune_grub_defaults $ROOT_FS

    # XXX: just before sync (in this stage)
    bump_next_stage "storage"

    # sync boot and root
    sync_filesystems

    # install grub
    tune_grub_install ${DISK1}-part2 ${DISK2}-part2

    # ensure pool imported
    tune_pools_imports $BPOOL

    # fix /etc/fstab
    tune_fstab $FSTAB_OLD_ROOT $FSTAB_OLD_SWAP $SWAP_VOL

    # TODO: bulk umount
    cd /root
    umount /mnt/data
    umount /mnt/tmp
    umount /mnt/boot
    umount /mnt

    # set up mountpoints
    zfs_set_rootfs $ROOT_FS $RPOOL
    zfs_set_mountpoints MOUNTPOINTS
}

# Set up next stage
function bump_next_stage {
    local NEXT_STAGE=$1

    echo "MIGRATE_STAGE=${NEXT_STAGE}" > $STAGE_FILE

    echo "Reboot system and re-run ${THIS_FILE} to continue migration."
}

# Stage OK message
function continue_stage {
    echo "Look good! Continue.."
}
