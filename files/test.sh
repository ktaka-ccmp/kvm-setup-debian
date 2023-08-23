#!/bin/bash

#QEMU=/kvm/qemu/qemu-2.6.0/bin/qemu-system-x86_64
QEMU=/kvm/qemu/qemu/bin/qemu-system-x86_64

$QEMU \
-drive file=/kvm/data/test.img,if=virtio \
-virtfs local,id=kvm_boot,path=/kvm/boot,security_model=none,readonly,mount_tag=kvmboot \
-cpu host -m 1024 -smp 2 -rtc base=localtime --enable-kvm \
-kernel /kvm/boot/vmlinuz -initrd /kvm/boot/initrd-kvm.img \
-append "console=ttyS0 ID=test IDNUM=253 HOST=$(hostname) root=/dev/vda" \
--device virtio-net-pci,netdev=dev1,mac=52:54:00:1f:00:7b,id=net1,vectors=6,mq=on \
--netdev tap,id=dev1,vhost=on,script=/kvm/etc/qemu-ifup,queues=2 \
-nographic 

