#!/usr/bin/env bash

set -euo pipefail

GREEN='\033[;32m'
NO_COLOR='\033[0m'
say_green() {
    printf "${GREEN}setup: $1\n${NO_COLOR}" 1>&2
}

say_green "installing Java"
apt-get update -y
apt-get install -y \
        openjdk-11-jre-headless

say_green "installing Confluent Schema Registry"
wget -qO - http://packages.confluent.io/deb/5.5/archive.key | sudo apt-key add -
add-apt-repository "deb [arch=amd64] http://packages.confluent.io/deb/5.5 stable main"
apt-get update -y
apt-get install -y confluent-schema-registry

say_green "install schema registry in systemd"
chown cp-schema-registry:confluent /var/log/confluent && chmod u+wx,g+wx,o= /var/log/confluent

say_green "installing LetsEncrypt trust chain for broker certificate"
keytool -trustcacerts \
        -keystore /usr/lib/jvm/java-11-openjdk-amd64/lib/security/cacerts \
        -storepass changeit \
        -noprompt \
        -importcert \
        -file /tmp/provisioning/broker-chain.pem

say_green "installing schema registry configuration"
say_green "  please enter admin password for kafka broker"
read -s "KAFKA_PASSWORD"
sed -i "s/__PASSWORD_PLACEHOLDER/$KAFKA_PASSWORD/g" /tmp/provisioning/schema-registry-custom.properties
cp /tmp/provisioning/schema-registry-custom.properties /etc/schema-registry/schema-registry.properties

say_green "enabling schema registry"
service confluent-schema-registry start

say_green "installing nginx frontend"
apt-get install -y nginx

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

say_green "installing LetsEncrypt certificate for nginx frontend"
apt-get install -y certbot python-certbot-nginx
certbot certonly \
        --nginx \
        -d alertschemas-scratch.lsst.codes \
        -m swnelson@uw.edu \
        --agree-tos \
        -n

say_green "configuring nginx"
rm /etc/nginx/sites-enabled/default
cp nginx.conf /etc/nginx/sites-available/registry.conf
cp passthrough.conf /etc/nginx/snippets/passthrough.conf
ln -s /etc/nginx/sites-available/registry.conf /etc/nginx/sites-enabled/registry.conf

say_green "creating admin user"
printf 'admin:' > /etc/nginx/htpasswd
say_green "  please enter admin password:"
read -s ADMIN_PW
printf "$ADMIN_PW\n" >> /etc/nginx/htpasswd

say_green "reloading nginx configuration"
service nginx reload

say_green "all done!"
