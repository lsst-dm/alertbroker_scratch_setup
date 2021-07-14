# Confluent Schema Registry Setup

This documents how the Scratch Confluent Schema Registry (which runs at
https://alertschemas-scratch.lsst.codes) is set up. This is not a "how-to"
document - it's a "what I did" document.

## Overview

Once the [Kafka Broker was set up](../broker/README.md), it was possible to add a
Confluent Schema Registry instance.

1. GCP resources were created:
   - A VM host to run the registry
   - A disk attached to the VM
   - A static external IP address
   - A firewall rule permitting TCP port 443 for HTTPS traffic
2. A DNS records was created by the SQuaRE team, giving a name to the external
   IP address.
3. The [`./setup_registry.sh`](../../setup_registry.sh) script was executed.

I ran the `setup_registry.sh` script on a completely fresh VM, so I'm sure it
actually works - or at least, it actually worked that one time.

The actual host runs two primary applications. There's an
[`nginx`](https://www.nginx.com/) web server, and the Confluent Schema Registry
server.

The nginx server exists to do two things:
 1. Require auth to access APIs which allow writes to the Schema Registry
 2. Terminate TLS, since encryption is necessary for our basic auth scheme.

The nginx server has a [configuration file](./nginx.conf) which uses regular
expressions to match requests that are world-public. This forms an explicit
allowlist: anything which matches is immediately passed through to the Schema
Registry. Anything which does not match those explicit checks will fall through
to [a block](./nginx.conf#L63-L67) which enforces BASIC authentication. This
checks whether a username and password are provided, and match an entry in
`/etc/nginx/htpasswd`; if so, the request is passed through. If not, the user
will get a `403` error code, telling them that they are Unauthorized.

## GCP Resources

### VM Host

I provisioned a default host, an e2-medium (2vCPUs, 4GB memory). The Schema
Registry is a lightweight application without many demands, so a small instance
is fine.

I gave it the name "`schema-registry-clean-install`". Originally there was
`schema-registry` while I was testing out provisioning, and then I made this
"clean-install" instance to try running the provisioning script end-to-end.

### VM Disk

I gave the VM a 25 GB disk. I figured it needs a little bit of space to install
system libraries and Java and stuff, but won't use disk for storage - Kafka gets
used as the storage backend.

### Static External IP

Nothing complicated here - this just ensures that the host is
internet-accessible, and that DNS can be done stably from SQuaRE's AWS account.

### Firewall rule

Port 443 is opened up so the host can serve HTTPS traffic.

## Provisioning

Provisioning is done with a script which is thoroughly documented. See
[./install_registry.sh](./install_registry.sh).
