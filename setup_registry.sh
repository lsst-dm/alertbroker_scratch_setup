#!/usr/bin/env bash

set -euo pipefail

HOST=alertschemas-scratch.lsst.codes

echo "copying files up"
rsync -r provisioning/registry/ $HOST:/tmp/provisioning/

# The Confluent Schema Registry requires an updated TLS root certificate trust
# chain. It needs this for when it connects to the Kafka broker over TLS.
# Without it, it doesn't really believe that LetsEncrypt has provided a valid
# certificate.
#
# I'm not totally sure why this is. It seems like Java 11 (which I think we're
# using?) ought to have the right trust chains already. But without it, we get
# TLS errors when the registry starts up, attempting to connect to the Kafka
# broker.
echo "copying broker TLS chain"
ssh alertbroker-scratch.lsst.codes "sudo cp /etc/letsencrypt/live/alertbroker-scratch.lsst.codes/chain.pem /tmp/chain.pem && sudo chmod a+r /tmp/chain.pem"
scp alertbroker-scratch.lsst.codes:/tmp/chain.pem /tmp/broker-chain.pem
scp /tmp/broker-chain.pem $HOST:/tmp/provisioning/broker-chain.pem

echo "installing"
ssh -t $HOST "cd /tmp/provisioning && sudo ./install_registry.sh"
