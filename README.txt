This is some scratchy files for setting up Kafka on a box, just with defaults.
Kafka (and Zookeeper) are set up as systemd services.

Usage:
./setup_host.sh HOSTNAME

You'll be prompted to set a password.

Clients need something like this (a kafkacat example):

    security.protocol=SASL_SSL
    sasl.mechanisms=SCRAM-SHA-256
    sasl.username=admin
    sasl.password=reallysecurepasswordyouchose
