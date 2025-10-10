# RDS Data Extraction Pipeline Design Document

> **Note:** This version consolidates everything we discussed during review (Sections 1–6) with the full level of detail, and includes clearly marked placeholders for where Visio diagrams should be inserted later. No DMS components are used anywhere in this design.

---

## 1. Purpose & Scope

The purpose of this system is to establish a **secure, automated, and OPA-compliant** pipeline that exports data from **Amazon RDS** to **Amazon S3** as **CSV** on a **daily schedule**, using **IAM database authentication** (no Secrets Manager, no static passwords) and **SSE‑KMS with a customer‑managed CMK**.

This design replaces heavyweight ETL jobs with a lightweight **Lambda-based** extraction process that:
- Uses **IAM-only** for database authentication (short‑lived tokens).
- Ensures **encryption at rest** via **SSE‑KMS (CMK)** and **TLS in transit**.
- Operates entirely in **private VPC subnets** with least‑privilege IAM.
- Produces **auditable, versioned** outputs for analytics and compliance.

**Primary use cases**
- Compliance/audit data feeds (e.g., user activity extracts).
- Analytics staging for a data lake (daily partitions).
- Multi‑environment or cross‑account controlled sharing (via S3 + KMS policy).

This document specifies **architecture**, **data flow**, **security & compliance**, and **operations** for the solution.

---

## 2. Architecture Overview

*(Insert **Figure 1: High‑Level Architecture Overview** here — Visio)*

The pipeline comprises the following AWS services and relationships:

### Amazon RDS (Source Database)
- IAM Database Authentication is **enabled**.
- A **read‑only DB role/user** is granted `rds_iam` and scoped SELECT privileges to the required schemas/tables.

### AWS Lambda (Data Extraction Function)
- Python 3.11 function in **private VPC subnets**.
- Authenticates to RDS using **IAM auth tokens** (no stored secrets).
- Executes **parameterized SQL**, serializes to **CSV**, uploads to **S3** with **SSE‑KMS (CMK)**.
- Emits structured logs and custom metrics.

### Amazon S3 (Export Storage)
- **Versioning** and **TLS‑only** bucket policy enforced.
- Objects encrypted via **customer‑managed CMK**.
- Prefix strategy supports partitioned analytics and lifecycle management.

### Amazon EventBridge (Scheduler)
- **Daily cron** rule invokes Lambda.
- Optional DLQ/retry to strengthen orchestration.

### AWS KMS (Encryption)
- **Customer‑managed CMK** dedicated to export bucket.
- Key policy explicitly authorizes Lambda role and S3 service principal.

### AWS IAM (Permissions)
- **Least‑privilege** policies with explicit ARNs:
  - `rds-db:connect` bound to `<dbi-resource-id>/<db_user>`.
  - S3 actions scoped to target bucket/prefix.
  - KMS actions limited to `Encrypt` + `GenerateDataKey*` only.
- Resource‑based policies on Lambda (EventBridge invoke), S3 (writer role), and KMS (Lambda + S3 service).

**High‑level flow (summary)**
1) EventBridge triggers Lambda → 2) Lambda generates IAM DB token → 3) TLS connection to RDS → 4) Run parameterized SQL → 5) CSV to S3 (SSE‑KMS) → 6) CloudWatch & CloudTrail log/audit every step.

---

## 3. Detailed Design Components

### 3.1 AWS Lambda — Data Extraction Function
**Purpose.** Run SQL against RDS using IAM DB auth, produce CSV, write to S3 (SSE‑KMS).

**Runtime & Packaging**
- Python 3.11; dependencies: `psycopg2-binary` (or `pg8000`), `boto3`.
- Include **RDS CA bundle** (layer or package file).
- Mem: 512–1024 MB; Timeout: 5–15 min (tune to dataset size).

**Networking**
- Private subnets + NAT for AWS APIs; SG egress 443.
- RDS SG allows inbound only from Lambda SG on the DB port (e.g., 5432).

