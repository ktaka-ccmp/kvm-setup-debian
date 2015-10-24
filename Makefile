
TOP_DIR=/kvm
SRC_DIR=${TOP_DIR}/SRC/

KERNEL_URI=http://www.kernel.org/pub/linux/kernel/v4.x/linux-4.2.4.tar.xz
KERNEL_FILE=$(notdir ${KERNEL_URI})
KERNEL=$(KERNEL_FILE:.tar.xz=)
KVER_MINOR=-64kvmg01

BUSYBOX_URI=http://busybox.net/downloads/busybox-1.23.2.tar.bz2
BUSYBOX_FILE=$(notdir ${BUSYBOX_URI})
BUSYBOX=$(BUSYBOX_FILE:.tar.bz2=)

QEMU_URI=http://wiki.qemu-project.org/download/qemu-2.4.0.1.tar.bz2
QEMU_FILE=$(notdir ${QEMU_URI})
QEMU=$(QEMU_FILE:.tar.bz2=)

TEMPLATE=template.jessie64

default: 
	@echo "Usage: make target "
	@echo " Available Targets "
	@echo "\t all		: Make all files"
	@echo "\t "
	@echo "\t kernel		: Compile kernel"
	@echo "\t initrd		: Create initrd image"
	@echo "\t qemu		: compile qemu"
	@echo "\t files		: copy kvm files"
	@echo "\t template	: create template image"
	@echo "\t template-modify : copy authorized_keys to template image"
	@echo "\t hosts	: add hosts entry"
	@echo

.PHONY: default

all: 
	make prep
	make initrd
	make kernel
	make qemu
	make files
	make template
	make template-modify
	make hosts

.PHONY: all kernel  

prep:
	mkdir -p ${TOP_DIR}/SRC
	mkdir -p ${TOP_DIR}/boot	
	mkdir -p ${TOP_DIR}/sbin
	mkdir -p ${TOP_DIR}/data
	mkdir -p ${TOP_DIR}/console
	mkdir -p ${TOP_DIR}/monitor
	mkdir -p ${TOP_DIR}/etc
	aptitude install -y debootstrap \
	ca-certificates \
	libncurses5-dev \
	xz-utils \
	bc \
	gcc \
	git \
	bzip2 \
	g++ \
	libtool \
	pkg-config \
	zlib1g-dev \
	libglib2.0-dev \
	autoconf \
	build-essential \
	socat \
	bridge-utils \
	lsof \
	time \
	

.PHONY: initrd
initrd: initrd_dir
	(cd ${SRC_DIR}/initrd_dir ;find . | cpio -o -H newc | gzip -9 -n > ${TOP_DIR}/boot/initrd-kvm.img)

.PHONY: initrd_dir
initrd_dir: ${SRC_DIR}/${BUSYBOX}/_install 
	mkdir -p ${SRC_DIR}/initrd_dir
	rsync -a --delete ${SRC_DIR}/${BUSYBOX}/_install/ ${SRC_DIR}/initrd_dir/
	mkdir -p ${SRC_DIR}/initrd_dir/sysroot
	mkdir -p ${SRC_DIR}/initrd_dir/proc
	cp files/init ${SRC_DIR}/initrd_dir/

kernel: ${SRC_DIR}/${KERNEL}/.config installkernel
	ARCH=x86_64 nice -n 10 make -C ${SRC_DIR}/${KERNEL} -j20
	ARCH=x86_64 make -C ${SRC_DIR}/${KERNEL} install INSTALL_PATH=${TOP_DIR}/boot/
	(cd ${TOP_DIR}/boot/ ; ln -sf $(subst linux,vmlinuz,${KERNEL})${KVER_MINOR} vmlinuz )
	(cp ${SRC_DIR}/${KERNEL}/.config files/dot.config ; touch ${SRC_DIR}/${KERNEL}/.config)

${SRC_DIR}/${KERNEL}/.config: files/dot.config
	if [ ! -d ${SRC_DIR}/${KERNEL} ]; then \
	(wget -c ${KERNEL_URI} ;\
	tar xf ${KERNEL_FILE} -C ${SRC_DIR}; rm ${KERNEL_FILE}) ; fi
	sed -e 's/^CONFIG_LOCALVERSION=.*/CONFIG_LOCALVERSION=\"${KVER_MINOR}\"/g' files/dot.config > ${SRC_DIR}/${KERNEL}/.config
	ARCH=x86_64 make -C ${SRC_DIR}/${KERNEL} menuconfig
	(cd ${SRC_DIR}/${KERNEL}/; cp -v  .config .config.tmp ;\
	sed -e 's/^CONFIG_LOCALVERSION=.*/CONFIG_LOCALVERSION=\"${KVER_MINOR}\"/g' .config.tmp > .config ;\
	rm .config.tmp )
	(cp ${SRC_DIR}/${KERNEL}/.config files/dot.config ; touch ${SRC_DIR}/${KERNEL}/.config)

