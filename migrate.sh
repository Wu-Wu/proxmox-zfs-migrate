#!/bin/bash

#
# migrate.sh - Proxmox ZFS migrate: main script
# Copyright (C) 2025 Anton Gerasimov
# https://github.com/Wu-Wu/proxmox-zfs-migrate
# License: MIT
#

VERSION="0.1.1"

PWD=`pwd`
LIB_FILE="${PWD}/lib.sh"
VARS_FILE="${PWD}/vars"
STAGE_FILE="${PWD}/.migrate-stage"
THIS_FILE="${PWD}/$(basename $0)"

if [[ ! -f $VARS_FILE ]]; then
    echo ""
    echo "ERROR: ${VARS_FILE} not found!"
    exit
fi

source $VARS_FILE

if [[ ! -f $LIB_FILE ]]; then
    echo ""
    echo "ERROR: ${LIB_FILE} not found!"
    exit
fi

source $LIB_FILE

if [[ -f $STAGE_FILE ]]; then
    source $STAGE_FILE
fi

# Stage OK message
function continue_stage {
    echo "Look good! Continue.."
}

# Set up next stage
function bump_next_stage {
    local NEXT_STAGE=$1

    echo "MIGRATE_STAGE=${NEXT_STAGE}" > $STAGE_FILE

    echo "Reboot system and re-run ${THIS_FILE} to continue migration."
}

# Mirgate finished
function bump_finished {
    # clean-up stage-file
    rm -f $STAGE_FILE

    echo ""
    echo "***"
    echo "*** MIGRATION FINISHED!"
    echo "***"
    echo "*** CAUTION! CAUTION! CAUTION! CAUTION!"
    echo "***"
    echo "*** YOU STRICTLY SHOULD WAIT TO COMPLETE"
    echo "*** RESILVERING PROCESS ON ZFS POOLS!"
    echo "*** Affected ZFS pools:"
    echo "***    - ${BPOOL}"
    echo "***    - ${RPOOL}"
    echo "*** Feel free to use next command to check:"
    echo "***    zpool status"
    echo "***"
    echo "*** Extra system reboot required in order"
    echo "*** to use some features (e.g. swap, ...)"
    echo "***"
}

# Base stage prerequisites
function stage_base_prereqs {
    # ZFS pools does not exist
    is_zfs_pool_not_exists $BPOOL
    is_zfs_pool_not_exists $RPOOL

    continue_stage
}

# Almost any stage prerequisites
function generic_stage_prereqs {
    # ZFS pools exist
    is_zfs_pool_exists $BPOOL
    is_zfs_pool_exists $RPOOL
    # check if root booted from ZFS
    is_zfs_on_root $ROOT_FS

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
    zfs_set_rootfs $RPOOL $ROOT_FS
    zfs_set_mountpoints MOUNTPOINTS
}

# Storage stage actions
function stage_storage_actions {
    tune_lvm_attrs
    tune_proxmox_storage $DATA_FS

    # old disk goes to layout
    bump_next_stage "layout-old"
}

# Layout old disk actions
function stage_layout_old_actions {
    # using disks
    DISK1=${DISK_OLD}
    DISK2=${DISK_NEW}

    # clone partitions from new to old
    disk_wipe $DISK1
    disk_clone $DISK2 $DISK1

    # bump EFI on new disk
    tune_init_efi ${DISK2}-part2

    # fix /etc/fstab mounts
    tune_switch_efi

    # old disk goes to mirror
    bump_next_stage "mirror"
}

# Mirror stage actions
function stage_mirror_actions {
    # using disks
    DISK1=${DISK_OLD}
    DISK2=${DISK_NEW}

    # format EFI on old disk
    tune_format_efi ${DISK1}-part2
    # bump EFI on old disk
    tune_init_efi ${DISK1}-part2

    # attach old disk to boot pool
    zfs_attach_vdev $BPOOL ${DISK2}-part3 ${DISK1}-part3

    # attach old disk to root pool
    zfs_attach_vdev $RPOOL ${DISK2}-part4 ${DISK1}-part4

    # turn on swap
    swap_turn_on

    bump_finished
}

# current stage
MIGRATE_STAGE=${MIGRATE_STAGE:="base"}

echo "Proxmox-ZFS-Migrate v${VERSION}"

if [[ "$MIGRATE_STAGE" != "base" ]]; then
    echo "Continue migration @ stage ${MIGRATE_STAGE}"
else
    echo "Begin migration to ZFS"
fi

case $MIGRATE_STAGE in
    mirror)
        generic_stage_prereqs
        stage_mirror_actions
        ;;
    layout-old)
        generic_stage_prereqs
        stage_layout_old_actions
        ;;
    storage)
        generic_stage_prereqs
        stage_storage_actions
        ;;
    *)
        stage_base_prereqs
        stage_base_actions
        ;;
esac
