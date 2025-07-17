# Custom Alpine Linux OS

This project builds a custom, lightweight Alpine Linux-based operating system that runs in a QEMU virtual machine. It's designed to be ephemeral, with the root filesystem running in ZRAM.

## Project Overview

The main goal of this project is to create a minimal, secure, and easy-to-manage Linux environment. Key features include:

*   **Lightweight:** Based on Alpine Linux, known for its small footprint.
*   **Ephemeral:** The root filesystem runs in ZRAM, meaning all changes are lost on reboot.
*   **Container-Ready:** Includes `podman` for running containers.
*   **Secure Networking:** Includes `tailscale` for secure networking.
*   **Unified Kernel Image (UKI):** The entire OS (kernel, initramfs, cmdline) is a single EFI file.

## Getting Started

### Prerequisites

*   [Podman](https://podman.io/) or a compatible container runtime.

### Building the Container

To build the container, run the following command:

```bash
podman build -t custom-alpine-os .
```

### Running the VM

To run the virtual machine, use the following command:

```bash
podman run -it --rm -v /path/to/your/disk:/disk custom-alpine-os
```

This will start the QEMU VM and you will be dropped into the shell of the running OS.

## How it Works

The build process is defined in the `Containerfile` and consists of multiple stages:

1.  **Builder:** An Alpine Linux environment is set up with the necessary tools to build the OS.
2.  **RootFS:** `alpine-make-rootfs` is used to create a custom root filesystem. This is where packages like `podman` and `tailscale` are added.
3.  **Initramfs:** A custom initramfs is created using `mkinitfs`. The `init.sh` script is the entry point for the initramfs, and it's responsible for setting up the ZRAM root filesystem.
4.  **UKI:** `efi-mkuki` is used to create a Unified Kernel Image (`os.efi`). This single file contains the kernel, initramfs, and kernel command line.
5.  **VM:** The final stage creates a QEMU-based virtual machine to run the `os.efi` image.

## Installation/Update

To install or update the OS on a running system, you can use the `install.sh` script. This script will download the latest release from GitHub and install it.

**Note:** You need to change the `GITHUB_REPO` variable in the `install.sh` script to your repository.

```bash
./install.sh
```

## Customization

You can customize the build by modifying the files in the `rootfs` directory. For example, you can:

*   **Add packages:** Add new packages to the `--packages` list in the `Containerfile`.
*   **Add services:** Add new services to the `setup.sh` script.
*   **Add files:** Add any files to the `rootfs` directory, and they will be included in the final root filesystem.
