#!/bin/sh

show_help() {
    echo "Usage: $0 [OPTION]"
    echo ""
    echo "Options:"
    echo "  vm          Start QEMU virtual machine"
    echo "  shell	Enter Shell"
    echo "  help        Show this help message"
    echo ""
    echo "Examples:"
    echo "  $0 vm       # Start the virtual machine"
    echo "  $0 help     # Show help"
}

start_vm() {
    echo "Starting QEMU virtual machine..."
    exec qemu-system-x86_64 \
        -m 1G \
        -nographic \
        -drive if=pflash,format=raw,readonly=yes,file=/usr/share/OVMF/OVMF_CODE.fd \
        -drive if=pflash,format=raw,file=/usr/share/OVMF/OVMF_VARS.fd \
        -kernel /work/os.efi \
        -device virtio-net,netdev=nic \
        -netdev user,hostname=os,id=nic \
	-drive file=/disk/disk1.qcow2,format=qcow2,if=none,id=disk0 \
        -device virtio-blk-pci,drive=disk0
}

start_shell() {
	echo "Enter Shell ..."
	exec sh
}

case "$1" in
    vm)
        start_vm
        ;;
    shell)
        start_shell
	;;
    help|--help|-h)
        show_help
        exit 0
        ;;
    "")
        echo "Error: No option specified"
        show_help
        exit 1
        ;;
    *)
        echo "Error: Unknown option '$1'"
        show_help
        exit 1
        ;;
esac

