#!/bin/bash

#QEMU=/kvm/qemu/qemu-2.6.0/bin/qemu-system-x86_64
QEMU=/kvm/qemu/qemu/bin/qemu-system-x86_64

$QEMU \
-drive file=/kvm/data/test.img,if=virtio \
-virtfs local,id=kvm_boot,path=/kvm/boot,security_model=none,readonly,mount_tag=kvmboot \
-cpu host -m 1024 -smp 2 -rtc base=localtime --enable-kvm \
-kernel /kvm/boot/vmlinuz -initrd /kvm/boot/initrd-kvm.img \
-append "console=ttyS0 ID=test IDNUM=253 HOST=kvm3 root=/dev/vda" \
-net nic,vlan=0,macaddr=52:54:00:1f:00:7b,model=virtio \
-net tap,vlan=0,script=/kvm/etc/qemu-ifup,ifname=test \
-nographic 

