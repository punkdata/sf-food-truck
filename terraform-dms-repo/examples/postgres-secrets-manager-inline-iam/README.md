# Example: Postgres → Postgres with inline IAM roles

This example shows how to wire the **DMS module** and, in the **same stack**, create the
two IAM roles DMS needs to read credentials from **Secrets Manager** for the **source** and **target** endpoints.

## What you need **before** applying

1. **Network**: private subnets + SGs that allow the DMS instance to reach both DBs.
2. **CMK**: a customer-managed KMS key ARN for the replication instance.
3. **Secrets**: two Secrets Manager secrets containing JSON:
   ```json
   {"username": "dbuser", "password": "SuperS3cret!"}
   ```
   Each secret must be encrypted with a **CMK** (not `aws/secretsmanager`).

## What the example creates

- Two IAM roles:
  - `${name_prefix}-source-secret-access`
  - `${name_prefix}-target-secret-access`
  Each trusted by `dms.amazonaws.com`, and each scoped to exactly one secret ARN and its CMK ARN.
- A DMS replication instance, source and target endpoints, and a replication task (full-load).

## Why two roles?

DMS requires an **access role ARN per endpoint** when you use Secrets Manager for credentials.
Each role must allow:
- `secretsmanager:GetSecretValue` on the **one** secret
- `kms:Decrypt` (and `kms:DescribeKey`) on the CMK that encrypts that secret

The example also adds a **`kms:ViaService`** condition to tighten decryption use to Secrets Manager.

## Cross-account notes

Keep the **secrets and the access roles in the same account** where the secrets live. Pass those role ARNs to the DMS endpoint in the account where DMS runs. If you truly need cross-account secrets, follow AWS guidance for cross-account Secrets Manager access; you may need a resource policy on the secret and adjusted trust—beyond the scope of this example.

## Apply

Provide variables (via `terraform.tfvars`, CLI, or environment):

```hcl
replication_subnet_ids          = ["subnet-aaa","subnet-bbb"]
replication_security_group_ids  = ["sg-12345678"]
replication_instance_kms_key_arn= "arn:aws:kms:us-east-1:111122223333:key/abcd-..."

source_server_name     = "src-db.cluster-xxxx.us-east-1.rds.amazonaws.com"
source_database_name   = "sourcedb"
source_secret_arn      = "arn:aws:secretsmanager:us-east-1:111122223333:secret:src-cred-abc"
source_secret_kms_arn  = "arn:aws:kms:us-east-1:111122223333:key/src-cmk-..."

target_server_name     = "tgt-db.cluster-yyyy.us-east-1.rds.amazonaws.com"
target_database_name   = "targetdb"
target_secret_arn      = "arn:aws:secretsmanager:us-east-1:111122223333:secret:tgt-cred-xyz"
target_secret_kms_arn  = "arn:aws:kms:us-east-1:111122223333:key/tgt-cmk-..."
```

Then:
```bash
terraform init
terraform apply
```

## OPA / Least-Privilege Checklist

- Secrets use **CMKs** (not the AWS-managed key).  
- IAM inline policies scope to **exact secret ARNs** and **exact CMK ARNs**.  
- Optional `kms:ViaService` limits decrypt usage via Secrets Manager in your region.  
- DMS instance uses your **CMK ARN** via `replication_instance_kms_key_arn`.  
- TLS settings `ssl_mode_source/target` default to `require`.  
