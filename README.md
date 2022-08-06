# Install Alpine Linux on Oracle Cloud Ampere aarch64

Any Linux can be replaced remotely on a KVM-style hypervisor, this repository
contains steps and scripts to replace Linux on an Ampere VM with GPT and EFI.

## Manual Steps

Create the instance with Oracle Linux 8.0 (any Linux with dd and wget),
connect with ssh or the serial console then from a root prompt:

    cd /tmp
    wget https://dl-cdn.alpinelinux.org/alpine/v3.16/releases/aarch64/alpine-virt-3.16.1-aarch64.iso
    dd if=alpine-virt-3.16.1-aarch64.iso of=/dev/sda
    reboot

Connect to the serial console and login as root:

    udhcpc eth0
    setup-apkrepos
    apk add curl
    curl https://raw.githubusercontent.com/drcrane/nim/master/oraclecloudsetup.sh |ash

Did you know that github hosts users public keys in a well-known location?
I wonder what that would be useful for?

    https://github.com/drcrane.keys
