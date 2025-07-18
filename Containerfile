#######################################################################
# ---------- STAGE 1: Builder (Alpine base, Kernel, mkinitfs) ---------
#######################################################################
FROM alpine:3.22 AS builder

RUN apk add --no-cache \
      alpine-sdk \
      linux-lts linux-firmware-none \
      mkinitfs \
      efi-mkuki \
      alpine-make-rootfs \
      systemd-efistub \
      e2fsprogs \
      squashfs-tools

WORKDIR /build

COPY rootfs /build/rootfs-overlay
COPY setup.sh /build/setup.sh

#######################################################################
# ---------- STAGE 2: RootFS ------------------------------------------
#######################################################################
RUN alpine-make-rootfs \
      --branch v3.22 \
      --packages "alpine-base linux-lts linux-firmware-none openrc podman monit dropbear tailscale" \
      -s rootfs-overlay \
      rootfs /build/setup.sh
RUN rm -rf rootfs/boot && rm -rf rootfs/var
RUN tar -C rootfs -czf rootfs.tar.gz .

#######################################################################
# ---------- STAGE 3: initramfs ---------------------------------------
#######################################################################


COPY init.sh /build/init
RUN chmod +x /build/init \
    && echo 'kernel/drivers/block/zram' > /etc/mkinitfs/features.d/zram.modules \
    && echo '/sbin/fsck.vfat' > /etc/mkinitfs/features.d/vfat.files \
    && echo 'kernel/fs/vfat' > /etc/mkinitfs/features.d/vfat.modules \
    && echo '/sbin/mkfs.ext4' > /etc/mkinitfs/features.d/ext4.files 

RUN mkinitfs -F "base ata usb zram ext4 vfat virtio" -i /build/init -o /build/initfs $(ls /lib/modules)

#######################################################################
# ---------- STAGE 4: UKI ---------------------------------------------
#######################################################################
RUN efi-mkuki \
      -k $(ls /lib/modules) \
      -c 'console=tty0 console=ttyS0,115200 kexec_load_disabled=0'  \
      -o  /build/os.efi \
      -r /etc/os-release \
      -S /usr/lib/systemd/boot/efi/linuxx64.efi.stub \
      /boot/vmlinuz-lts \
      /build/initfs

FROM busybox 
COPY --from=builder /build/rootfs.tar.gz /
COPY --from=builder /build/os.efi /

CMD ["/bin/true"]

#######################################################################
# ---------- STAGE 5: Test ------------------------------------------
#######################################################################
# FROM docker.io/library/alpine:3.22 as vm
# RUN apk add --no-cache ovmf neovim qemu-img qemu-system-x86_64 e2fsprogs
# COPY --from=builder /build/os.efi /work/
# COPY --from=builder /build/rootfs.tar.gz /work/
# COPY entrypoint.sh /entrypoint.sh
#
# RUN mkfs.ext4 -L ESP -d /work /osdisk.raw 2G \
#     && qemu-img convert -f raw -O qcow2 -o cluster_size=2M,lazy_refcounts=on /osdisk.raw /osdisk.qcow2 && rm /osdisk.raw
#
# VOLUME /disk
#
# ENTRYPOINT ["/entrypoint.sh"]
#
# CMD ["vm"]
