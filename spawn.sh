#!/bin/bash

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

ARCH=`uname -m`
ARM=`test $ARCH == "aarch64"`

# Give up on unsupported architectures before proceeding
case $ARCH in
	x86_64)
		:
		;;
	aarch64)
		:
		;;
	*)
		printf "\n[${BOLDRED}-${ENDCOLOR}] ${BOLDRED}Unsupported architecture: $ARCH${ENDCOLOR}\n\n"
		exit 1
		;;
esac


if [ $UID -ne 0 ]; then
	printf "\n[${BOLDRED}-${ENDCOLOR}] ${BOLDRED}This script must be run as root${ENDCOLOR}\n\n" >&2
	exit 1
fi

function usage()
{
	printf "\nUsage: $0 <container_name> [mirror]\n" >&2
	printf "\n(Spawn using default archive): ./spawn.sh compiler\n"
	printf "(Spawn using archive  mirror): ./spawn.sh compiler http://mirror.us-tx.kamatera.com/ubuntu\n"
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
	printf "\n[${BOLDGREEN}+${ENDCOLOR}] ${BOLDGREEN}Using preferred mirror: $MIRROR${ENDCOLOR}\n"
elif [[ -f "preferred_mirror" && $# -eq 2 ]]; then
	echo $2 > preferred_mirror
	MIRROR=`<preferred_mirror`
	printf "\n[${BOLDYELLOW}!${ENDCOLOR}] Overwriting preferred mirror: $MIRROR\n"
elif [ $# -eq 2 ]; then
	MIRROR=$2
	echo $MIRROR > preferred_mirror
	printf "\n[${BOLDGREEN}+${ENDCOLOR}] ${BOLDGREEN}Setting preferred mirror: $MIRROR${ENDCOLOR}\n"
else
	MIRROR=http://archive.ubuntu.com/ubuntu
	printf "\n[${BOLDGREEN}+${ENDCOLOR}] Using default mirror: $MIRROR\n"
fi

function dep_check()
{
	if [[ `dpkg -l | grep -o $1` ]]; then
		printf "[${BOLDGREEN}+${ENDCOLOR}] $1: ${BOLDGREEN}OK${ENDCOLOR}\n"
	else
		printf "[${BOLDRED}-${ENDCOLOR}] $1: ${BOLDRED}Not found${ENDCOLOR}\n\n"
		printf "[${BOLDGREEN}+${ENDCOLOR}] ${BOLDGREEN}Installing $1${ENDCOLOR}\n\n"
		apt-get install -y $1
	fi
}

# Custom machine name to be used with systemd-nspawn -M <machine_name>
container="$1"

printf "[${BOLDGREEN}+${ENDCOLOR}] Updating package index\n\n"
apt-get update

printf "\n[${BOLDGREEN}+${ENDCOLOR}] Checking required packages\n\n"
# Check whether dependencies are installed. If yes, skip
# If not, pull packages required for the build (done on Kali)
dep_check debootstrap
dep_check systemd-container
dep_check bridge-utils

if [ !$ARM ]; then
	# this is required for builing amd64 containers on ARM
	dep_check qemu-user-static
fi

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
case $ARCH in
	x86_64)
		printf "\n[${BOLDGREEN}+${ENDCOLOR}] Architecture: $ARCH\n\n"
		debootstrap --variant=minbase --include=binutils,make,gcc-5,build-essential,gcc-multilib xenial /var/lib/machines/"$container" $MIRROR
		;;
	aarch64)
		printf "\n[${BOLDGREEN}+${ENDCOLOR}] Architecture: $ARCH\n\n"
		debootstrap --foreign --arch=amd64 --include=binutils,make,gcc-5,build-essential,gcc-multilib xenial /var/lib/machines/"$container" $MIRROR

		# Copy qemu-user-static binary to the chroot environment
		cp /usr/bin/qemu-aarch64-static /var/lib/machines/"$container"/usr/bin/

		# Enter the chroot environment and complete the installation
		chroot /var/lib/machines/"$container" /bin/bash -c '/debootstrap/debootstrap --second-stage'

		# Remove the copied qemu-aarch64-static binary
		rm /var/lib/machines/"$container"/usr/bin/qemu-aarch64-static
		;;
	*)
		printf "\n[${BOLDRED}-${ENDCOLOR}] ${BOLDRED}Unsupported architecture: $ARCH${ENDCOLOR}\n\n"
		exit 1
		;;
esac

# Set passwordless login
sed '/^root:/ s|\*||' -i "/var/lib/machines/$container/etc/shadow"

# systemd uses systemd-resolved
rm "/var/lib/machines/$container/etc/resolv.conf"

# https://github.com/systemd/systemd/issues/852
[ -f "/var/lib/machines/$container/etc/securetty" ] && \
	printf 'pts/%d\n' $(seq 0 10) >>"/var/lib/machines/$container/etc/securetty"

# Alias gcc-5 to gcc
echo "alias gcc='gcc-5'" >> /var/lib/machines/$container/root/.bash_aliases

# Query container size and location on file system
size=$(du -h /var/lib/machines/"$container" | grep "$container"$)

printf "
################################################################################################

[${BOLDGREEN}+${ENDCOLOR}] ${BOLDGREEN}Ubuntu 16.04 container spawned successfully${ENDCOLOR}. To boot up, use the following command:

    kali@kali:~# sudo systemd-nspawn -M $container

[${BOLDYELLOW}!${ENDCOLOR}] To exit out of the container, simply type exit and hit Enter

[${BOLDYELLOW}!${ENDCOLOR}] Container size and location on disk: $size

[${BOLDYELLOW}!${ENDCOLOR}] To remove the container from your system, use the following command:

    kali@kali:~# sudo machinectl remove $container

[${BOLDYELLOW}!${ENDCOLOR}] You can always send a SIGKILL by pressing ^] three times within 1 second ( Ctrl + ]]] )

################################################################################################

"
