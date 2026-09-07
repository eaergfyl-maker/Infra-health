#!/bin/bash
# =============================================================
#  SABOTAGE 1 of 3  --  fill up a disk (safely)
#
#  This does NOT touch your real disk. It creates a tiny 64 MB
#  RAM-based filesystem mounted at /mnt/health-demo-disk, then
#  fills it up. Person B's disk check looks at that mount point
#  as well as "/", so the score drops.
#
#  Usage:
#    sudo ./fill_disk.sh on     <- break it  (disk goes ~97% full)
#    sudo ./fill_disk.sh off    <- fix it    (unmounts, all gone)
#    sudo ./fill_disk.sh status <- show current usage
# =============================================================

DEMO_DISK="/mnt/health-demo-disk"
SIZE_MB=64          # total size of the fake disk
FILL_MB=60          # how much of it we fill up

ACTION="$1"

case "$ACTION" in

  on)
    echo "Creating a $SIZE_MB MB demo disk at $DEMO_DISK ..."
    mkdir -p "$DEMO_DISK"

    # Mount a tmpfs (a filesystem that lives in RAM). Nothing is
    # written to the real hard drive, so this is completely safe.
    if ! mountpoint -q "$DEMO_DISK"; then
      mount -t tmpfs -o size=${SIZE_MB}M tmpfs "$DEMO_DISK"
    fi

    echo "Filling it with ${FILL_MB} MB of zeros ..."
    # dd copies data. /dev/zero is an endless stream of empty bytes.
    dd if=/dev/zero of="$DEMO_DISK/bigfile.dat" bs=1M count=$FILL_MB status=none

    echo ""
    df -h "$DEMO_DISK"
    echo ""
    echo "Done. Re-run the health checks to see the score drop."
    ;;

  off)
    echo "Cleaning up the demo disk ..."
    rm -f "$DEMO_DISK/bigfile.dat"

    if mountpoint -q "$DEMO_DISK"; then
      umount "$DEMO_DISK"
    fi
    rmdir "$DEMO_DISK" 2>/dev/null

    echo "Done. The demo disk is gone. Re-run the checks to recover."
    ;;

  status)
    if mountpoint -q "$DEMO_DISK"; then
      df -h "$DEMO_DISK"
    else
      echo "No demo disk is mounted. Real disk usage:"
      df -h /
    fi
    ;;

  *)
    echo "Usage: sudo $0 on|off|status"
    exit 1
    ;;
esac
