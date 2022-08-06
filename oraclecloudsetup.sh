#!/bin/ash
set -e
set -x
ALPINERELEASE=v3.16
ALPINEARCH=aarch64
ALPINEHOSTNAME=localhost
ALPINEUSERNAME=user
MOUNTPOINT=/mnt
# Script to setup alpine linux on Oracle Cloud Ampere
mkdir /media/setup
cp -a /media/sda/* /media/setup
mkdir /lib/setup
cp -a /.modloop/* /lib/setup
umount /dev/sda
mv /media/setup/* /media/sda/
mv /lib/setup/* /.modloop/
setup-apkrepos
apk update
apk add dosfstools e2fsprogs sfdisk
dd if=/dev/zero of=/dev/sda bs=8192 count=16
sfdisk /dev/sda <<EOF
label:GPT
1M,256M,C12A7328-F81F-11D2-BA4B-00A0C93EC93B,*
,2048M,S
,,L
EOF
mdev -s
mkfs.vfat /dev/sda1
mkswap /dev/sda2
mkfs.ext4 -O ^has_journal /dev/sda3
modprobe ext4
mount /dev/sda3 ${MOUNTPOINT}
mkdir ${MOUNTPOINT}/boot
mount /dev/sda1 ${MOUNTPOINT}/boot

apk add --update-cache \
	--repository=http://dl-cdn.alpinelinux.org/alpine/${ALPINERELEASE}/main/
	--allow-untrusted \
	--arch=${ALPINEARCH} \
	--root=${MOUNTPOINT} \
	--initdb \
	acct alpine-base alpine-conf linux-virt

mount --bind /dev ${MOUNTPOINT}/dev
mount --bind /dev/pts ${MOUNTPOINT}/dev/pts
mount --bind /dev/shm ${MOUNTPOINT}/dev/shm
mount --bind /proc ${MOUNTPOINT}/proc
mount --bind /run ${MOUNTPOINT}/run
mount --bind /sys ${MOUNTPOINT}/sys

run_root() {
	chroot ${MOUNTPOINT} /usr/bin/env \
		PATH=/sbin:/usr/sbin:/bin:/usr/bin \
		/bin/sh -c "$*"
}

cat >${MOUNTPOINT}/etc/apk/repositories <<EOF
http://dl-cdn.alpinelinux.org/alpine/${ALPINERELEASE}/main
http://dl-cdn.alpinelinux.org/alpine/${ALPINERELEASE}/community
EOF

run_root apk add --no-scripts syslinux
run_root dd if=/usr/share/syslinux/gptmbr.bin of=${LOOPDEV} bs=1 count=440
run_root extlinux -i /boot

mkdir -p ${MOUNTPOINT}/boot/EFI/BOOT/
cp ${MOUNTPOINT}/usr/share/syslinux/efi64/syslinux.efi ${MOUNTPOINT}/boot/EFI/BOOT/bootx64.efi
cp ${MOUNTPOINT}/usr/share/syslinux/efi64/ldlinux.e64 ${MOUNTPOINT}/boot/EFI/BOOT/ldlinux.e64

cat >${MOUNTPOINT}/boot/EFI/BOOT/syslinux.cfg <<EOF
DEFAULT linux
LABEL linux
	LINUX /vmlinuz-virt
	INITRD /initramfs-virt
	APPEND root=/dev/sda3 rw modules=sd-mod,ext4 quiet rootfstype=ext4
EOF

run_root setup-hostname -n ${ALPINEHOSTNAME}
run_root setup-interfaces -i <<EOF
auto lo
iface lo inet loopback

auto eth0
iface eth0 inet dhcp
EOF

cat >>${MOUNTPOINT}/etc/fstab <<EOF
/dev/sda1 /boot ext4 rw,relatime 0 0
/dev/sda2 swap swap defaults 0 0
/dev/sda3 / ext4 rw,relatime 0 0
EOF

run_root apk add openssh haveged doas

run_root rc-update add sshd default
run_root rc-update add crond default
run_root rc-update add haveged default
run_root rc-update add local default
for i in hwclock modules sysctl hostname bootmisc networking syslog swap urandom
do
	run_root rc-update add $i boot
done
for i in mount-ro killprocs savecache
do
	run_root rc-update add $i shutdown
done

sed -e 's/#key_types_to_generate=""/key_types_to_generate="ed25519"/' -i ${MOUNTPOINT}/etc/conf.d/sshd
echo 'sshd_disable_keygen="yes"' >> ${MOUNTPOINT}/etc/conf.d/sshd

sed -e 's/#PermitEmptyPasswords no/PermitEmptyPasswords yes/' \
	-e 's/#HostKey \/etc\/ssh\/ssh_host_ed25519_key/HostKey \/etc\/ssh\/ssh_host_ed25519_key/' \
	-i ${MOUNTPOINT}/etc/ssh/sshd_config


run_root ssh-keygen -t ed25519 -f /etc/ssh/ssh_host_ed25519_key -C "${ALPINEHOSTNAME}" -q -N ""
run_root chown root:root /etc/ssh/ssh_host_ed25519_key
chmod og-rw ${MOUNTPOINT}/etc/ssh/ssh_host_ed25519_key
run_root chown root:root /etc/ssh/ssh_host_ed25519_key.pub

run_root mkdir /root/.ssh
run_root chmod go-rwx /root/.ssh

if [ ! -f id_ed25519.pub ] ; then
run_root ssh-keygen -t ed25519 -f /root/id_ed25519 -C "${ALPINEUSERNAME}@${ALPINEHOSTNAME}" -q -N ""
cp ${MOUNTPOINT}/root/id_ed25519 .
cp ${MOUNTPOINT}/root/id_ed25519.pub .
fi
cat id_ed25519.pub >> ${MOUNTPOINT}/root/.ssh/authorized_keys
run_root adduser -u 1000 -G users -D -h /home/${ALPINEUSERNAME} -s /bin/ash ${ALPINEUSERNAME}
run_root adduser ${ALPINEUSERNAME} wheel
run_root adduser ${ALPINEUSERNAME} kvm
run_root passwd -u ${ALPINEUSERNAME}

printf '%s\n' "permit nopass keepenv :wheel" >> ${MOUNTPOINT}/etc/doas.d/doas.conf
rm -f ${MOUNTPOINT}/etc/motd

pkg_version() {
	name=$(run_root apk list $1 | grep installed | cut -d' ' -f1)
	echo ${name##$1-}
}

run_root apk add linux-virt=$(pkg_version linux-virt)
