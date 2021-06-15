# alertbroker_scratch_setup #

This repo documents how the Scratch Alert Broker (which runs at
`alertbroker-scratch.lsst.codes`) is set up. This is not a "how-to" document -
it's a "what I did" document.

## Usage

Beware that this is a temporary scratch broker for developing libraries and
clients. It can disappear at any moment without warning, and has no redundancy!

You can use the alertbroker with any Kafka client; it's accessible on the
internet at `alertbroker-scratch.lsst.codes:9092`. It uses password-based auth;
ask `swnelson@uw.edu` or `ecbellm@uw.edu` for the password.

Here's an example `kafkacat` configuration file:

```
security.protocol=SASL_SSL
sasl.mechanisms=SCRAM-SHA-256
sasl.username=admin
sasl.password=<REDACTED>
```

## Overview

The general gist is:
 1. A new
    [project](https://cloud.google.com/resource-manager/docs/creating-managing-projects)
    named `alert-stream` was created in the Scratch folder of the GCP IDF
    account.
 2. GCP resources were created:
    - A VPC network
    - Firewall rules permitting Kafka traffic and HTTP port 80
    - A static external IP address
    - A VM host to run the broker
    - A disk attached to the VM
    - SSH public key for accessing the VM
 3. A DNS record was created by the SQuaRE team, giving a name to the external
    IP address.
 4. Scripts and configs were copied onto the host with
    [`./setup_host.sh`](./setup_host.sh).
 5. Dependencies were installed, configs were copied into place, and systemd
    units were installed to run the broker. This is described in
    [`./install_broker.sh`](./install_broker.sh) - but in reality that script
    was written after working on the host, so it may miss some commands that
    were done by hand.

These steps are covered in more detail below.

## The GCP project

The GCP project is named `alert-stream` and is in the `Scratch` folder, which
indicates that it may be destroyed at any time and is just a workspace for
exploring GCP infrastructure.

## GCP resources

All resources were created by clicking around in the Google Cloud console.

Each section here includes a link to the created resource(s). You may need to
change accounts after clicking on these links.

### VPC Network

Link: [`broker-network`](https://console.cloud.google.com/networking/networks/details/broker-network?project=alert-stream)

The `broker-network` network is the only one. I left options to their defaults
when I created it, which meant that it created subnets for all regions.

### Firewall rules

Links:
[`broker-permit-kafka`](https://console.cloud.google.com/networking/firewalls/details/broker-permit-kafka?project=alert-stream),
[`broker-permit-http`](https://console.cloud.google.com/networking/firewalls/details/broker-permit-http?project=alert-stream)

Two firewall rules here. `broker-permit-kafka` allows TCP traffic from any IP
address on port 9092, which is the conventional port for Kafka traffic. This was
enabled for all instances `broker-network`.

`broker-permit-http` allows TCP traffic from any IP address on port 80. This is
only used to complete a LetsEncrypt ACME flow to get a free TLS certificate
which is installed in the Kafka broker. We need the TLS cert so that password
auth can be done over an encrypted channel; without it we'd have plaintext
passwords over the wire.

In principle, `broker-permit-http` should only be enabled when we're actively
attempting a LetsEncrypt ACME flow since that's only done when trying to renew a
certificate (or get one for the first time). But in general, nothing is
listening to port 80, so this should be OK.

### Static External IP address

Link: [list of external IPs](https://console.cloud.google.com/networking/addresses/list?project=alert-stream)

By default, a VM created in GCP has an ephemeral public IP address which may
change. This makes it impossible to assign a public DNS name to the VM. So, I
created a static IP which would be attached to the VM.

### VM Host

Link: [`broker`](https://console.cloud.google.com/compute/instancesDetail/zones/us-west1-b/instances/broker?project=alert-stream&rif_reserved)

`broker` is a single VM host is intended to run the Kafka broker as well as
Zookeeper.

The VM is launched in the `us-west-1` region because it has cheap prices and is
close to Seattle, where I work.

The machine type is `e2-highmem-4` (4 vCPUs, 32 GB memory) because Coonfluent's
recommendations emphasize using at least 32 GB when running Kafka:

> A machine with 64 GB of RAM is a decent choice, but 32 GB machines are not
> uncommon. Less than 32 GB tends to be counterproductive.

from ["Running Kafka in
Production"](https://docs.confluent.io/platform/current/kafka/deployment.html)

The boot disk is Ubuntu 18.04 LTS. I chose Ubuntu because I'm familiar with it
and it has good packaging tools. I chose 18.04 LTS because it's the most recent
LTS release with plenty of packages available; 20.04 is still a little fresh.

### Persistent disk

Link: [`broker-storage`](https://console.cloud.google.com/compute/disksDetail/zones/us-west1-b/disks/broker-storage?project=alert-stream)

A persistent disk named `broker-storage` has 500GB, with a type of "balanced
persistent disk". These are just the defaults, I didn't think hard about them.

### SSH Public Key

Link: [SSH Keys](https://console.cloud.google.com/compute/metadata/sshKeys?authuser=3&project=alert-stream)

SSH public keys can be added to the GCP console. The VM will automatically scoop
up the public keys that are added, permitting SSH to the broker. I used SSH for
provisioning because I wasn't sure exactly what I needed, so I wanted rapid
iteration, which is easiest with a terminal session on a machine.

## DNS Record

SQuaRE set up a DNS record. Specifically, it's an A record pointing
`alertbroker-scratch.lsst.codes` to the external static IP address that was
provisioned above. Discussion was [here in LSST
Slack](https://lsstc.slack.com/archives/C2JP8GGVC/p1623434605009900).

## Provisioning upload

This is pretty straightforward - everything that is needed is uploaded onto the
VM at `/tmp/provision_scripts`. The things that were uploaded are:

 - Main install script [`install_broker.sh`](./install_broker.sh)
 - systemd service definitions:
   - [`zookeeper.service`](./zookeeper.service)
   - [`kafka.service`](./kafka.service)
   - [`cert_renewal.service`](./cert_renewal.service)
   - [`cert_renewal.timer`](./cert_renewal.timer)
 - Kafka configuration [`server.properties`](./server.properties)

Then, I would SSH onto the VM and run `cd /tmp/provision_scripts && sudo
./install_broker.sh`.

## Installation

The installation has these steps:

1. Host configuration: set up directories, set up the hostname, etc
2. Dependency installation: Just Java!
3. TLS certificate setup: Using EFF's [`certbot`](https://certbot.eff.org/), get
   a TLS certificate from LetsEncrypt, and then package it for Kafka.
4. Kafka installation: Download a Kafka release and extract it.
5. Admin account setup: Set up an `admin` account, accepting a password over
   `stdin`. Zookeeper needs to be running for this step.
6. Turn Kafka on: done with a systemd service.
7. Turn cert renewal on: also done with a systemd service.

### Host configuration

I needed to set the (fully-qualified) hostname because Kafka uses it to identify
the broker.

This was done with `hostnamectl set-hostname`, since this takes effect
immediately without requiring a restart.

Next, `/opt` and `/opt/services` directories were created. These are the
ultimate home of our installed software (Kafka, Zookeeper, and systemd service
definitions).

### Dependency installation

Not much to say here - `apt update` and then `apt install
openjdk-11-jre-headless` (which is Java).

### TLS certificate setup

Our installation needs TLS certificates because it needs to encrypt Kafka
traffic. It needs to encrypt Kafka traffic because it needs to receive a
password from the user, and the password needs to be transported over the
internet. TLS is necessary to avoid main-in-the-middle snooping of that
password.

TLS certs are associated with a name; we use the Kafka broker's address,
`alertbroker-scratch.lsst.codes`.

#### Using `certbot` for a LetsEncrypt certificate

[LetsEncrypt](https://letsencrypt.org/) is a nonprofit which provides free TLS
certificates. The way this works is that we need to run a web server which
responds to a carefully-crafted HTTP request, proving that we control a
particular domain name.

To do this, I used `certbot`, which is a program for automatically running that
web server flow. I installed it with `apt`, and then ran it headlessly.

TLS certs need an associated email address. I used `swnelson@uw.edu`.

The certificate (and associated trust chain and private key) was installed by
`certbot` into `/etc/letsencrypt/live/alertbroker-scratch.lsst.codes/`.

#### Preparing certs for Kafka

`certbot` produced `PEM`-formatted TLS certificates, but Kafka uses Java
Keystores (JKS) to load TLS certificates, so I needed to do a series of
invocations to change formats. This is tricky; I found [this blog
post](https://ordina-jworks.github.io/security/2019/08/14/Using-Lets-Encrypt-Certificates-In-Java.html)
very helpful.

First, I used `openssl` to convert the `PEM`-format certificate and private key
into `PKCS12`-format. I needed to provide a password for the encrypted PKCS12
file, as well; I arbitrarily chose 'kafka', but this password doesn't really
matter:

```
openssl pkcs12 \
        -export \
        -in /etc/letsencrypt/live/$HOST/cert.pem \
        -inkey /etc/letsencrypt/live/$HOST/privkey.pem \
        -name $HOST \
        -password pass:kafka \
        > /tmp/server.p12
```

Next, I imported that `.p12` file into a JKS, which is done with Java's
`keytool`. The result got named `kafka.server.keystore.jks`, holding the private keys.
```
keytool \
    -importkeystore \
    -srckeystore /tmp/server.p12 \
    -destkeystore /tmp/kafka.server.keystore.jks \
    -srcstoretype pkcs12 \
    -alias $HOST \
    -srcstorepass kafka \
    -deststorepass broker
```

Finally, I loaded the `PEM` certificate chain into a "trust store" JKS,
explaining the authority chain for TLS certs. This was named
`kafka.server.truststore.jks`:

```
keytool \
    -keystore /tmp/kafka.server.truststore.jks \
    -alias CARoot \
    -import \
    -file /etc/letsencrypt/live/$HOST/chain.pem \
    -deststorepass broker \
    -trustcacerts
```

Finally, the resulting JKS stores were moved into a final location at
`/var/private/ssl`, which is referenced [in the Kafka configuration
file](./server.properties#L22-L27):

```
mkdir -p /var/private/ssl
mv /tmp/kafka.server.truststore.jks /var/private/ssl
mv /tmp/kafka.server.keystore.jks /var/private/ssl
```

### Downloading and installing Kafka

I downloaded the latest release of Kafka, version 2.8.0, using curl, and
unpacked the tarball to `/opt/kafka_2.13-2.8.0` (2.13 is the Scala version used
to build Kafka). Then I made a symlink from `/opt/kafka` pointing to
`/opt/kafka_2.13-2.8.0`.

### Creating an admin account

I decided to use SCRAM-SHA-256 authentication. This is a password-based
mechanism, which makes it pretty easy to distribute credentials, and is simple
to set up compared to alternatives like LDAP, Kerberos, or mTLS.

This sort of authentication requires making a user account in Zookeeper. I did
this with the `kafka-configs.sh` script which is shipped with Kafka.

But first, I needed to turn on Zookeeper, which was done by symlinking
[`zookeeper.service`](./zookeeper.service) into `/etc/systemd/system` (which
added a new systemd service). Next, I enabled the service with this:
```
systemctl daemon-reload
systemctl enable zookeeper
service zookeeper start
```

Once zookeeper was on, I could create an admin account. The account needs a
password; I picked one and typed it in and set it to the bash variable `PW`, and
then ran this:

```
/opt/kafka/bin/kafka-configs.sh \
    --zookeeper localhost:2181 \
    --alter \
    --add-config "SCRAM-SHA-256=[password=$PW],SCRAM-SHA-512=[password=$PW]" \
    --entity-type users \
    --entity-name admin
```

The admin account also needed to be registered into Kafka explicitly in its
configuration. I _think_ this has to do with interbroker communication, even
though we only have one broker, but I don't really understand why this was
necessary. Nevertheless, it's [in `server.properties`](./server.properties#L37-L39).

To avoid checking it into source code, the password itself is redacted from
`server.properties`, and instead there's a placeholder value,
`__PASSWORD_PLACEHOLDER`. I ran a `sed `script to replace this placeholder
string with the actual password (which is still in the bash interpreter's `PW`
variable).

### Turn Kafka on

Very similarly to how Zookeeper was enabled, I moved the [Kafka service
definition](./kafka.service) into place in `/etc/systemd/system`, and then
reloaded the systemd daemon and enabled Kafka.

One noteworthy line in the service definition is
[`LimitNOFILE=infinity`](./kafka.service#L12) which is necessary because Kafka
likes to keep a _lot_ of open files.

### Turn Cert renewal on

Finally, I made a little systemd service to re-run `certbot` to renew TLS
certificates. This is done with a systemd timer to run twice daily.

I don't actually think that cert renewal will fully work - I suspect we need to
re-bundle new certs into a JKS trust store, and maybe restart Kafka. This may be
broken; the cert is set to expire in 3 months.

## Verifying that it works

To test that things are working, I first created a topic on the server with this
command:

```
/opt/kafka/bin/kafka-topics.sh \
    --create \
    --topic test-topic \
    --bootstrap-server localhost:9092
```

I actually ran this _before_ having SCRAM auth fully set up, so it worked. It
would need modification if password-based authentication is already enabled.

Then, I made sure I could list broker metadata:

```
$ kafkacat \
    -X sasl.mechanisms=SCRAM-SHA-256 \
    -X security.protocol=SASL_SSL \
    -X sasl.username=admin \
    -X sasl.password=<REDACTED> \
    -L -b alertbroker-scratch.lsst.codes

Metadata for all topics (from broker 0: sasl_ssl://alertbroker-scratch.lsst.codes:9092/0):
 1 brokers:
  broker 0 at alertbroker-scratch.lsst.codes:9092 (controller)
 2 topics:
  topic "__consumer_offsets" with 50 partitions:
    partition 0, leader 0, replicas: 0, isrs: 0
    partition 1, leader 0, replicas: 0, isrs: 0
    partition 2, leader 0, replicas: 0, isrs: 0
    partition 3, leader 0, replicas: 0, isrs: 0
    partition 4, leader 0, replicas: 0, isrs: 0
    partition 5, leader 0, replicas: 0, isrs: 0
    partition 6, leader 0, replicas: 0, isrs: 0
    partition 7, leader 0, replicas: 0, isrs: 0
    partition 8, leader 0, replicas: 0, isrs: 0
    partition 9, leader 0, replicas: 0, isrs: 0
    partition 10, leader 0, replicas: 0, isrs: 0
    partition 11, leader 0, replicas: 0, isrs: 0
    partition 12, leader 0, replicas: 0, isrs: 0
    partition 13, leader 0, replicas: 0, isrs: 0
    partition 14, leader 0, replicas: 0, isrs: 0
    partition 15, leader 0, replicas: 0, isrs: 0
    partition 16, leader 0, replicas: 0, isrs: 0
    partition 17, leader 0, replicas: 0, isrs: 0
    partition 18, leader 0, replicas: 0, isrs: 0
    partition 19, leader 0, replicas: 0, isrs: 0
    partition 20, leader 0, replicas: 0, isrs: 0
    partition 21, leader 0, replicas: 0, isrs: 0
    partition 22, leader 0, replicas: 0, isrs: 0
    partition 23, leader 0, replicas: 0, isrs: 0
    partition 24, leader 0, replicas: 0, isrs: 0
    partition 25, leader 0, replicas: 0, isrs: 0
    partition 26, leader 0, replicas: 0, isrs: 0
    partition 27, leader 0, replicas: 0, isrs: 0
    partition 28, leader 0, replicas: 0, isrs: 0
    partition 29, leader 0, replicas: 0, isrs: 0
    partition 30, leader 0, replicas: 0, isrs: 0
    partition 31, leader 0, replicas: 0, isrs: 0
    partition 32, leader 0, replicas: 0, isrs: 0
    partition 33, leader 0, replicas: 0, isrs: 0
    partition 34, leader 0, replicas: 0, isrs: 0
    partition 35, leader 0, replicas: 0, isrs: 0
    partition 36, leader 0, replicas: 0, isrs: 0
    partition 37, leader 0, replicas: 0, isrs: 0
    partition 38, leader 0, replicas: 0, isrs: 0
    partition 39, leader 0, replicas: 0, isrs: 0
    partition 40, leader 0, replicas: 0, isrs: 0
    partition 41, leader 0, replicas: 0, isrs: 0
    partition 42, leader 0, replicas: 0, isrs: 0
    partition 43, leader 0, replicas: 0, isrs: 0
    partition 44, leader 0, replicas: 0, isrs: 0
    partition 45, leader 0, replicas: 0, isrs: 0
    partition 46, leader 0, replicas: 0, isrs: 0
    partition 47, leader 0, replicas: 0, isrs: 0
    partition 48, leader 0, replicas: 0, isrs: 0
    partition 49, leader 0, replicas: 0, isrs: 0
  topic "test-topic" with 1 partitions:
    partition 0, leader 0, replicas: 0, isrs: 0
```

I similarly ran a few `kafkacat` commands to produce and consume some messages.