**Configuration (env)**
- `DB_HOST`, `DB_PORT`, `DB_NAME`, `DB_USER`, `REGION`
- `QUERY` (or reference SQL via SSM Param Store)
- `EXPORT_BUCKET`, `EXPORT_PREFIX`
- `SSL_CERT_PATH`

**Execution Flow**
1. `rds.generate_db_auth_token()` → obtain short‑lived token.
2. Open **TLS** connection (`sslmode=require`) with token.
3. Execute **parameterized** SQL (no string concatenation).
4. Stream rows → CSV with header; handle large outputs via `/tmp` or chunking.
5. `PutObject` to S3 with `ServerSideEncryption="aws:kms"` and `SSEKMSKeyId=<CMK>`.
6. Emit metrics: rows, duration, bytes, s3_key; write structured logs.

**Error Handling & Retries**
- Fail fast with clear error categories: **Auth**, **SQL**, **Write**.
- Use EventBridge retry policy or Step Functions wrapper if needed.
- CloudWatch Alarms on `Errors>0`, p95 duration, missed daily run.

**Performance**
- Prefer **time‑windowed** SQL (e.g., “previous day”).
- Consider read replica to offload primary; add LIMIT/OFFSET if needed.

**Security Posture**
- No Secrets Manager, no static creds.
- Lambda lacks `kms:Decrypt` (write‑only encryption).

---

### 3.2 Amazon RDS — Source Database
**IAM DB Auth & Grants (PostgreSQL example)**
```sql
CREATE ROLE dbsec WITH LOGIN;
GRANT rds_iam TO dbsec;
GRANT CONNECT ON DATABASE <db_name> TO dbsec;
GRANT USAGE ON SCHEMA public TO dbsec;
GRANT SELECT ON ALL TABLES IN SCHEMA public TO dbsec;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT SELECT ON TABLES TO dbsec;
```
**Security**
- TLS required; RDS CA validation.
- SG pin‑holing to Lambda SG only.
**Ops**
- Keep stats updated; consider replicas for heavy reads.

---

### 3.3 Amazon S3 — Export Storage
**Configuration**
- Versioning: **Enabled**.
- SSE‑KMS with **CMK**.
- Bucket policy enforces **TLS‑only** (`aws:SecureTransport=true`).

**Layout**
- `s3://<bucket>/<prefix>/dbname=<DB_NAME>/dt=<YYYYMMDD>/export_<timestamp>.csv`

**Lifecycle**
- Transition to colder tiers after N days; retain M months/years per policy.

**Access Control**
- Bucket policy allows **only** the Lambda role to `PutObject` to the export prefix.
- Readers granted separate, read‑only, prefix‑scoped permissions.

---

### 3.4 AWS KMS — Customer‑Managed CMK
**Usage**
- Dedicated CMK for S3 exports.
- Key policy:
  - **Lambda role**: `kms:Encrypt`, `kms:GenerateDataKey*` (no decrypt).
  - **S3 service principal**: allowed for this bucket only (conditions `SourceArn`, `SourceAccount`).
  - **Root admin** statement for key management.

**Audit & Rotation**
- CloudTrail logs `GenerateDataKey`/`Encrypt` usage.
- Annual rotation enabled; alias follows naming conventions.

---

### 3.5 AWS IAM — Roles & Policies
**Lambda Execution Role**
- Trust: `lambda.amazonaws.com`.
- Permissions:
  - `rds-db:connect` on `arn:aws:rds-db:<region>:<acct>:dbuser:<dbi-resource-id>/<db_user>`
  - `rds:DescribeDBInstances` (metadata)
  - `s3:PutObject`, `s3:AbortMultipartUpload`, `s3:ListBucket` on target bucket/prefix
  - `kms:Encrypt`, `kms:GenerateDataKey`, `kms:GenerateDataKeyWithoutPlaintext` on CMK
  - CloudWatch logs write

**S3 Bucket Policy**
- Deny non‑TLS; allow Lambda role write to specific prefix only.

**KMS Key Policy**
- Allow **Lambda role** and **S3 service** (bucket‑scoped) to use the key.
- Root admin statement retained.

