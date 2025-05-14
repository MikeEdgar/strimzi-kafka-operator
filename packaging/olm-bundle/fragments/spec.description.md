Strimzi provides a way to run an [Apache Kafka®](https://kafka.apache.org) cluster on
[Kubernetes](https://kubernetes.io/) or [OpenShift](https://www.openshift.com/) in various deployment configurations.
See our [website](https://strimzi.io) for more details about the project.


**!!! IMPORTANT !!!**


**Direct upgrade from Strimzi 0.22 or earlier is not supported anymore!**
You have to upgrade first to one of the previous versions of Strimzi.
You will also need to convert the CRD resources.
For more details, see the [documentation](https://strimzi.io/docs/operators/0.46.0/deploying.html#assembly-upgrade-str).


**From version 0.46, Strimzi supports only Kuberneets 1.25 and newer. Kubernetes 1.23 and 1.24 are not supported anymore.**

**Support for ZooKeeper-based clusters and for migration from ZooKeeper-based clusters to KRaft has been removed.
Please make sure all your clusters are using KRaft before upgrading to Strimzi 0.46.0 or newer!

**Strimzi EnvVar Configuration Provider (deprecated in Strimzi 0.38.0) and Strimzi MirrorMaker 2 Extensions (deprecated in Strimzi 0.28.0) plugins were removed from Strimzi container images.
Please use the Apache Kafka EnvVarConfigProvider and Identity Replication Policy instead.

**Support for MirrorMaker 1 has been removed.
Please make sure to migrate to MirrorMaker 2 before upgrading to Strimzi 0.46 or newer.

### New in 0.46

* Add support for Kafka 4.0.0.
Remove support for Kafka 3.8.0 and 3.8.1.

* Support for ZooKeeper-based Apache Kafka clusters and for KRaft migration has been removed

* Support for MirrorMaker 1 has been removed

* Support for storage class overrides has been removed

* Added support to configure `dnsPolicy` and `dnsConfig` using the `template` sections.

* Store Kafka node certificates in separate Secrets, one Secret per pod.

* Allow configuring `ssl.principal.mapping.rules` and custom trusted CAs in Kafka brokers with `type: custom` authentication

* Moved HTTP bridge configuration to the ConfigMap setup by the operator.

* Dependency updates (Vert.x 4.5.14, Netty 4.1.118.Final)

* Moved Kafka Connect configuration to the ConfigMap created by the operator.

* Update Kafka Exporter to [1.9.0](https://github.com/danielqsj/kafka_exporter/releases/tag/v1.9.0)

* Adopted new Kafka Connect health check endpoint (see [proposal 89](https://github.com/strimzi/proposals/blob/main/089-adopt-connect-health-endpoint.md)).

* Update standalone User Operator to handle Cluster CA cert Secret being missing when TLS is not needed.

* Strimzi Drain Cleaner updated to 1.3.0 (included in the Strimzi installation files)

* Implicit IPv4 preference when enabling JMX has been removed, and will now use JVM defaults.
This will make the cluster boot up correctly in IPv6 only environments, where IPv4 preference will break it due to lack of IPv4 addresses.

* Improved the MirrorMaker2 example Grafana dashboard to set metric units and include chart descriptions.

* The `ContinueReconciliationOnManualRollingUpdateFailure` feature gate moves to GA stage and is permanently enabled without the possibility to disable it.

* Update OAuth library to 0.16.2.

* Update HTTP bridge to 0.32.0.

* Kubernetes events emitted during a Pod restart updated to have the Kafka resource as the `regardingObject` and the Pod in the `related` field.

### Supported Features

* **Manages the Kafka Cluster** - Deploys and manages all of the components of this complex application, including dependencies like Apache ZooKeeper® that are traditionally hard to administer.

* **Supports KRaft** - You can run your Apache Kafka clusters without Apache ZooKeeper.

* **Tiered storage** - Offloads older, less critical data to a lower-cost, lower-performance storage tier, such as object storage.

* **Includes Kafka Connect** - Allows for configuration of common data sources and sinks to move data into and out of the Kafka cluster.

* **Topic Management** - Creates and manages Kafka Topics within the cluster.

* **User Management** - Creates and manages Kafka Users within the cluster.

* **Connector Management** - Creates and manages Kafka Connect connectors.

* **Includes Kafka Mirror Maker 2** - Allows for mirroring data between different Apache Kafka® clusters.

* **Includes HTTP Kafka Bridge** - Allows clients to send and receive messages through an Apache Kafka® cluster via HTTP protocol.

* **Cluster Rebalancing** - Uses built-in Cruise Control for redistributing partition replicas according to specified goals in order to achieve the best cluster performance.

* **Auto-rebalancing when scaling** - Automatically rebalance the Kafka cluster after a scale-up or before a scale-down.

* **Monitoring** - Built-in support for monitoring using Prometheus and provided Grafana dashboards

### Upgrading your Clusters

The Strimzi Operator understands how to run and upgrade between a set of Kafka versions.
When specifying a new version in your config, check to make sure you aren't using any features that may have been removed.
See [the upgrade guide](https://strimzi.io/docs/operators/latest/deploying.html#assembly-upgrading-kafka-versions-str) for more information.

### Storage

An efficient data storage infrastructure is essential to the optimal performance of Apache Kafka®.
Apache Kafka® deployed via Strimzi requires block storage.
The use of file storage (for example, NFS) is not recommended.

The Strimzi Operator supports three types of data storage:

* Ephemeral (Recommended for development only!)

* Persistent

* JBOD (Just a Bunch of Disks, suitable for Kafka only. Not supported in Zookeeper.)

Strimzi also supports advanced operations such as adding or removing disks in Apache Kafka® brokers or resizing the persistent volumes (where supported by the infrastructure).

### Documentation

Documentation to the current _main_ branch as well as all releases can be found on our [website](https://strimzi.io/documentation).

### Getting help

If you encounter any issues while using Strimzi, you can get help using:

* [Strimzi mailing list on CNCF](https://lists.cncf.io/g/cncf-strimzi-users/topics)

* [Strimzi Slack channel on CNCF workspace](https://cloud-native.slack.com/messages/strimzi)

### Contributing

You can contribute by:

* Raising any issues you find using Strimzi

* Fixing issues by opening Pull Requests

* Improving documentation

* Talking about Strimzi

All bugs, tasks or enhancements are tracked as [GitHub issues](https://github.com/strimzi/strimzi-kafka-operator/issues). Issues which
might be a good start for new contributors are marked with ["good-start"](https://github.com/strimzi/strimzi-kafka-operator/labels/good-start)
label.

The [Development guide](https://github.com/strimzi/strimzi-kafka-operator/blob/main/development-docs/DEV_GUIDE.md) describes how to build Strimzi and how to
test your changes before submitting a patch or opening a PR.

The [Documentation Contributor Guide](https://strimzi.io/contributing/guide/) describes how to contribute to Strimzi documentation.

If you want to get in touch with us first before contributing, you can use:

* [Strimzi mailing list on CNCF](https://lists.cncf.io/g/cncf-strimzi-users/topics)

* [Strimzi Slack channel on CNCF workspace](https://cloud-native.slack.com/messages/strimzi)

### License

Strimzi is licensed under the [Apache License, Version 2.0](https://github.com/strimzi/strimzi-kafka-operator/blob/main/LICENSE).