# alertbroker_scratch_setup #

This repo documents how the Scratch Alert Broker infrastructure is set up.

The Kafka broker is available at `alertbroker-scratch.lsst.codes`, accessible to
the internet but with a shared password.

The Confluent Schema Registry instance is available at
`alertschemas-scratch.lsst.codes`, accessible to the internet under HTTPS. All
reads are world-public, while writing requires HTTP BASIC auth credentials.

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

## How this was set up

First, I set up a Kafka broker. Details are in
[./provisioning/broker](./provisioning/broker).

Second, I set up a Confluent Schema Registry. Details are in
[./provisioning/registry](./provisioning/registry)
