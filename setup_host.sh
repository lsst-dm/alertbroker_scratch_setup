#!/bin/bash

set -euo pipefail

if [ -z ${1+x} ]; then
    echo "usage: setup_host.sh IPADDRESS"
    echo "	an IP address must be specified"
    exit 1
fi

IP=$1

echo "copying files up"
rsync kafka.service zookeeper.service install_broker.sh $IP:/tmp/provision_scripts

echo "executing remote install"
ssh $IP 'cd /tmp/provision_scripts && sudo ./install_broker.sh'
