#!/bin/sh
set -e

LOGFILE="/initrd.log"
# Redirect all stdout and stderr to both console and log file
exec > >(tee -a "$LOGFILE") 2>&1

log()    { printf "➜ %s\n" "$*"; }
log_suc(){ printf "✓ %s\n" "$*"; }
log_err(){ printf "✗ %s\n" "$*" >&2; }

# Ensure busybox commands are available in PATH
/bin/busybox --install -s /bin
export PATH=/bin:/sbin:/usr/bin:/usr/sbin

# Retry function with exponential backoff for critical commands
retry() {
    local cmd="$*"
    local attempt=1 max=5 delay=1

    while [ $attempt -le $max ]; do
        if sh -c "$cmd"; then
            return 0
        else
            log_err "Command failed (attempt $attempt): $cmd"
            if [ $attempt -lt $max ]; then
                sleep $delay
                delay=$((delay * 2))
                attempt=$((attempt + 1))
            else
                return 1
            fi
        fi
    done
}

log "Starting initrd script"

# Mount filesystems with retry
log "Mounting filesystems"
try_mount() {
    local type=$1 opts=$2 src=$3 dst=$4
    retry "mount -t $type -o $opts $src $dst"
}

# Mount /sys
try_mount sysfs "noexec,nosuid,nodev" sysfs /sys || log_err "Failed to mount sysfs"

# Mount /dev with fallback from devtmpfs to tmpfs
if ! try_mount devtmpfs "exec,nosuid,mode=0755,size=2M" devtmpfs /dev; then
    try_mount tmpfs "exec,nosuid,mode=0755,size=2M" tmpfs /dev || log_err "Failed to mount devtmpfs/tmpfs"
fi

# Mount /proc
try_mount proc "noexec,nosuid,nodev" proc /proc || log_err "Failed to mount proc"

# Create /dev/pts if missing and mount devpts
[ -d /dev/pts ] || mkdir -m 755 /dev/pts
try_mount devpts "gid=5,mode=0620,noexec,nosuid" devpts /dev/pts || log_err "Failed to mount devpts"

# Load kernel modules (non-fatal errors logged)
log "Loading kernel modules"
MODULES="virtio_pci virtio_blk virtio-scsi virtio_ring virtio_rng virtio_console zram ext4 vfat ata_piix ata_generic libata sd_mod sr_mod uhci_hcd ehci_hcd usb_storage floppy"

for mod in $MODULES; do
    if modprobe "$mod"; then
        log_suc "modprobe $mod succeeded"
    else
        log_err "modprobe $mod failed (warning only)"
    fi
done

# Wait for the zram device node with timeout
log "Waiting for /dev/zram0 (timeout 30s)"
WAIT_TIMEOUT=30
WAIT_INTERVAL=1
elapsed=0
while [ ! -b /dev/zram0 ]; do
    sleep $WAIT_INTERVAL
    elapsed=$((elapsed + WAIT_INTERVAL))
    if [ $elapsed -ge $WAIT_TIMEOUT ]; then
        log_err "Timeout waiting for /dev/zram0 after $WAIT_TIMEOUT seconds"
        exec sh
    fi
done
log_suc "/dev/zram0 is present"

# Trigger mdev to create device nodes
/bin/mdev -s
sleep 0.5

# Determine ZRAM size (80% of total memory)
mem_kb=$(awk '/MemTotal/ {print $2}' /proc/meminfo)
zram_kb=$(( mem_kb * 8 / 10 ))
log "Setting zram size to ${zram_kb}K"
echo "${zram_kb}K" > /sys/block/zram0/disksize

# Format and mount zram device
ROOT_FSTYPE="${ROOT_FSTYPE:-ext4}"
if ! /sbin/mkfs.$ROOT_FSTYPE -L root /dev/zram0; then
    log_err "mkfs failed on /dev/zram0"
    exec sh
fi

mkdir -p /mnt/zram_root /mnt/alpine_dev
if ! mount /dev/zram0 /mnt/zram_root; then
    log_err "Mounting /dev/zram0 on /mnt/zram_root failed"
    exec sh
fi
log_suc "ZRAM root formatted and mounted"

# Mount root device containing the rootfs archive
ROOT_DEV="${ROOT_DEV:-/dev/disk/by-label/ESP}"
log "Mounting root device $ROOT_DEV"
if ! mount "$ROOT_DEV" /mnt/alpine_dev; then
    log_err "Mounting root device $ROOT_DEV failed"
    exec sh
fi

# Check rootfs archive presence
ROOT_ARCHIVE="${ROOT_ARCHIVE:-rootfs.tar.gz}"
if [ ! -f "/mnt/alpine_dev/$ROOT_ARCHIVE" ]; then
    log_err "Rootfs archive '$ROOT_ARCHIVE' not found on $ROOT_DEV"
    exec sh
fi

# Extract rootfs archive into zram root
log "Extracting rootfs archive $ROOT_ARCHIVE into /mnt/zram_root"
if ! tar xzf "/mnt/alpine_dev/$ROOT_ARCHIVE" -C /mnt/zram_root; then
    log_err "Extracting rootfs archive failed"
    exec sh
fi
log_suc "Rootfs archive extracted successfully"

# Prepare for switch_root
log "Switching to new root"
if [ ! -x "/mnt/zram_root/sbin/init" ]; then
    log_err "/sbin/init missing in new root"
    exec sh
fi

# Unmount old filesystems
umount /sys /proc

# Move /dev and redirect stdio to new console
mount --move /dev /mnt/zram_root/dev
exec 0</mnt/zram_root/dev/console
exec 1>/mnt/zram_root/dev/console
exec 2>/mnt/zram_root/dev/console

# Switch root and start init
exec switch_root -c /dev/console /mnt/zram_root /sbin/init

# Fallback shell in case switch_root fails
log_err "switch_root failed, starting emergency shell"
exec sh

