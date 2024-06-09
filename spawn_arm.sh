#!/bin/bash -e

# Color Codes
RED="\e[31m"
GREEN="\e[32m"
YELLOW="\e[33m"
RED_BOLD="31"
GREEN_BOLD="32"
YELLOW_BOLD="33"
BOLDGREEN="\e[1;${GREEN_BOLD}m"
BOLDRED="\e[1;${RED_BOLD}m"
BOLDYELLOW="\e[1;${YELLOW_BOLD}m"
ENDCOLOR="\e[0m"

if [ $UID -ne 0 ]; then
	echo "This script must be run as root" >&2
	exit 1
fi

function usage()
{
	printf "\nUsage: $0 <${BOLDYELLOW}container_name${ENDCOLOR}> [${BOLDYELLOW}mirror${ENDCOLOR}]\n" >&2
	printf "\n(Default archive): ./spawn.sh compiler\n"
	printf "(Archive  mirror): ./spawn.sh compiler http://mirror.us-tx.kamatera.com/ubuntu\n"
	printf "\n[${BOLDYELLOW}!${ENDCOLOR}] Mirror list: http://mirrors.ubuntu.com/mirrors.txt\n\n"
	exit 1
}

if [ -z $1 ]; then
	printf "\n[${BOLDRED}-${ENDCOLOR}] ${BOLDRED}Missing machine name${ENDCOLOR}\n"
	usage
elif [[ $1 == *"/"* ]]; then
	printf "\n[${BOLDRED}-${ENDCOLOR}] ${BOLDRED}Invalid machine name or incorrect order of args${ENDCOLOR}\n"
	usage
elif [[ -f "preferred_mirror" && $# -ne 2 ]]; then
	MIRROR=`<preferred_mirror`
	printf "\n[+] Using preferred mirror: $MIRROR\n"
elif [[ -f "preferred_mirror" && $# -eq 2 ]]; then
	echo $2 > preferred_mirror
	MIRROR=`<preferred_mirror`
	printf "\n[${BOLDYELLOW}!${ENDCOLOR}] Overwriting preferred mirror: $MIRROR\n"
elif [ $# -eq 2 ]; then
	MIRROR=$2
	echo $MIRROR > preferred_mirror
	printf "\n[+] Setting preferred mirror: $MIRROR\n"
else
	MIRROR=http://archive.ubuntu.com/ubuntu
	printf "\n[+] Using default mirror: $MIRROR\n"
fi

function dep_check()
{
	if [[ `dpkg -l | grep -o $1` ]]; then
		printf "[${BOLDGREEN}+${ENDCOLOR}] $1: ${BOLDGREEN}OK${ENDCOLOR}\n"
	else
		printf "[${BOLDRED}-${ENDCOLOR}] $1: ${BOLDRED}Not found${ENDCOLOR}\n\n"
		printf "[${BOLDGREEN}+${ENDCOLOR}] Updating package index\n\n"
		apt update
		printf "[${BOLDGREEN}+${ENDCOLOR}] Installing $1\n\n"
		apt install -y $1
	fi
}

# Custom machine name to be used with systemd-nspawn -M <machine_name>
container="$1"

printf "\n[${BOLDGREEN}+${ENDCOLOR}] Checking required packages\n\n"
# Check whether dependencies are installed. If yes, skip
# If not, update the package repos and pull packages required for the build (done on Kali)
dep_check debootstrap
dep_check systemd-container
dep_check bridge-utils
dep_check qemu-user-static # this is required for builing amd64 containers on ARM 

printf "\n[${BOLDGREEN}+${ENDCOLOR}] Creating necessary build directories and configuring permissions\n"
# systemd-nspawn looks for --machine in /var/lib/machines
mkdir -p /var/lib/machines/"$container"
# Allow only-root access to the machines directory
chown root:root /var/lib/machines
chmod 700 /var/lib/machines

printf "\n[${BOLDGREEN}+${ENDCOLOR}] Building minimal Ubuntu 16.04 image at: /var/lib/machines/$container\n"
printf "\n[${BOLDYELLOW}!${ENDCOLOR}] This might take a while\n\n"
# Build a minimal Ubuntu 16.04 LTS (Xenial Xerus) container packaged with
# tools required for compiling exploits that would work for similar releases

# Custom machine name to be used with systemd-nspawn -M <machine_name>
container="$1"

# Build the minimal Ubuntu 16.04 image
debootstrap --foreign --arch=amd64 --include=binutils,make,gcc-5,build-essential,gcc-multilib xenial /var/lib/machines/"$container" $MIRROR

# Copy qemu-user-static binary to the chroot environment
cp /usr/bin/qemu-aarch64-static /var/lib/machines/"$container"/usr/bin/

# Enter the chroot environment and complete the installation
chroot /var/lib/machines/"$container" /bin/bash -c '
    /debootstrap/debootstrap --second-stage
'

# Remove the copied qemu-aarch64-static binary
rm /var/lib/machines/"$container"/usr/bin/qemu-aarch64-static

sed '/^root:/ s|\*||' -i "/var/lib/machines/$container/etc/shadow" # passwordless login
rm "/var/lib/machines/$container/etc/resolv.conf" # systemd configures this
# https://github.com/systemd/systemd/issues/852
[ -f "/var/lib/machines/$container/etc/securetty" ] && \
	printf 'pts/%d\n' $(seq 0 10) >>"/var/lib/machines/$container/etc/securetty"
# Alias gcc-5 to gcc
echo "alias gcc='gcc-5'" >> /var/lib/machines/$container/root/.bash_aliases
# Query container size and location on FS
size=$(du -h /var/lib/machines/"$container" | grep "$container"$)

echo "
################################################################################################

[+] Ubuntu 16.04 container spawned successfully on ARM device. To boot up, use the following command:
    root@kali:~# systemd-nspawn -M $container
[!] To exit out of the container, simply type exit and hit Enter
[!] Container size and location on disk: $size
[!] To remove the container from your system, use the following command:
    root@kali:~# machinectl remove $container
[!] You can always send a SIGKILL by pressing ^] three times within 1 second ( Ctrl + ]]] )

################################################################################################
"