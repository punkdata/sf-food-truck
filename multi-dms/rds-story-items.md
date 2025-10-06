# Epic: Automated CSDB/RODB Feeds via AWS Lambda & Step Function Orchestration

---

## Epic Summary

Design and prototype an automated mechanism for exporting PostgreSQL user activity data from RDS instances across multiple AWS accounts and environments (dev, stg, prod) to a centralized S3 bucket using IAM authentication, Step Functions, and EventBridge scheduling.

**Goal:**  
Implement a secure, scalable, and auditable system for daily PostgreSQL data extraction using short-lived IAM credentials instead of static secrets.

---

### Story 1: Define Solution Architecture & Requirements (**AWS: IAM, Lambda, Step Functions, S3, CloudWatch**)

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

**Story points:** 3  
**Relevant AWS Services:** IAM, Lambda, Step Functions, S3, CloudWatch

---

### Story 2: IAM Role Design for IAM-Based RDS Authentication (**AWS: IAM, RDS, STS, KMS**)

**Description:**  
Design and implement IAM roles and policies that enable Lambda functions to securely authenticate to RDS PostgreSQL using IAM database authentication and STS tokens — eliminating static credential dependencies.

**Acceptance Criteria:**  
- Given each Lambda operates in its own AWS account,  
- When IAM roles are deployed,  
- Then they must:  
  - Use IAM-based database authentication (rds-db:connect).  
  - Assume cross-account roles for centralized orchestration.  
  - Follow least-privilege and resource-scoped policy design.

**Deliverables:**  
- Defined centralized execution role (csdb-data-export-role).  
- Scoped IAM policies for:  
  - rds-db:connect (RDS instance ARNs)  
  - kms:Decrypt, kms:DescribeKey  
  - s3:PutObject (export prefixes)  
  - sts:AssumeRole for cross-account operations  
- Cross-account trust policies validated and tested.

**Story points:** 5  
**Relevant AWS Services:** IAM, RDS, STS, KMS

---

### Story 3: Implement Step Function Orchestration (**AWS: Step Functions, Lambda, IAM, CloudWatch, SNS**)

**Description:**  
Develop an AWS Step Function that coordinates Lambda executions in sequence or parallel to extract RDS data and upload it to S3.

**Acceptance Criteria:**  
- Given a scheduled EventBridge trigger,  
- When the Step Function executes,  
- Then it must:  
  - Orchestrate Lambda invocations in the correct order.  
  - Retry failed Lambdas up to 3 times with exponential backoff.  
  - Log state transitions to CloudWatch.

**Deliverables:**  
- State machine definition and retry logic.  
- Failure handling and alerts via CloudWatch and SNS.  
- Parameterized Lambda ARNs and environment mappings.

**Story points:** 5  
**Relevant AWS Services:** Step Functions, Lambda, IAM, CloudWatch, SNS

---

### Story 4: Develop Data Extraction and Export Functions (**AWS: Lambda, RDS, IAM, S3, KMS, VPC, CloudWatch**)

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

**Deliverables:**  
- Lambda function logic for query execution and CSV export.  
- IAM role-based RDS authentication tested end-to-end.  
- Encrypted data uploads to S3 verified.  
- Network routing and timeout validation.

**Story points:** 8  
**Relevant AWS Services:** Lambda, RDS (PostgreSQL), IAM, S3, KMS, CloudWatch, VPC

---

### Story 5: Configure Centralized S3 Storage and Encryption (**AWS: S3, KMS, IAM, CloudWatch**)

**Description:**  
Provision a centralized S3 bucket for exporting CSV data from all environments, encrypted with KMS and restricted to least-privilege access.

**Acceptance Criteria:**  
- Given S3 bucket resources are created,  
- When CSV data is uploaded,  
- Then it must:  
  - Be encrypted using SSE-KMS.  
  - Follow folder structure: /env/[db_name]/csdb_YYYYMMDD.csv.  
  - Allow write access only to the Lambda roles.

**Deliverables:**  
- S3 bucket with versioning and logging enabled.  
- KMS key and policy integration.  
- S3 bucket policy that enforces TLS and denies public access.  

**Story points:** 5  
**Relevant AWS Services:** S3, KMS, IAM, CloudWatch

---

### Story 6: Monitoring, Logging, and Alerting (**AWS: CloudWatch, Lambda, Step Functions, SNS**)

**Description:**  
Implement centralized monitoring, logging, and alerting for all workflow executions across environments to ensure visibility, reliability, and traceability.

**Acceptance Criteria:**  
- Given observability is required,  
- When workflows execute,  
- Then the system must:  
  - Log all execution details and metrics.  
  - Expose data for task duration, rows exported, and failures.  
  - Trigger alerts on threshold breaches.  
  - Provide traceability for audits.

**Deliverables:**  
- Centralized log configuration.  
- Metrics and dashboards for health visibility.  
- Alerting rules and SNS notifications.  
- Validation of alert propagation across environments.

**Story points:** 5  
**Relevant AWS Services:** CloudWatch, Lambda, Step Functions, SNS

---

### Story 8: Documentation & Handoff (**AWS: IAM, Lambda, Step Functions, S3, CloudWatch**)

**Description:**  
Develop comprehensive documentation that describes architecture, configuration, and operations of the automated data export system for ongoing maintenance by DevOps and platform teams.

**Acceptance Criteria:**  
- Given the system is complete,  
- When documentation is delivered,  
- Then it must include:  
  - Architecture diagrams and data flow.  
  - IAM role relationships and authentication flow.  
  - Orchestration and runtime sequencing.  
  - Operational guidance for monitoring, recovery, and updates.

**Deliverables:**  
- Architecture and operations documentation.  
- System diagrams and flowcharts.  
- Operations runbook and recovery checklist.  
- Handoff session with relevant teams.

**Story points:** 3  
**Relevant AWS Services:** IAM, Lambda, Step Functions, S3, CloudWatch

---

### Story 9: Scheduling and Automation (**AWS: EventBridge, Step Functions, Lambda, CloudWatch**)

**Description:**  
Implement a scheduled trigger to automatically initiate the data export workflow daily. Ensure reliable and consistent execution across environments.

**Acceptance Criteria:**  
- Given the need for daily exports,  
- When the scheduled trigger runs,  
- Then it must:  
  - Invoke the workflow automatically at the defined time.  
  - Handle overlaps and failures gracefully.  
  - Log execution and trigger alerts on failure.

**Deliverables:**  
- Scheduled rule configuration.  
- Validation of daily execution.  
- Documentation of failure handling.  
- Log verification for successful runs.

**Story points:** 3  
**Relevant AWS Services:** EventBridge, Step Functions, Lambda, CloudWatch

---
