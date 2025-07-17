FROM scratch AS ctx
COPY / /


FROM docker.io/library/alpine:edge as builder

ARG TARGETARCH


RUN apk add --no-cache systemd-efistub ukify binutils efi-mkuki ovmf alpine-make-rootfs zstd mkinitfs neovim qemu-img

RUN set -ex; \
    case "$TARGETARCH" in \
        "arm64") \
            echo "Setting up for aarch64"; \
            apk add --no-cache qemu-system-aarch64; \
            ;; \
        "amd64") \
            echo "Setting up for x86_64"; \
            apk add --no-cache qemu-system-x86_64; \
            ;; \
        *) \
            echo "Unknown architecture: $TARGETARCH"; \
            exit 1; \
            ;; \
    esac

RUN mkdir -p /work

RUN --mount=type=bind,from=ctx,source=/,target=/ctx \
    --mount=type=cache,dst=/var/cache \
    --mount=type=cache,dst=/var/log \
    --mount=type=tmpfs,dst=/tmp \
    alpine-make-rootfs -s /ctx/rootfs \
    	--packages 'alpine-conf alpine-base linux-stable linux-firmware-none util-linux btrfs-progs efibootmgr openssh openrc nftables doas zram-init chrony ifupdown-ng rng-tools kexec-tools' \
	--fs-skel-chown root:root \
	--branch edge \
	/work/fs /ctx/setup.sh


RUN cd /work/fs \
        && mv boot/vmlinuz-stable /work/vmlinuz-stable \
	&& rm -rf var boot home usr/share/man usr/share/doc \

ADD https://github.com/christoph00.keys /work/fs/etc/ssh/authorized_keys/core

RUN cd /work/fs && find . -path "./boot" -prune -o -print | cpio -o -H newc  >  /work/initramfs-stable

# RUN efi-mkuki -c "${CMDLINE}" -k "6.15.4" -o /work/os.efi /work/vmlinuz-stable /work/initramfs-stable
	# efi-mkuki -c "rdinit=/sbin/init ro console=ttyS0,115200 kexec_load_disabled=0" -o /work/os.efi /work/vmlinuz-stable /work/initramfs-stable
RUN ukify build --output /work/os.efi --cmdline "rdinit=/sbin/init console=ttyS0,115200 kexec_load_disabled=0" --linux /work/vmlinuz-stable --initrd /work/initramfs-stable --os-release /work/fs/etc/os-release

COPY entrypoint.sh /entrypoint.sh
VOLUME /disk

ENTRYPOINT ["/entrypoint.sh"]

CMD ["vm"]
