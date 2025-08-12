# DMS Module (no KMS/Secrets creation)

This module provisions AWS Database Migration Service (DMS) components while **accepting** existing
KMS and Secrets Manager resources:

- DMS **replication subnet group**
- DMS **replication instance** (encrypted with your **CMK ARN** input)
- DMS **source** and **target** endpoints (auth via **Secrets Manager** or inline user/pass)
- DMS **replication task**

> The module **does not create** KMS keys or Secrets Manager secrets, nor the IAM roles to read those secrets.
> You pass in the **access role ARNs**. See the root README for detailed instructions to create them.

## Inputs (highlights)

- `replication_subnet_ids` (list) – private subnet IDs for the replication instance
- `replication_security_group_ids` (list) – SGs to attach to the instance
- `replication_instance_kms_key_arn` (string) – CMK to encrypt the instance
- Source/Target endpoint connection values plus **either**:
  - `*_secrets_manager_arn` **and** `*_secrets_manager_access_role_arn`, **or**
  - `*_username` **and** `*_password`
- `migration_type` – `full-load` | `cdc` | `full-load-and-cdc`
- `table_mappings_json` / `replication_task_settings_json`
- `ssl_mode_source/target` (default `require`)
- `tags`

## Outputs

- `replication_instance_arn`
- `replication_subnet_group_id`
- `source_endpoint_arn`
- `target_endpoint_arn`
- `replication_task_arn`