**EventBridge → Lambda**
- Resource policy on Lambda allows invoke from the specific rule ARN.

*(Authoritative JSON artifacts were delivered separately; see “Appendix A: Policy Artifacts”.)*

---

### 3.6 Amazon EventBridge — Scheduling
- Cron rule (e.g., `cron(0 05 * * ? *)` UTC daily).
- Optional DLQ and retry policy.
- Parameterize schedule per environment.

---

### 3.7 Observability & Operations
**Logging**
- Structured JSON logs (request_id, rows, duration, s3_key, status).
- Retention ≥ 400 days; encrypted at rest.

**Metrics**
- Standard: Invocations, Errors, Duration.
- Custom: `RowsExported`, `QueryDurationMs`, `CsvSizeBytes`, `S3PutLatencyMs`.

**Dashboards**
- Combined Lambda/S3/EventBridge dashboard per environment.

**Alarms**
- ErrorRate > 0, execution p95 above threshold, “no success in 24h”.

---

### 3.8 Data Model & SQL Strategy
- Parameterized SQL; daily time window filters.
- Prefer **views** to insulate from schema drift.
- Normalize timestamps to UTC ISO‑8601; fixed column ordering.

---

### 3.9 Scalability & Limits
- For large outputs, chunk by date or ID ranges; stream to `/tmp` if needed.
- Consider read replicas to mitigate primary load.
- KMS API cost negligible at daily cadence; S3 lifecycle controls storage cost.

---

### 3.10 Security & Compliance Mapping (OPA)
| Control Area | Decision | Compliance Note |
|---|---|---|
| Credentials | IAM DB Auth only | Removes secrets & rotation burden |
| Encryption at Rest | SSE‑KMS (CMK) | CM-6 / SC‑28 alignment |
| Encryption in Transit | TLS everywhere | S3 TLS‑only bucket policy |
| IAM Least Privilege | Resource‑scoped ARNs | No wildcards, no PassRole |
| Network Isolation | Private subnets, SG pin‑holing | No public endpoints |
| Auditability | CloudTrail + CloudWatch | Evidence for audits |

---

## 4. Data Flow Description

*(Insert **Figure 2: Data Flow Sequence** here — Visio)*

**4.1 Trigger and Invocation**
- EventBridge daily cron invokes Lambda via resource‑based policy scoping the rule ARN.

**4.2 Lambda Initialization**
- Runs in private VPC; assumes execution role; uses VPC endpoints (S3, KMS) to keep traffic on AWS backplane.

**4.3 Database Connection & Extraction**
- Lambda obtains IAM DB token; establishes TLS connection with RDS CA validation.
- Executes parameterized SQL; streams results; serializes to CSV with header row.

**4.4 Encryption & Upload**
- Lambda calls S3 `PutObject` with `SSE-KMS` and CMK ARN.
- S3 interacts with KMS (`GenerateDataKey`, `Encrypt`); CloudTrail logs key usage.
- Bucket policy enforces TLS and prefix‑scoped writes.

**4.5 Logging & Metrics**
- Lambda logs structured events; emits custom metrics.
- Errors and anomalies trigger CloudWatch Alarms.

**4.6 Post‑Execution**
- Data immediately available for downstream read‑only consumers.
- Lifecycle and versioning ensure retention and recovery.

---

## 5. Security & Compliance Design

*(Insert **Figure 3: Security & Trust Boundaries** here — Visio)*

### 5.1 Identity & Access Management
- **Least privilege** everywhere; explicit ARNs; no wildcards beyond `Describe*` where necessary.
- Lambda trust limited to `lambda.amazonaws.com`; EventBridge invoke scoped by rule ARN.
- No cross‑account assumptions in this version (add `SourceAccount`/`SourceArn` conditions if introduced later).

### 5.2 Encryption & Key Management
- **SSE‑KMS (CMK)** for all S3 objects.
- Lambda IAM policy: `kms:Encrypt`, `kms:GenerateDataKey*` only; **no decrypt**.
- KMS key policy authorizes Lambda role + S3 service principal restricted to bucket.
- Annual rotation; CloudTrail for all KMS API calls.

