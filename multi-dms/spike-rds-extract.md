# SPIKE: RDS Postgres User Activity Capture

## Executive Summary
This spike investigates how to automatically capture **user access activity** from all AWS RDS PostgreSQL instances across multiple accounts and organizations, and deliver the data into a central location for compliance and reporting. The goal is to eliminate manual collection, ensure consistency, and meet audit requirements by providing management with clear visibility into who accessed which database roles and when.  

The proposed approach uses a **hub-and-spoke design**. In each AWS account, a scheduled Lambda function will securely connect to RDS databases (preferably using **IAM database authentication** for short-lived tokens, with Secrets Manager as a fallback), extract user activity, and export results into **date-stamped CSV files**. These files will be stored in a **central S3 bucket** with strict encryption and least-privilege access controls, where downstream analytics can process them.  

This design aligns with organizational security policies, emphasizes **OPA compliance and least privilege IAM**, and scales across multiple accounts. It provides a repeatable, automated mechanism to capture access data daily, enabling reliable compliance reporting and improved visibility for stakeholders.

---

## Key Takeaways
- **Business Goal:** Centralize RDS Postgres access activity for compliance, visibility, and reporting.  
- **Scope:** Daily extraction of user activity (`user_id`, `login_time`, `activity_type`) from all RDS Postgres instances across accounts/orgs.  
- **Architecture:** Hub-and-spoke model — EventBridge → Lambda (per account) → RDS → S3 (central).  
- **Preferred Authentication:** IAM DB authentication (short-lived tokens). Secrets Manager is fallback only.  
- **Security:** TLS enforced, SSE-KMS encryption, least-privilege IAM, OPA-compliant by design.  
- **Output:** Date-stamped CSV files in central S3 bucket, structured for downstream reporting.  
- **Future Extensions:** Alerting, auto-discovery of DBs, Lifecycle policies for archival.  

---

## Business Context
### Problem
The organization lacks centralized visibility into **user and role-based access permissions** and **last-access activity** across all AWS RDS PostgreSQL instances. Without this, compliance monitoring, stale-role detection, and management reporting are manual and error-prone.  

### Goals & Objectives
- **Compliance** – Capture and centralize user activity for audit.  
- **Visibility** – Provide management accurate daily insights into DB access.  
- **Automation** – Eliminate manual SQL queries or log scraping.  
- **Enterprise Coverage** – Cover **all RDS PostgreSQL instances** across **multiple AWS accounts** and **AWS Organizations**.  

### Success Criteria
- Daily **CSV exports** from every RDS Postgres instance.  
- Captured fields: `user_id`, `login_time`, `activity_type`.  
- Files date-stamped and uploaded to central **S3 bucket with SSE-KMS**.  
- IAM least-privilege enforced across hub and spoke accounts.  
- System extensible to new accounts/instances with minimal rework.  

---

## Functional Requirements
### Must-Haves
1. Connect securely (TLS) to each RDS Postgres instance.  
2. Query `UserActivityLog` for: `user_id`, `login_time`, `activity_type`.  
3. Export query results to CSV with stable schema.  
4. Filename format: `user_activity_YYYY-MM-DD.csv`.  
5. Upload to central S3 bucket with prefix:  
   ```
   s3://<bucket>/<org>/<account>/<region>/<db-id>/<YYYY>/<MM>/<DD>/user_activity_<date>.csv
   ```
6. Encrypt data at rest (SSE-KMS) and in transit (TLS).  
7. Use IAM least-privilege roles per account.  
8. Run automatically once per day via EventBridge schedule.  
9. Write logs to CloudWatch with 90-day retention.  

### Should-Haves
- Normalize schema across DBs (consistent headers).  
- Consolidate exports in central S3.  
- Retry logic with exponential backoff.  
- Structured error logs (account, db, timestamp, failure reason).  

### Nice-to-Haves
- Multi-Org federation coverage.  
- Alerting (CloudWatch Alarms + SNS).  
- Auto-discovery of tagged RDS instances.  
- Lifecycle policies for archival.  

---

## High-Level Design
### Architecture Pattern
- **Spoke Accounts:**  
  EventBridge Scheduler → Lambda Collector (VPC) → RDS PostgreSQL.  
  Lambda retrieves credentials via **IAM DB Auth (preferred)** or **Secrets Manager (fallback)**.  
  CSV exported to central S3 bucket.  

- **Hub Account:**  
  Central S3 bucket (SSE-KMS, TLS-only).  
  KMS key scoped: spoke roles encrypt only, hub roles decrypt.  

### Data Flow
1. EventBridge triggers Lambda daily.  
2. Lambda authenticates via IAM token (or Secrets fallback).  
3. Lambda queries Postgres activity logs.  
4. Lambda generates date-stamped CSV.  
5. Lambda writes CSV to S3 with KMS encryption.  
6. Downstream analytics ingest files.  

### CSV Contract
```
user_id,login_time,activity_type,account_id,region,db_identifier
```
- `login_time` in UTC ISO-8601.  
- Context fields enable aggregation across accounts.  

---

