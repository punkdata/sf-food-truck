
# Epic: Automated CSDB/RODB Feeds via AWS Lambda & Step Function Orchestration

---

## Epic Summary

Design and prototype an automated, OPA-compliant mechanism for exporting PostgreSQL user activity data from RDS instances across multiple AWS accounts and environments (dev, stg, prod) to a centralized S3 bucket using IAM authentication, Step Functions, and EventBridge scheduling.

**Goal:**  
Implement a secure, scalable, and auditable system for daily PostgreSQL data extraction using short-lived IAM credentials instead of static secrets.

---

## Story 1: Define Solution Architecture & Requirements

**Description:**  
Develop and document the high-level and detailed architecture for the CSDB/RODB automated data export system, covering all components and data flow.

**Acceptance Criteria:**  
- Given the need to automate RDS data exports,  
- When reviewing the architecture,  
- Then it must clearly define AWS services, interactions, IAM relationships, and data flow between RDS, Lambda, and S3.

**Deliverables:**  
- Architecture overview and diagrams (component + workflow)  
- Step Function state machine outline  
- Component responsibility matrix  
- AWS service inventory (Lambda, Step Functions, S3, KMS, IAM)

---

## Story 2: IAM Role Design for IAM-Based RDS Authentication

**Description:**  
Design and implement IAM roles and policies that enable Lambda functions to securely authenticate to RDS PostgreSQL using IAM database authentication and STS tokens — eliminating Secrets Manager dependency.

**Acceptance Criteria:**  
- Given each Lambda operates in its own AWS account,  
- When IAM roles are deployed,  
- Then they must:
  - Use IAM-based database authentication (rds-db:connect).  
  - Assume cross-account roles for centralized orchestration.  
  - Follow OPA least-privilege and resource-scoped policy design.

**Tasks:**  
- Define centralized execution role (csdb-data-export-role) in shared services or security account.  
- Grant least-privilege permissions:  
  - rds-db:connect (scoped to PostgreSQL instance ARNs)  
  - kms:Decrypt, kms:DescribeKey for encryption/decryption  
  - s3:PutObject (restricted to export prefixes)  
  - config:Get*, config:List* for AWS Config access  
- Create per-environment Lambda roles (dev/stg/prod) with sts:AssumeRole permissions.  
- Validate all IAM policies pass OPA compliance scans.  
- Configure cross-account trust policies for centralized control.

---

## Story 3: Implement Step Function Orchestration

**Description:**  
Develop an AWS Step Function that coordinates Lambda executions in sequence or parallel to extract RDS data and upload it to S3.

**Acceptance Criteria:**  
- Given a scheduled EventBridge trigger,  
- When the Step Function executes,  
- Then it must:
  - Orchestrate Lambda invocations in the correct order.  
  - Retry failed Lambdas up to 3 times with exponential backoff.  
  - Log state transitions to CloudWatch.

**Tasks:**  
- Create the Step Function state machine in Terraform or JSON.  
- Define state transitions and retry logic.  
- Add failure handling and alerts via CloudWatch and SNS.  
- Parameterize Lambda ARNs and environment mappings.

---

## Story 4: Develop Lambda Functions for Data Extraction and Export

**Description:**  
Build Lambda functions to authenticate with RDS via IAM tokens, run parameterized SQL queries, and export results as encrypted CSV files to S3.

**Acceptance Criteria:**  
- Given Lambda functions are deployed for dev, stg, and prod environments,  
- When executed,  
- Then they must:
  - Assume IAM execution roles to generate RDS auth tokens.  
  - Establish encrypted connections to RDS instances (SSL/TLS).  
  - Execute pre-defined queries against user activity tables.  
  - Export results to S3 with date-stamped filenames.

**Tasks:**  
- Implement AWS SDK call generate_db_auth_token for RDS login.  
- Implement database query and CSV export logic.  
- Configure VPC networking and Transit Gateway routing for RDS access.  
- Validate execution timeout and retry configuration.

---

## Story 5: Configure Centralized S3 Storage and KMS Encryption

**Description:**  
Provision a centralized S3 bucket for exporting CSV data from all environments, encrypted with KMS and locked down with least-privilege access.

**Acceptance Criteria:**  
- Given S3 bucket resources are created,  
- When CSV data is uploaded,  
- Then it must:
  - Be encrypted using KMS (SSE-KMS).  
  - Follow a folder structure: /env/[db_name]/csdb_YYYYMMDD.csv.  
  - Allow write access only to the Lambda roles.

**Tasks:**  
- Create S3 bucket with versioning and logging enabled.  
- Define KMS key policy allowing Lambda encryption/decryption.  
- Implement S3 bucket policy that denies non-SSL and public access.  
- Validate OPA rules (S3-2, S3-9, S3-11 compliance).

---

## Story 6: Monitoring, Logging, and Alerting

**Description:**  
Implement centralized observability and alerting for all Lambda and Step Function executions.

**Acceptance Criteria:**  
- Given monitoring is configured,  
- When tasks fail or metrics deviate,  
- Then alerts are sent to the DevOps team and logs are available for audit.

**Tasks:**  
- Enable CloudWatch log groups for all Lambdas.  
- Create CloudWatch metrics:  
  - Execution duration  
  - Rows exported  
  - S3 upload success/failure  
- Set up CloudWatch Alarms and SNS notifications.  
- (Optional) Export metrics to Grafana dashboards.

---

## Story 7: Testing & Validation Framework

**Description:**  
Establish automated unit and integration testing for IAM-authenticated Lambda functions and RDS data exports.

**Acceptance Criteria:**  
- Given a test environment is available,  
- When validation tests are executed,  
- Then:
  - RDS connections authenticate successfully via IAM token.  
  - Exported CSVs match source query results.  
  - IAM role access is strictly scoped and auditable.

**Tasks:**  
- Implement mock RDS for Lambda connection testing.  
- Validate rds-db:connect permissions across environments.  
- Verify row count equality between RDS and exported CSV.  
- Conduct negative IAM tests (access denied scenarios).

---

## Story 8: Documentation & Handoff

**Description:**  
Deliver finalized documentation and handoff materials to DevOps and platform engineering teams for continued maintenance.

**Acceptance Criteria:**  
- Given development is complete,  
- When documentation is reviewed,  
- Then it must clearly explain:  
  - Deployment process via Terraform/IaC.  
  - IAM authentication logic and trust configuration.  
  - Step Function orchestration flow.  
  - Monitoring and recovery procedures.

**Deliverables:**  
- Markdown/Confluence document (Architecture + Operations)  
- Terraform baseline for IAM, Lambda, and Step Functions  
- DevOps runbook and recovery checklist

---

## Story 9: EventBridge Scheduling & Automation

**Description:**  
Configure AWS EventBridge to automatically trigger the Step Function daily for continuous RDS data exports.

**Acceptance Criteria:**  
- Given EventBridge rules are deployed,  
- When the daily trigger executes,  
- Then the Step Function runs the complete data export pipeline.

**Tasks:**  
- Define daily schedule (e.g., 00:00 UTC).  
- Configure rule target to Step Function ARN.  
- Test and validate end-to-end workflow.  
- Ensure concurrency and error-handling configurations are documented.

---