.PHONY: installkernel
installkernel: 
	mkdir -p ~/bin/
	egrep -v "run-parts --verbose|/etc/kernel/postinst.d" /sbin/installkernel > ~/bin/installkernel
	chmod +x ~/bin/installkernel

.PHONY: qemu
qemu: 
	if [ ! -d ${SRC_DIR}/${QEMU} ]; then \
	(wget -c ${QEMU_URI} ; \
	tar xf ${QEMU_FILE} -C ${SRC_DIR}; rm ${QEMU_FILE}) ; fi
	(cd ${SRC_DIR}/${QEMU}; \
	./configure --prefix=${TOP_DIR}/qemu/${QEMU}/ --enable-kvm --target-list=x86_64-softmmu ; \
	time make -j 20 install ;\
	)

.PHONY: busybox
busybox: ${SRC_DIR}/${BUSYBOX}/_install

${SRC_DIR}/${BUSYBOX}/_install: 
	if [ ! -d ${SRC_DIR}/${BUSYBOX} ]; then \
	wget -c ${BUSYBOX_URI} ; \
	tar xf ${BUSYBOX_FILE} -C ${SRC_DIR}; rm ${BUSYBOX_FILE} ; fi
	cp files/dot.config.busybox ${SRC_DIR}/${BUSYBOX}/.config
	(cd ${SRC_DIR}/${BUSYBOX} ; \
	make menuconfig ; \
	time make -j 20 install )
	cp ${SRC_DIR}/${BUSYBOX}/.config files/dot.config.busybox 

.PHONY: files
files:
	cp files/kvm ${TOP_DIR}/sbin/
	if [ ! -f /etc/network/interfaces.d/kbr0 ]; then \
	cp files/kbr0 /etc/network/interfaces.d/ ; \
	cp files/masquerade.sh /etc/network/ ; \
	ifup kbr0 ; fi
	if [ ! -f /etc/sysctl.d/00-forward.conf ]; then \
	cp files/00-forward.conf /etc/sysctl.d/00-forward.conf ; \
	sysctl -p /etc/sysctl.d/00-forward.conf ; \
	fi
	cp files/qemu-ifup ${TOP_DIR}/etc/

hosts:
	bash files/hosts_gen.sh

template: 
	if [ ! -f ${TOP_DIR}/data/${TEMPLATE} ]; then \
	dd if=/dev/zero of=${TOP_DIR}/data/${TEMPLATE} bs=1024 seek=9999999 count=1 ; \
	mkfs.ext4 ${TOP_DIR}/data/${TEMPLATE} ; \
	mkdir -p ${TOP_DIR}/mnt/tmp ; \
	mount -o loop ${TOP_DIR}/data/${TEMPLATE} ${TOP_DIR}/mnt/tmp/ ; \
	debootstrap --include=openssh-server,openssh-client,rsync,pciutils,tcpdump,strace,libpam-systemd jessie ${TOP_DIR}/mnt/tmp/ http://ftp.jp.debian.org/debian ; \
	echo "root:root" | chpasswd --root ${TOP_DIR}/mnt/tmp/ ; \
	apt-get -o RootDir=${TOP_DIR}/mnt/tmp/ clean ;\
	umount ${TOP_DIR}/mnt/tmp ;\
	fi
	cp ${TOP_DIR}/data/${TEMPLATE} ${TOP_DIR}/data/test.img

template-modify:
	if [ -f ${TOP_DIR}/data/${TEMPLATE} ]; then \
	mount -o loop ${TOP_DIR}/data/${TEMPLATE} ${TOP_DIR}/mnt/tmp/ ; \
	if [ -f /root/.ssh/authorized_keys ]; then \
	mkdir -p ${TOP_DIR}/mnt/tmp/root/.ssh && chmod 700 ${TOP_DIR}/mnt/tmp/root/ && cp ~/.ssh/authorized_keys ${TOP_DIR}/mnt/tmp/root/.ssh/ ;\
	cp /etc/hosts ${TOP_DIR}/mnt/tmp/etc/ ;\
	fi ; \
	umount ${TOP_DIR}/mnt/tmp ;\
	fi
	cp ${TOP_DIR}/data/${TEMPLATE} ${TOP_DIR}/data/test.img

