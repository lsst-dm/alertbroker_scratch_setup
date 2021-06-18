#!/usr/bin/env bash

set -euo pipefail

HOST=alertschemas-scratch.lsst.codes

echo "copying files up"
rsync -r provisioning/registry/ $HOST:/tmp/provisioning/

echo "copying broker TLS chain"
ssh alertbroker-scratch.lsst.codes "sudo cp /etc/letsencrypt/live/alertbroker-scratch.lsst.codes/chain.pem /tmp/chain.pem && sudo chmod a+r /tmp/chain.pem"
scp alertbroker-scratch.lsst.codes:/tmp/chain.pem /tmp/broker-chain.pem
scp /tmp/broker-chain.pem $HOST:/tmp/provisioning/broker-chain.pem

echo "installing"
ssh -t $HOST "cd /tmp/provisioning && sudo ./install_registry.sh"
