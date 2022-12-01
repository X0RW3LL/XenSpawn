#!/bin/bash -e

if [ $UID -ne 0 ]; then
	echo "This script must be run as root" >&2
	exit 1
fi

if [ -z "$1" ]; then
	echo "Usage: $0 <container_name>" >&2
	exit 0
fi

# Custom machine name to be used with systemd-nspawn -M <machine_name>
container="$1"

echo
echo "[+] Installing required packages" && echo
# Update package repos and pull packages required for the build (done on Kali)
apt update && apt install -y debootstrap systemd-container bridge-utils

echo
echo "[+] Creating necessary build directories and configuring permissions"
# systemd-nspawn looks for --machine in /var/lib/machines
mkdir -p /var/lib/machines/"$container"
# Allow only-root access to the machines directory
chown root:root /var/lib/machines
chmod 700 /var/lib/machines

echo
echo "[+] Building minimal Ubuntu 16.04 image at: /var/lib/machines/$container"
echo "[!] This might take a while" && echo
# Build a minimal Ubuntu 16.04 LTS (Xenial Xerus) container packaged with
# tools required for compiling exploits that would work for similar releases
debootstrap --variant=minbase --include=binutils,make,gcc-5,build-essential,gcc-multilib xenial /var/lib/machines/"$container" http://archive.ubuntu.com/ubuntu
sed '/^root:/ s|\*||' -i "/var/lib/machines/$container/etc/shadow" # passwordless login
rm "/var/lib/machines/$container/etc/resolv.conf" # systemd configures this
# https://github.com/systemd/systemd/issues/852
[ -f "/var/lib/machines/$container/etc/securetty" ] && \
	printf 'pts/%d\n' $(seq 0 10) >>"/var/lib/machines/$container/etc/securetty"
# Alias gcc-5 to gcc
echo "alias gcc='gcc-5'" >> /var/lib/machines/$container/root/.bash_aliases
# Query container size and location on FS
size=$(du -h /var/lib/machines/"$container" | grep "$container"$)

echo
echo "################################################################################################"
echo
echo "[+] Ubuntu 16.04 container spawned successfully. To boot up, use the following command:" && echo
echo "    kali@kali:~$ systemd-nspawn -M $container" && echo
echo "[!] To exit out of the container, simply type exit and hit Enter"
echo "[!] Container size and location on disk: $size"
echo "[!] To remove the container from your system, use the following command:" && echo
echo "    kali@kali:~$ machinectl remove $container" && echo
echo "[!] You can always send a SIGKILL by pressing ^] three times within 1 second ( Ctrl + ]]] )"
echo
echo "################################################################################################"

