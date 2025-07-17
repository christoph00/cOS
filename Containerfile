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
      squashfs-tools

WORKDIR /build

#######################################################################
# ---------- STAGE 2: RootFS ------------------------------------------
#######################################################################
RUN alpine-make-rootfs \
      --branch v3.22 \
      --packages "alpine-base" \
      rootfs

RUN tar -C rootfs -czf rootfs.tar.gz .

#######################################################################
# ---------- STAGE 3: initramfs ---------------------------------------
#######################################################################


COPY init.sh /build/init
RUN chmod +x /build/init && \
    echo 'kernel/drivers/block/zram' > /etc/mkinitfs/features.d/zram.modules \
    echo '/sbin/fsck.vfat' > /etc/mkinitfs/features.d/vfat.files \
    echo 'kernel/fs/vfat' > /etc/mkinitfs/features.d/vfat.modules 

RUN mkinitfs -F "base ata usb zram ext4 vfat virtio" -i /build/init -o /build/initfs $(ls /lib/modules)

#######################################################################
# ---------- STAGE 4: UKI ---------------------------------------------
#######################################################################
RUN efi-mkuki \
      -k $(ls /lib/modules) \
      -c 'quiet console=ttyS0,115200 kexec_load_disabled=0'  \
      -o  /build/os.efi \
      /boot/vmlinuz-lts \
      /build/initfs

#######################################################################
# ---------- STAGE 5: Export ------------------------------------------
#######################################################################
FROM scratch AS output
COPY --from=builder /build/ /

CMD ["/bin/true"]

