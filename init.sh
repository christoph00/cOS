#!/bin/sh
set -e

log() { printf "➜ %s\n" "$*"; }
log_suc() { printf "✓ %s\n" "$*"; }
log_err() { printf "✗ %s\n" "$*" >&2; }

/bin/busybox --install -s /bin
export PATH=/bin:/sbin:/usr/bin:/usr/sbin


log "Mount Filesystems"
mount -t proc proc /proc
mount -t sysfs sysfs /sys
mount -t devtmpfs devtmpfs /dev

: ${ZRAM_SIZE:=600M}
: ${ROOT_FSTYPE:=ext4}
: ${ROOT_DEV:=/dev/vda1}
: ${ROOT_ARCHIVE:=rootfs.tar.gz}

log "Load Kernel-Modules ..."
for mod in virtio_pci virtio_blk virtio-scsi virtio_ring virtio_rng \
           zram ext4 vfat \
           ata_piix ata_generic libata \
           sd_mod sr_mod uhci_hcd ehci_hcd usb_storage \
           floppy; do
    if modprobe "$mod" 2>/dev/null; then
        log_suc "modprobe $mod geladen."
    else
        log_err "modprobe $mod nicht nötig/fehlerhaft."
    fi
done

mem_total_kb=$(awk '/MemTotal/ {print $2}' /proc/meminfo)
zram_size_kb=$((mem_total_kb * 8 / 10))
log "Create ZRAM Root"
echo "${zram_size_kb}K" > /sys/block/zram0/disksize
/sbin/mkfs.$ROOT_FSTYPE /dev/zram0
mkdir -p /mnt/zram_root /mnt/alpine_dev
mount /dev/zram0 /mnt/zram_root
mount "$ROOT_DEV" /mnt/alpine_dev
log_suc "Root zram format successful"

if [ -f "$ROOT_ARCHIVE" ]; then
  log "Found rootfs Archive, extract to zram root"
  tar xzf "/mnt/alpine_dev/${ROOT_ARCHIVE}" -C /mnt/zram_root
  log_suc "rootfs archive extraction successful"
else
  log_err "no rootfs found"
  exec sh
fi


log "Switch Root"
exec switch_root /mnt/zram_root /sbin/init
log_err "Switch Root Failed"
exec sh