### 5.3 Network Security & Isolation
- Private subnets; VPC endpoints for S3/KMS; SG pin‑holing to RDS port.
- No public IPs on Lambda or RDS; NAT egress for AWS APIs only.

### 5.4 Data Integrity & Auditing
- CloudTrail enabled across services; logs centralized per policy.
- S3 versioning; optional replication to logging account for immutability.

### 5.5 Operational Security & Resilience
- EventBridge retry; optional DLQ; idempotent object keys.
- Runbooks for **Auth**, **SQL**, **S3/KMS** failures; alarms route via SNS.

### 5.6 Compliance Alignment Summary
| Category | Implementation | Reference |
|---|---|---|
| Credential Mgmt | IAM DB auth; no Secrets Manager | OPA `IAM-4` |
| At‑Rest Encryption | SSE‑KMS (CMK) | OPA `KMS-3`, `S3-10` |
| In‑Transit Encryption | TLS enforced | OPA `NET-TLS-1` |
| Least Privilege | Scoped ARNs | OPA `IAM-1` |
| Audit Logging | CloudTrail + CW Logs | OPA `LOG-1` |
| Network Isolation | Private VPC + endpoints | OPA `NET-2` |

### 5.7 Security Assurances
- No plaintext credentials anywhere.
- CMK‑encrypted data with explicit principals only.
- TLS‑only transport enforced by policy.
- Full traceability via CloudWatch/CloudTrail.

---

## 6. Operations & Monitoring

*(Insert **Figure 4: Operations & Monitoring Topology** here — Visio)*

### 6.1 Monitoring & Observability
- **Metrics**: Invocations, Errors, Duration, Throttles; custom `RowsExported`, `QueryDurationMs`, `CsvSizeBytes`, `S3PutLatencyMs`.
- **Dashboards**: environment‑scoped summaries over last 7 days.
- **Logs**: structured JSON, retained ≥ 400 days.

### 6.2 Alerting & Alarms
- Error > 0 in 15 min; p95 duration threshold; missed daily success.
- S3 failures or AccessDenied via metric filters.
- KMS AccessDenied surfaced from CloudTrail.

### 6.3 Operational Runbooks
| Category | Symptom | Resolution |
|---|---|---|
| Auth | `rds-db:connect` denied | Verify `rds_iam`, role ARN mapping, SGs |
| S3 Access | `PutObject` AccessDenied | Check bucket policy + CMK statements |
| SQL | Syntax/schema errors | Update SQL or stabilize with a view |
| KMS | AccessDenied in CloudTrail | Validate key policy for Lambda + S3 |
| Perf | Duration ↑ or row count ↓ | Analyze RDS metrics; optimize query; reschedule |

### 6.4 Deployment & Change Mgmt
- Terraform IaC; PR review; OPA policy gating before apply.
- Dev → Stg → Prod promotion with approval gates.

### 6.5 Governance & Continuous Compliance
- AWS Config rules: `s3-bucket-server-side-encryption-enabled`, `lambda-inside-vpc`, `kms-key-rotation-enabled`, `eventbridge-rule-enabled`.
- Quarterly access and policy reviews; annual DR exercise.

### 6.6 Operational Metrics Summary
| Metric | Source | Target | Purpose |
|---|---|---|
| RowsExported | Lambda | > 0 daily | Confirms extraction |
| LambdaErrorRate | CloudWatch | = 0 | Execution health |
| S3PutLatencyMs | Custom | < 500 ms | Detect S3 issues |
| KMSAccessDenied | CloudTrail | = 0 | Policy integrity |
| MissedInvocations | EventBridge | = 0 | Schedule integrity |

### 6.7 Business Continuity & DR
- RDS automated backups; S3 versioning; optional cross‑region replication.
- **RTO** < 1 hour (IaC redeploy); **RPO** ≤ 24 hours (daily cadence).

### 6.8 Review Cadence
- Daily dashboards; weekly S3/KMS checks; monthly CloudTrail audits; quarterly OPA reviews.