## Decision Matrix: IAM Auth vs Secrets Manager
| Aspect              | **IAM DB Authentication (Preferred)** | **Secrets Manager (Fallback)** |
|---------------------|----------------------------------------|--------------------------------|
| Security            | Short-lived tokens (15 min). No static creds. | Static creds, must rotate. |
| Compliance          | Strongest OPA alignment. | Still compliant but more overhead. |
| Complexity          | Needs DB role setup (`GRANT rds_iam`). | Simple initial setup. |
| Ops Overhead        | None (tokens auto-expire). | Rotation policies required. |
| Multi-Account Scale | Clean trust model. | Secrets per account/region. |
| Best Use Case       | Standardized new deployments. | Legacy DBs without IAM auth. |

**Recommendation:** Use IAM DB Authentication wherever possible. Use Secrets Manager only as fallback.  

---

## Required AWS Services
- **AWS RDS PostgreSQL** (source DB).  
- **AWS IAM** (roles, trust policies, least-privilege).  
- **AWS Lambda** (collector function, Python).  
- **Amazon EventBridge** (scheduler).  
- **Amazon S3** (central CSV storage).  
- **AWS KMS (CMKs)** (encryption).  
- **AWS Secrets Manager** (fallback for creds).  
- **Amazon CloudWatch Logs** (logging, retention).  
- **AWS Organizations** (multi-account federation).  

---

## Risks & Assumptions
- IAM DB Auth not enabled on all instances.  
- Schema differences may exist across databases.  
- Cross-org IAM trust adds complexity.  
- Lambda must run in correct VPC subnets for RDS access.  
- Token validity window (15 min) must be managed.  

---

## Open Questions
- Should CSV schema be strict vs. flexible?  
- Who owns the central S3 bucket (shared vs BU)?  
- Should exports be per-DB or aggregated?  
- Data retention policy in S3?  

---

## Acceptance Criteria (BDD Style)
- **Given** an RDS PostgreSQL instance with IAM DB authentication enabled,  
  **When** the Lambda runs on schedule,  
  **Then** it generates a CSV with `user_id, login_time, activity_type` and uploads it to the central S3 bucket with SSE-KMS.  

- **Given** an RDS instance without IAM DB auth,  
  **When** the Lambda runs,  
  **Then** it retrieves credentials from Secrets Manager and successfully exports the CSV.  

- **Given** multiple spoke accounts configured,  
  **When** the scheduled Lambda runs in each account,  
  **Then** all accounts deliver daily exports into the central S3 bucket under their prefix paths.  

- **Given** a job runs,  
  **When** it completes successfully or fails,  
  **Then** CloudWatch logs contain status, record count, and error details (if any).  

- **Given** the S3 bucket has SSE-KMS enforced and TLS-only policy,  
  **When** a spoke Lambda attempts to upload,  
  **Then** the file is stored encrypted and access is denied if TLS is not used.  

---

## Deployment Strategy: AFT vs Per-Account

### Option 1: Per-Account Deployment
- **Description:** Each account team deploys the RDS activity capture module individually.  
- **Pros:**  
  - Autonomy for account owners.  
  - Can customize settings per account (different DBs, retention, tags).  
- **Cons:**  
  - Risk of inconsistency in IAM/KMS/logging configuration.  
  - Duplication of Terraform code across accounts.  
  - Upgrades and bugfixes must be rolled out separately in each account.  

### Option 2: Centralized Deployment via AWS Control Tower AFT
- **Description:** Integrate the solution into the **Account Factory for Terraform (AFT)** baseline so it is automatically deployed into every new/existing account as part of account provisioning.  
- **Pros:**  
  - **Central governance** – ensures all accounts have the solution enabled by default.  
  - **Consistency** – IAM policies, S3 bucket access, KMS usage enforced uniformly.  
  - **Scalability** – automatically included in new accounts without manual setup.  
  - **Compliance** – OPA guardrails and least-privilege roles are consistently applied across the org.  
- **Cons:**  
  - Less flexibility for one-off account customizations (though AFT supports overrides via account customizations).  
  - Requires AFT/Control Tower adoption and some upfront baseline work.  

### Recommendation
Use **AFT-based deployment** as the default strategy for this project.  
- This ensures the solution is automatically part of every account baseline.  
- Central services (S3, KMS) remain in a **shared services account**.  
- Each spoke account only needs to run its local Lambda + EventBridge, deployed automatically through AFT.  

This approach provides the strongest alignment with **OPA compliance, least privilege, and enterprise scalability**.  

---

## Next Steps
1. **Prototype in Dev Account** – Deploy Lambda + EventBridge + S3 + KMS in a development account to validate end-to-end flow.  
2. **Validate IAM Auth** – Confirm IAM DB Authentication works against a test RDS PostgreSQL instance, fallback to Secrets Manager if disabled.  
3. **S3/KMS Hardening** – Apply TLS-only bucket policy and scoped KMS key policies.  
4. **Cross-Account Test** – Validate spoke → hub data flow using IAM role assumption.  
5. **Document Findings** – Update design based on POC results (timings, IAM adjustments, logging).  
6. **AFT Integration Plan** – Define how to embed the solution into the AFT baseline for organization-wide rollout.  

---