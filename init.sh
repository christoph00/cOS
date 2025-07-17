#!/bin/sh
set -e

log() { printf "➜ %s\n" "$*"; }
log_suc() { printf "✓ %s\n" "$*"; }
log_err() { printf "✗ %s\n" "$*" >&2; }

/bin/busybox --install -s /bin
export PATH=/bin:/sbin:/usr/bin:/usr/sbin

log "Mount Filesystems"
mount -t sysfs -o noexec,nosuid,nodev sysfs /sys
mount -t devtmpfs -o exec,nosuid,mode=0755,size=2M devtmpfs /dev 2>/dev/null \
        || mount -t tmpfs -o exec,nosuid,mode=0755,size=2M tmpfs /dev
mount -t proc -o noexec,nosuid,nodev proc /proc
[ -c /dev/ptmx ] || mknod -m 666 /dev/ptmx c 5 2
[ -d /dev/pts ] || mkdir -m 755 /dev/pts
mount -t devpts -o gid=5,mode=0620,noexec,nosuid devpts /dev/pts

: ${ZRAM_SIZE:=600M}
: ${ROOT_FSTYPE:=ext4}
: ${ROOT_DEV:=/dev/disk/by-label/ESP}
: ${ROOT_ARCHIVE:=rootfs.tar.gz}

log "Load Kernel-Modules ..."
for mod in virtio_pci virtio_blk virtio-scsi virtio_ring virtio_rng \
           zram ext4 vfat \
           ata_piix ata_generic libata \
           sd_mod sr_mod uhci_hcd ehci_hcd usb_storage \
           floppy; do
    if modprobe "$mod" 2>/dev/null; then
        log_suc "modprobe $mod"
    else
        log_err "modprobe $mod"
    fi
done

TIMEOUT=30
INTERVAL=1
ELAPSED=0

while [ ! -e /dev/zram0 ]; do
  sleep "$INTERVAL"
  ELAPSED=$((ELAPSED + INTERVAL))
  if [ "$ELAPSED" -ge "$TIMEOUT" ]; then
    log_err "Fehler: /dev/zram0 missing after timeout ${TIMEOUT}s ."
    exec sh
  fi
done
ELAPSED=0

/bin/mdev -s
sleep 0.5

mem_total_kb=$(awk '/MemTotal/ {print $2}' /proc/meminfo)
zram_size_kb=$((mem_total_kb * 8 / 10))
log "Create ZRAM Root"
echo "${zram_size_kb}K" > /sys/block/zram0/disksize
/sbin/mkfs.$ROOT_FSTYPE -L root /dev/zram0
mkdir -p /mnt/zram_root /mnt/alpine_dev
mount /dev/zram0 /mnt/zram_root
log_suc "Root zram format successful"


log "Mount Alpine-dev"
mount "$ROOT_DEV" /mnt/alpine_dev

log "Found rootfs Archive, extract to zram root"
tar xzf "/mnt/alpine_dev/${ROOT_ARCHIVE}" -C /mnt/zram_root
log_suc "rootfs archive extraction successful"

log "Switch Root"

if [[ -x "/mnt/zram_root/sbin/init" ]] ; then
    umount /sys /proc

    /bin/mount --move /dev /mnt/zram_root/dev
    exec 0</mnt/zram_root/dev/console
    exec 1>/mnt/zram_root/dev/console
    exec 2>/mnt/zram_root/dev/console
    exec switch_root -c /dev/console /mnt/zram_root /sbin/init
fi
log_err "Missing /sbin/init in new root"
exec sh