---

## Appendix A: Policy Artifacts (Reference)
Authoritative JSON policies (Lambda trust/core, S3 bucket policy, KMS key policy, EventBridge invoke) were delivered separately as downloadable files. Use those artifacts as the source of truth for IAM/KMS enforcement in this design.


---



## 7. Testing & Validation

This section defines the verification strategy for the RDS Data Extraction Pipeline prior to production release and as part of continuous compliance operations.

### 7.1 Pre-Deployment Validation
Before each environment deployment (dev/stg/prod), automated checks validate:
- **Terraform plan compliance** — OPA policy bundle executed to confirm no violations:
  - `S3_BUCKET_ENCRYPTION_ENABLED`
  - `LAMBDA_INSIDE_VPC`
  - `KMS_KEY_ROTATION_ENABLED`
  - `IAM_ROLE_LEAST_PRIVILEGE`
- **Resource identity consistency** — KMS alias, S3 bucket name, and IAM role ARNs validated against naming regex rules (`^[a-z0-9-]{3,50}$`).
- **Parameter integrity** — required variables (`prefix_name`, `kms_key_arn`, `export_bucket`) verified non-null.

### 7.2 Functional Testing
Functional tests confirm the pipeline performs as designed:
1. **Lambda Execution Test**
   - Invoke manually with sample query (`SELECT 1;`) to confirm connectivity and IAM authentication.
   - Expected: CSV with single record in S3.
2. **S3 Output Verification**
   - Confirm object key follows naming convention:
     `s3://<bucket>/<prefix>/dbname=<DB_NAME>/dt=<YYYYMMDD>/export_<timestamp>.csv`
   - Verify object metadata includes `ServerSideEncryption=aws:kms` and correct `SSEKMSKeyId`.
3. **Encryption Validation**
   - Use AWS CLI to run `aws s3api head-object` and confirm CMK ARN matches expected key ID.
   - Review CloudTrail for `kms:GenerateDataKey*` events matching Lambda principal.
4. **Data Integrity Check**
   - Download sample export and confirm schema, row count, and date range match query parameters.

### 7.3 Security Validation
Security validation ensures IAM and KMS enforcement is effective:
- Attempt cross-account or unauthorized role upload → expect `AccessDenied`.
- Attempt non-TLS S3 request → expect bucket policy denial (`SecureTransport`).
- Verify Lambda role **cannot decrypt** KMS objects (no `kms:Decrypt`).
- Confirm RDS enforces IAM token auth (no static credentials accepted).

### 7.4 Observability Validation
Operational observability validated via:
- CloudWatch Alarms trigger upon simulated failure (forced query error).
- Custom metrics (`RowsExported`, `CsvSizeBytes`) appear within 1 min of execution.
- Log retention and encryption verified via `aws logs describe-log-groups`.

### 7.5 Post-Deployment Audit
- CloudTrail event trace from EventBridge → Lambda → RDS → S3 → KMS reviewed.
- IAM Access Analyzer run to detect unintended cross-service access.
- KMS and S3 Config rules confirmed **compliant = true**.

### 7.6 Ongoing Validation
- Quarterly re-validation of all IAM and KMS policies via automated compliance jobs.
- Annual penetration test simulating credential misuse and data exfiltration scenarios.
- Continuous integration jobs re-run OPA policy checks on every infrastructure commit.

---

## Appendix B: IAM, S3, and KMS Policy JSON Artifacts

### 1. Lambda Trust Policy
```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Service": "lambda.amazonaws.com"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
```

