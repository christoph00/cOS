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
rc_add hostname boot
rc_add bootmisc boot
rc_add syslog boot
rc_add cgroups boot

rc_add mount-ro shutdown
rc_add killprocs shutdown
rc_add savecache shutdown

rc_add local default
rc_add sshd default
rc_add podman default
rc_add networking default
rc_add tailscale default
rc_add monit default


einfo "Set Root Password"
sed -i 's|root.*|root:$1$n3vjdweX$vyZqcZyUC5Q2uq4bxnfbQ0:18242:0:99999:7:::|g' "$ROOTFS"/etc/shadow


USERNAME="core"
GROUPNAME="wheel"
UID=1000
GID=10
HOME_DIR="/home/${USERNAME}"
SHELL="/bin/ash"


create_user_manual() {
    if ! grep -q "^${GROUPNAME}:" /etc/group; then
        echo "${GROUPNAME}:x:${GID}:" >> /etc/group
        einfo "Gruppe ${GROUPNAME} erstellt"
    fi
    
    echo "${USERNAME}:x:${UID}:${GID}:${USERNAME}:${HOME_DIR}:${SHELL}" >> /etc/passwd
    einfo "User ${USERNAME} in /etc/passwd erstellt"
    
    echo "${USERNAME}:!:19000:0:99999:7:::" >> /etc/shadow
    einfo "User ${USERNAME} in /etc/shadow erstellt"
    
    sed -i "s/^${GROUPNAME}:x:${GID}:$/&${USERNAME}/" /etc/group
    einfo "User ${USERNAME} zur Gruppe ${GROUPNAME} hinzugefügt"
    
    einfo "User ${USERNAME} wurde erfolgreich erstellt!"
}

create_user_manual
