#!/usr/bin/env bash

## Set script options to fail loudly in case of an error, rather than muddling
## through.
set -euo pipefail

## Give a little colorful output to highlight human-readable messages from the
## verbose output of the subcommand here.
GREEN='\033[;32m'
NO_COLOR='\033[0m'
say_green() {
    printf "${GREEN}setup: $1\n${NO_COLOR}" 1>&2
}

## Install Java, which is a dependency of the Confluent Schema Registry. 11 is
## the latest version at the time of writing. 'headless' means we don't need any
## GUI elements.
say_green "installing Java"
apt-get update -y
apt-get install -y \
        openjdk-11-jre-headless

## Install the Confluent Schema Registry. This is done following the
## instructions at
## https://docs.confluent.io/platform/current/installation/installing_cp/deb-ubuntu.html#systemd-ubuntu-debian-install:
## we add Confluent's Aptitude repository (and its keys, so apt trusts it), and
## then install from there.
say_green "installing Confluent Schema Registry"
wget -qO - https://packages.confluent.io/deb/5.5/archive.key | sudo apt-key add -
add-apt-repository "deb [arch=amd64] http://packages.confluent.io/deb/5.5 stable main"
apt-get update -y
apt-get install -y confluent-schema-registry

## The 'apt-get install -y confluent-schema-registry' command above
## automatically added a user, cp-schema-registry, which is intended to run the
## registry. We need to give it access to a log directory.
say_green "install schema registry in systemd"
chown cp-schema-registry:confluent /var/log/confluent && chmod u+wx,g+wx,o= /var/log/confluent

## We need the full chain of trust that was used to generate the Kafka broker's
## TLS certificate. I don't really know *why* we need to do this; I expected
## that Java would already have this in its cacerts file. But apparently not -
## we need to explicitly import this.
say_green "installing LetsEncrypt trust chain for broker certificate"
keytool -trustcacerts \
        -keystore /usr/lib/jvm/java-11-openjdk-amd64/lib/security/cacerts \
        -storepass changeit \
        -noprompt \
        -importcert \
        -file /tmp/provisioning/broker-chain.pem

## The Kafka Broker requires a password. This is where we tell the Schema
## Registry that password - it's done in a configuration file,
## /etc/schema-registry/schema-registry.properties.
say_green "installing schema registry configuration"
say_green "  please enter admin password for kafka broker"
read -s "KAFKA_PASSWORD"
sed -i "s/__PASSWORD_PLACEHOLDER/$KAFKA_PASSWORD/g" /tmp/provisioning/schema-registry-custom.properties
cp /tmp/provisioning/schema-registry-custom.properties /etc/schema-registry/schema-registry.properties

## Turn on the Schema registry. The systemd definition for the service already
## references /etc/schema-registry/schema-registry.properties.
say_green "enabling schema registry"
service confluent-schema-registry start

## The schema registry is listening on port 8081. We run a nginx server in
## front, at port 80 and 443, in order which proxies requests to the registry if
## they pass some authentication checks.
##
## We do this because the Schema Registry has no authentication of its own.
say_green "installing nginx frontend"
apt-get install -y nginx

## We need to get a TLS certificate to serve HTTPS traffic from nginx. It's
## easiest to do this with nginx's default configuration file in place, so we
## enable it immediately with its default config. This is done by adding a
## systemd unit file (which is defined inline here) and starting nginx up.
say_green "enabling nginx service with defaults to bootstrap TLS certificate"
cat <<EOF > /etc/systemd/system/nginx.service
[Unit]
Description=The NGINX HTTP and reverse proxy server
After=syslog.target network-online.target remote-fs.target nss-lookup.target
Wants=network-online.target

[Service]
Type=forking
PIDFile=/run/nginx.pid
ExecStartPre=/usr/sbin/nginx -t
ExecStart=/usr/sbin/nginx
ExecReload=/usr/sbin/nginx -s reload
ExecStop=/bin/kill -s QUIT
PrivateTmp=true

[Install]
WantedBy=multi-user.target
EOF
service nginx start

## Use certbot, with a magical nginx plugin (python-certbot-nginx) to fetch
## certificates. They'll be installed into
## /etc/letsencrypt/live/alertschemas-scratch.lsst.codes.
say_green "installing LetsEncrypt certificate for nginx frontend"
apt-get install -y certbot python-certbot-nginx
certbot certonly \
        --nginx \
        -d alertschemas-scratch.lsst.codes \
        -m swnelson@uw.edu \
        --agree-tos \
        -n

## Now install our *actual* nginx configuration.
say_green "configuring nginx"
rm /etc/nginx/sites-enabled/default
cp nginx.conf /etc/nginx/sites-available/registry.conf
cp passthrough.conf /etc/nginx/snippets/passthrough.conf
ln -s /etc/nginx/sites-available/registry.conf /etc/nginx/sites-enabled/registry.conf

## The nginx configuration references an Apache-style password file in
## /etc/nginx/htpasswd. This is a plaintext list of username:passwords for
## access. Anyone in this file will have full access to the registry.
say_green "creating admin user"
printf 'admin:' > /etc/nginx/htpasswd
say_green "  please enter admin password:"
read -s ADMIN_PW
printf "$ADMIN_PW\n" >> /etc/nginx/htpasswd

## Finally, inform nginx that its configuration is updated so it should reload.
say_green "reloading nginx configuration"
service nginx reload

say_green "all done!"