### 2. Lambda Core Policy
```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "AllowRdsDbConnect",
      "Effect": "Allow",
      "Action": ["rds-db:connect"],
      "Resource": ["arn:aws:rds-db:<REGION>:<ACCOUNT_ID>:dbuser:<RDS_RESOURCE_ID>/<DB_USER>"]
    },
    {
      "Sid": "DescribeRdsInstances",
      "Effect": "Allow",
      "Action": ["rds:DescribeDBInstances"],
      "Resource": "*"
    },
    {
      "Sid": "S3CsvExportAccess",
      "Effect": "Allow",
      "Action": ["s3:PutObject", "s3:AbortMultipartUpload", "s3:ListBucket"],
      "Resource": [
        "arn:aws:s3:::<EXPORT_BUCKET>",
        "arn:aws:s3:::<EXPORT_BUCKET>/<PREFIX>/*"
      ]
    },
    {
      "Sid": "KmsEncryptForS3",
      "Effect": "Allow",
      "Action": [
        "kms:Encrypt",
        "kms:GenerateDataKey",
        "kms:GenerateDataKeyWithoutPlaintext"
      ],
      "Resource": ["arn:aws:kms:<REGION>:<ACCOUNT_ID>:key/<KMS_KEY_ID>"]
    },
    {
      "Sid": "CloudWatchLogs",
      "Effect": "Allow",
      "Action": [
        "logs:CreateLogGroup",
        "logs:CreateLogStream",
        "logs:PutLogEvents"
      ],
      "Resource": "*"
    }
  ]
}
```

### 3. KMS Key Policy
```json
{
  "Version": "2012-10-17",
  "Id": "key-policy-rds-export",
  "Statement": [
    {
      "Sid": "EnableRootAccess",
      "Effect": "Allow",
      "Principal": {
        "AWS": "arn:aws:iam::<ACCOUNT_ID>:root"
      },
      "Action": "kms:*",
      "Resource": "*"
    },
    {
      "Sid": "AllowLambdaEncrypt",
      "Effect": "Allow",
      "Principal": {
        "AWS": "arn:aws:iam::<ACCOUNT_ID>:role/lambda-rds-export-role"
      },
      "Action": [
        "kms:Encrypt",
        "kms:GenerateDataKey",
        "kms:GenerateDataKeyWithoutPlaintext"
      ],
      "Resource": "*"
    },
    {
      "Sid": "AllowS3UseOfKey",
      "Effect": "Allow",
      "Principal": {
        "Service": "s3.amazonaws.com"
      },
      "Action": [
        "kms:Encrypt",
        "kms:Decrypt",
        "kms:ReEncrypt*",
        "kms:GenerateDataKey*",
        "kms:DescribeKey"
      ],
      "Resource": "*",
      "Condition": {
        "StringEquals": {"aws:SourceAccount": "<ACCOUNT_ID>"},
        "ArnLike": {"aws:SourceArn": "arn:aws:s3:::<EXPORT_BUCKET>"}
      }
    }
  ]
}
```

### 4. S3 Bucket Policy
```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "DenyInsecureTransport",
      "Effect": "Deny",
      "Principal": "*",
      "Action": "s3:*",
      "Resource": [
        "arn:aws:s3:::<EXPORT_BUCKET>",
        "arn:aws:s3:::<EXPORT_BUCKET>/*"
      ],
      "Condition": {
        "Bool": {"aws:SecureTransport": "false"}
      }
    },
    {
      "Sid": "AllowLambdaPutCsv",
      "Effect": "Allow",
      "Principal": {
        "AWS": "arn:aws:iam::<ACCOUNT_ID>:role/lambda-rds-export-role"
      },
      "Action": ["s3:PutObject", "s3:AbortMultipartUpload", "s3:ListBucket"],
      "Resource": [
        "arn:aws:s3:::<EXPORT_BUCKET>",
        "arn:aws:s3:::<EXPORT_BUCKET>/<PREFIX>/*"
      ]
    }
  ]
}
```

### 5. EventBridge Invoke Permission
```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "AllowEventBridgeInvoke",
      "Effect": "Allow",
      "Principal": {"Service": "events.amazonaws.com"},
      "Action": "lambda:InvokeFunction",
      "Resource": "arn:aws:lambda:<REGION>:<ACCOUNT_ID>:function:<LAMBDA_FUNCTION_NAME>",
      "Condition": {
        "ArnLike": {
          "AWS:SourceArn": "arn:aws:events:<REGION>:<ACCOUNT_ID>:rule/<RULE_NAME>"
        }
      }
    }
  ]
}
```
