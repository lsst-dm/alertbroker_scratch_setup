#!/bin/bash

set -euo pipefail

GREEN='\033[;32m'
NO_COLOR='\033[0m'
say_green() {
    printf "${GREEN}setup: $1\n${NO_COLOR}" 1>&2
}

say_green "setting hostname to alertbroker-scratch.lsst.codes"
hostnamectl set-hostname alertbroker-scratch.lsst.codes

say_green "installing Java"

apt update -y
apt install -y \
    openjdk-11-jre-headless

say_green "preparing /opt directories"
mkdir -p /opt
mkdir -p /opt/services

say_green "downloading Kafka"

# Download and unpack kafka
curl --output /tmp/kafka.tar.gz \
     https://mirrors.ocf.berkeley.edu/apache/kafka/2.8.0/kafka_2.13-2.8.0.tgz

say_green "unpacking Kafka"

tar --directory /opt \
    --file /tmp/kafka.tar.gz \
    --extract \
    --preserve-permissions \
    --ungzip

ln -sf /opt/kafka_2.13-2.8.0 /opt/kafka
say_green "cleaning up Kafka download tarball"

rm /tmp/kafka.tar.gz

say_green "installing systemd services"

cp kafka.service /opt/services/kafka.service
cp zookeeper.service /opt/services/zookeeper.service

ln -sf /etc/systemd/system/kafka.service /opt/services/kafka.service
ln -sf /etc/systemd/system/zookeeper.service /opt/services/zookeeper.service

say_green "restarting systemd daemon"

systemctl daemon-reload

say_green "enabling services"
systemctl enable zookeeper
systemctl enable kafka
service zookeeper start
service kafka start

say_green "all done!"
