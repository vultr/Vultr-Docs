#!/bin/bash
################################################
## Build example snapshot for Vultr Marketplace
## Tested on Ubuntu 20.04
################################################

######################
## Prerequisite steps
######################

set -eo pipefail
## Update the server.
apt-get -y update
apt-get -y upgrade
apt-get -y autoremove
apt-get -y autoclean

#############################################
## Install vultr-support branch of cloud-init
#############################################
cd /tmp
wget https://ewr1.vultrobjects.com/cloud_init_beta/cloud-init_universal_latest.deb
wget https://ewr1.vultrobjects.com/cloud_init_beta/universal_latest_MD5
sleep 10
echo "Expected MD5SUM:"
cat /tmp/universal_latest_MD5
echo "Computed MD5SUM:"
echo "$(md5sum /tmp/cloud-init_universal_latest.deb)"
apt-get update -y
sleep 10

apt-get install -y /tmp/cloud-init_universal_latest.deb
sleep 10

## Create script folders for cloud-init
mkdir -p /var/lib/cloud/scripts/per-boot/
mkdir -p /var/lib/cloud/scripts/per-instance/

## Make a per-boot script.
cat << "EOFBOOT" > /var/lib/cloud/scripts/per-boot/setup.sh
#!/bin/bash
## Run on every boot.
echo $(date -u) ": System booted." >> /var/log/per-boot.log
EOFBOOT

## Make a per-instance script.
cat << "EOFINSTANCE" > /var/lib/cloud/scripts/per-instance/provision.sh
#!/bin/bash
## Runs once-and-only-once at first boot per instance.
echo $(date -u) ": System provisioned." >> /var/log/per-instance.log

## Capture Marketplace Password Variables
DEMO_PASSWORD=$(curl -H "METADATA-TOKEN: vultr" http://169.254.169.254/v1/internal/app-demo_password)
WEB_PASSWORD=$(curl -H "METADATA-TOKEN: vultr" http://169.254.169.254/v1/internal/app-web_password)

## Create user
adduser demo --gecos "First Last,RoomNumber,WorkPhone,HomePhone" --disabled-password
## Set Password
echo demo:$DEMO_PASSWORD | chpasswd

## Report the Web Password
echo "The Web password is: $WEB_PASSWORD" > /root/web-password.txt
EOFINSTANCE

# Make the scripts executable
chmod +x /var/lib/cloud/scripts/per-boot/setup.sh
chmod +x /var/lib/cloud/scripts/per-instance/provision.sh

set +eo pipefail
##########################################
## Prepare server snapshot for Marketplace
##########################################

## Clean the temporary directories, SSH keys, logs, history, etc.
rm -rf /tmp/*
rm -rf /var/tmp/*
rm -f /root/.ssh/authorized_keys /etc/ssh/*key*
touch /etc/ssh/revoked_keys
chmod 600 /etc/ssh/revoked_keys

## Clean the logs.
find /var/log -mtime -1 -type f -exec truncate -s 0 {} \;
rm -rf /var/log/*.gz
rm -rf /var/log/*.[0-9]
rm -rf /var/log/*-????????
echo "" >/var/log/auth.log

## Clean old cloud-init information.
rm -rf /var/lib/cloud/instances/*

## Clean the session history.
history -c
cat /dev/null > /root/.bash_history
unset HISTFILE

## Update the mlocate database.
/usr/bin/updatedb

## Wipe random seed files.
rm -f /var/lib/systemd/random-seed

## Distributions that use systemd should wipe the machine identifier to prevent boot problems.
rm -f /etc/machine-id
touch /etc/machine-id

## Clear the login log history.
cat /dev/null > /var/log/lastlog
cat /dev/null > /var/log/wtmp

## Wipe unused disk space with zeros for security and compression.
echo "Clearing free disk space. This may take several minutes."
dd if=/dev/zero of=/zerofile status=progress
sync
rm /zerofile
sync
echo "Setup is complete. Begin snapshot process."
