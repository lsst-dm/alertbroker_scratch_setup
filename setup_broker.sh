#!/bin/bash

set -euo pipefail

HOST=alertbroker-scratch.lsst.codes

echo "copying files up"
ssh $HOST 'mkdir -p /tmp/provision_scripts'
rsync -r provisioning/broker $HOST:/tmp/provision_scripts
cd -

echo "executing remote install"
ssh $HOST 'cd /tmp/provision_scripts && sudo ./install_broker.sh'
