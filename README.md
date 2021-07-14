# alertbroker_scratch_setup #

This repo documents how the Scratch Alert Broker infrastructure is set up.

The Kafka broker is available at `alertbroker-scratch.lsst.codes`, accessible to
the internet but with a shared password.

The Confluent Schema Registry instance is available at
`alertschemas-scratch.lsst.codes`, accessible to the internet under HTTPS. All
reads are world-public, while writing requires HTTP BASIC auth credentials.

## Using the Kafka Broker

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

## Using the Schema Registry

Beware that this, too, is a temporary scratch instance for developing libraries
and clients. Anything can disappear without warning!

You can use the Schema Registry with `curl`; it's accessible at
`https://alertschemas-scratch.lsst.codes`. In general, **reading** data is
world-public, while **writing** data (or deleting it) is restricted by a
username and password.

You can get the password by asking for it nicely from @swnelson or @ecbellm on
LSST slack.

Here are some example public read commands:
```
# Get a list of all subjects in the registry:
curl --request GET https://alertschemas-scratch.lsst.codes/subjects
```

```
# Get the latest schema version of a subject in the registry:
SCHEMA_SUBJECT=some-cool-name
curl --request GET \
  https://alertschemas-scratch.lsst.codes/subjects/${SCHEMA_SUBJECT}/versions/latest
```

```
# Get a Schema by unique ID
curl https://alertschemas-scratch.lsst.codes/schemas/ids/1
```

And some private write commands:
```
# Create a new schema:
SCHEMA_SUBJECT=some-cool-name
PASSWORD=supersecret
curl \
  --request POST \
  --header "Content-Type: application/vnd.schemaregistry.v1+json" \
  --data '{"schema": "{\"type\": \"string\"}"}' \
  --user "admin:$PASSWORD" \
  "https://alertschemas-scratch.lsst.codes/subjects/${SCHEMA_SUBJECT}/versions"
```

```
# Delete a schema:
SCHEMA_SUBJECT=some-cool-name
PASSWORD=supersecret
curl \
  --request DELETE \
  --user "admin:$PASSWORD" \
  "https://alertschemas-scratch.lsst.codes/subjects/${SCHEMA_SUBJECT}/versions"
```

## How this was set up

First, I set up a Kafka broker. Details are in
[./provisioning/broker](./provisioning/broker).

Second, I set up a Confluent Schema Registry. Details are in
[./provisioning/registry](./provisioning/registry)
