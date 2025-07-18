#!/bin/sh
set -e

log() { printf "➜ %s\n" "$*"; }
log_suc() { printf "✓ %s\n" "$*"; }
log_err() { printf "✗ %s\n" "$*" >&2; }

# Recursively resolve tty aliases like console or tty0
list_console_devices() {
	if ! [ -e /sys/class/tty/$1/active ]; then
		echo $1
		return
	fi

	for dev in $(cat /sys/class/tty/$1/active); do
		list_console_devices $dev
	done
}

detect_serial_consoles() {
	local n=$(awk '$7 ~ /CTS/ || $7 ~ /DSR/ { print $1 }' /proc/tty/driver/serial 2>/dev/null)
	if [ -n "$n" ]; then
		echo ttyS${n%:}
	fi
	for i in /sys/class/tty/*; do
		if [ -e "$i"/device ]; then
			echo ${i##*/}
		fi
	done
}

setup_inittab_console() {
	term=vt100
	# Inquire the kernel for list of console= devices
	consoles="$(for c in console $KOPT_consoles $(detect_serial_consoles); do list_console_devices $c; done)"
	for tty in $consoles; do
		# ignore tty devices that gives I/O error
		if ! stty -g -F /dev/$tty >/dev/null 2>/dev/null; then
			continue
		fi
		# do nothing if inittab already have the tty set up
		if ! grep -q "^$tty:" $sysroot/etc/inittab 2>/dev/null; then
			echo "# enable login on alternative console" \
				>> $sysroot/etc/inittab
			# Baudrate of 0 keeps settings from kernel
			echo "$tty::respawn:/sbin/getty -L 0 $tty $term" \
				>> $sysroot/etc/inittab
		fi
		if [ -e "$sysroot"/etc/securetty ] && ! grep -q -w "$tty" "$sysroot"/etc/securetty; then
			echo "$tty" >> "$sysroot"/etc/securetty
		fi
	done
}


setconsole_serial() {
	for tty in $(detect_serial_consoles); do
		# ignore tty devices that gives I/O error
		if ! stty -g -F /dev/$tty >/dev/null 2>/dev/null; then
			continue
		fi
		if [ $# -eq 0 ] && setconsole /dev/$tty; then
			return
		fi
		for pattern in "$@"; do
			if grep -E -q "$pattern" "/sys/class/dmi/id/modalias" 2>/dev/null; then
				setconsole /dev/$tty && return
			fi
		done
	done
}


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


# read the kernel options. we need surve things like:
#  acpi_osi="!Windows 2006" xen-pciback.hide=(01:00.0)
set -- $(cat /proc/cmdline)

myopts="BOOTIF
	autodetect_serial
	blacklist
	init
	init_args
	modules
	quiet
	splash
"

for opt; do
	case "$opt" in
	s|single|1)
		SINGLEMODE=yes
		continue
		;;
	console=*)
		opt="${opt#*=}"
		KOPT_consoles="${opt%%,*} $KOPT_consoles"
		switch_root_opts="-c /dev/${opt%%,*}"
		continue
		;;
	esac

	for i in $myopts; do
		case "$opt" in
		$i=*)	eval "KOPT_${i}"='${opt#*=}';;
		$i)	eval "KOPT_${i}=yes";;
		no$i)	eval "KOPT_${i}=no";;
		esac
	done
done

case "$KOPT_autodetect_serial" in
	setconsole) setconsole_serial;;
	setconsole=*) setconsole_serial $(echo "${KOPT_autodetect_serial#setconsole=}" | tr ',' ' ');;
esac


: ${KOPT_init:=/sbin/init}

: ${ZRAM_SIZE:=600M}
: ${ROOT_FSTYPE:=ext4}
: ${ROOT_DEV:=/dev/disk/by-label/ESP}
: ${ROOT_ARCHIVE:=rootfs.tar.gz}

log "Load Kernel-Modules ..."
for mod in virtio_pci virtio_blk virtio-scsi virtio_ring virtio_rng virtio_console \
           zram ext4 vfat \
	   simpledrm \
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

setup_inittab_console

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
