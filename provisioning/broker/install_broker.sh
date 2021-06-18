#!/bin/bash

set -euo pipefail

HOST='alertbroker-scratch.lsst.codes'
EMAIL='swnelson@uw.edu'

GREEN='\033[;32m'
NO_COLOR='\033[0m'
say_green() {
    printf "${GREEN}setup: $1\n${NO_COLOR}" 1>&2
}

# Host-level setup
say_green "setting hostname to alertbroker-scratch.lsst.codes"
hostnamectl set-hostname $HOST

say_green "preparing /opt directories"
mkdir -p /opt
mkdir -p /opt/services

# Dependencies
say_green "installing Java"

apt update -y
apt install -y \
    openjdk-11-jre-headless

# TLS Certs
say_green "setting up SSL certificate"
say_green "  installing LetsEncrypt Certbot"
apt install -y certbot

say_green "  running certbot"
certbot certonly \
     --standalone \
     --agree-tos \
     --domains $HOST \
     -m $EMAIL \
     -n

say_green "  bundling SSL certificate into Java Keystore"
openssl pkcs12 \
        -export \
        -in /etc/letsencrypt/live/$HOST/cert.pem \
        -inkey /etc/letsencrypt/live/$HOST/privkey.pem \
        -name $HOST \
        -password pass:kafka \
        > /tmp/server.p12

rm /tmp/kafka.server.*.jks
keytool \
    -importkeystore \
    -srckeystore /tmp/server.p12 \
    -destkeystore /tmp/kafka.server.keystore.jks \
    -srcstoretype pkcs12 \
    -alias $HOST \
    -srcstorepass kafka \
    -deststorepass broker

keytool \
    -keystore /tmp/kafka.server.truststore.jks \
    -alias CARoot \
    -import \
    -file /etc/letsencrypt/live/$HOST/chain.pem \
    -deststorepass broker \
    -trustcacerts

say_green "  installing Java Keystore into /var/private/ssl"
mkdir -p /var/private/ssl
mv /tmp/kafka.server.truststore.jks /var/private/ssl
mv /tmp/kafka.server.keystore.jks /var/private/ssl

# Download and unpack kafka
say_green "downloading Kafka"
curl --output /tmp/kafka.tar.gz \
     https://mirrors.ocf.berkeley.edu/apache/kafka/2.8.0/kafka_2.13-2.8.0.tgz

say_green "unpacking Kafka"
tar --directory /opt \
    --file /tmp/kafka.tar.gz \
    --extract \
    --preserve-permissions \
    --ungzip

say_green "symlinking kafka to /opt/kafka"
ln -sf /opt/kafka_2.13-2.8.0 /opt/kafka

say_green "cleaning up Kafka download tarball"
rm /tmp/kafka.tar.gz

say_green "setting up admin account"
say_green "  turning on Zookeeper"
cp zookeeper.service /opt/services/zookeeper.service
ln -sf /opt/services/zookeeper.service /etc/systemd/system/zookeeper.service
systemctl daemon-reload
systemctl enable zookeeper
service zookeeper start

say_green "  please enter admin password:"
read -s PW

/opt/kafka/bin/kafka-configs.sh \
    --zookeeper localhost:2181 \
    --alter \
    --add-config "SCRAM-SHA-256=[password=$PW],SCRAM-SHA-512=[password=$PW]" \
    --entity-type users \
    --entity-name admin

say_green "installing Kafka configuration"
mkdir -p /etc/kafka
cp server.properties /etc/kafka/server.properties
sed -i "s/__PASSWORD_PLACEHOLDER/$PW/g" /etc/kafka/server.properties

say_green "turning on Kafka"
cp kafka.service /opt/services/kafka.service
ln -sf /opt/services/kafka.service /etc/systemd/system/kafka.service
systemctl daemon-reload
systemctl enable kafka
service kafka start

say_green "turning on Cert renewal service"
cp cert_renewal.service /opt/services/cert_renewal.service
cp cert_renewal.timer /opt/services/cert_renewal.timer
ln -sf /opt/services/cert_renewal.service /etc/systemd/system/cert_renewal.service
ln -sf /opt/services/cert_renewal.timer /etc/systemd/system/cert_renewal.timer
systemctl daemon-reload
systemctl enable cert_renewal

say_green "all done!"
