#!/bin/sh

set -e

# --- Configuration ---
GITHUB_REPO="your-username/your-repo" # Change this to your repository
ESP_PATH="/boot"

# --- Helper Functions ---
log() {
    echo "INFO: $1"
}

err() {
    echo "ERROR: $1" >&2
    exit 1
}

# --- Main Script ---
log "Starting installation/update..."

# 1. Find the latest release URL
LATEST_RELEASE_URL=$(curl -s "https://api.github.com/repos/${GITHUB_REPO}/releases/latest" | grep "browser_download_url" | cut -d '"' -f 4)

if [ -z "$LATEST_RELEASE_URL" ]; then
    err "Could not find the latest release. Check the GITHUB_REPO variable."
fi

# 2. Download the assets
log "Downloading latest release assets..."
wget -q -O /tmp/os.efi $(echo "$LATEST_RELEASE_URL" | grep "os.efi")
wget -q -O /tmp/rootfs.tar.gz $(echo "$LATEST_RELEASE_URL" | grep "rootfs.tar.gz")

# 3. Mount the ESP
log "Mounting EFI System Partition at ${ESP_PATH}..."
mount -o remount,rw /
mount /dev/sda1 ${ESP_PATH} || err "Failed to mount ESP at ${ESP_PATH}"

# 4. Install the new files
log "Installing new files..."
mv /tmp/os.efi ${ESP_PATH}/EFI/BOOT/BOOTX64.EFI
mv /tmp/rootfs.tar.gz /rootfs.tar.gz

# 5. Unmount the ESP
log "Unmounting EFI System Partition..."
umount ${ESP_PATH}
mount -o remount,ro /

log "Installation/update complete. Please reboot your system."
