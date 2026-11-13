# Deployment key migration

The three deployment settings move to dotted keys:

| Old key         | New key        |
|-----------------|----------------|
| region          | deploy.region  |
| replicas        | deploy.replicas |
| timeout_seconds | deploy.timeout_s |

Remove the old keys when migrating deploy-config.yaml.
