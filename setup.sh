#!/bin/sh -e

die() {
	printf '\033[1;31mERROR:\033[0m %s\n' "$@" >&2  # bold red
	exit 1
}

einfo() {
	printf '\n\033[1;36m> %s\033[0m\n' "$@" >&2  # bold cyan
}

rc_add() {
	einfo "Add Service $1 to $2"
	mkdir -p "$ROOTFS"/etc/runlevels/"$2"
	ln -sf /etc/init.d/"$1" "$ROOTFS"/etc/runlevels/"$2"/"$1"
}


rc_add devfs sysinit
rc_add dmesg sysinit
rc_add mdev sysinit

rc_add hwclock boot
rc_add modules boot
rc_add sysctl boot
rc_add bootmisc boot
rc_add syslog boot
rc_add cgroups boot
rc_add inittab boot

rc_add mount-ro shutdown
rc_add killprocs shutdown
rc_add savecache shutdown

rc_add local default
rc_add networking default
rc_add core-setup default
rc_add tailscale default
rc_add podman default
rc_add monit default
rc_add sshd default

# einfo "Set Root Password"
# sed -i 's|root.*|root:$1$n3vjdweX$vyZqcZyUC5Q2uq4bxnfbQ0:18242:0:99999:7:::|g' "$ROOTFS"/etc/shadow
