# AWS DMS Terraform Module + Inline IAM Example

This repo provides:
- `modules/dms`: a clean, reusable DMS module that accepts **CMK ARN** and **Secrets Manager ARNs + role ARNs**.
- `examples/postgres-secrets-manager-inline-iam`: an example that **creates the required IAM roles** and calls the module.

## Why no IAM in the module?
You asked to keep the module focused and pass ARNs in. This keeps cross-account and security ownership explicit.
The example shows exactly how to create the roles you need, with least-privilege, and how to pass them in.

## Creating the required IAM roles (detailed)

1. **Decide the secrets and their CMKs** for **source** and **target** endpoints.
   - Secret value JSON must include `username` and `password`.
   - Each secret should be CMK-encrypted (OPA-friendly).

2. **Create one IAM role per endpoint** with this **trust policy**:
   ```json
   {
     "Version": "2012-10-17",
     "Statement": [{
       "Effect": "Allow",
       "Principal": { "Service": "dms.amazonaws.com" },
       "Action": "sts:AssumeRole"
     }]
   }
   ```

3. **Attach a least-privilege policy** to each role that allows reading **exactly one secret** and decrypting **its CMK**:
   - `secretsmanager:GetSecretValue`, `secretsmanager:DescribeSecret` on the secret ARN
   - `kms:Decrypt`, `kms:DescribeKey` on the CMK ARN
   - Optional defense-in-depth:
     ```json
     "Condition": {
       "ForAnyValue:StringEquals": {
         "kms:ViaService": "secretsmanager.<region>.amazonaws.com"
       }
     }
     ```
   This binds decryption to calls coming from Secrets Manager in your region.

4. **Pass the role ARNs** into the module as:
   - `source_secrets_manager_access_role_arn`
   - `target_secrets_manager_access_role_arn`

5. Ensure **network** paths (subnets/SGs) allow the DMS instance to reach both DBs on their ports.

## Example
See `examples/postgres-secrets-manager-inline-iam/` to copy/paste a working setup.

## OPA / Security
- No wildcards on resource ARNs for secrets/CMKs.
- DMS instance is encrypted with your CMK (`replication_instance_kms_key_arn`).
- TLS is on by default (`ssl_mode_source/target = "require"`).

