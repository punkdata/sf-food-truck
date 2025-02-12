# Open Policy Agent (OPA) Request Process for Terraform Code and Configurations

## Purpose
This document defines a clear and structured process for engineers to request new or modified Open Policy Agent (OPA) policies and tests, specifically for Terraform code and configurations. It is designed to be accessible for both technical and less technical audiences, ensuring that everyone involved can understand and follow the process. The document includes a step-by-step guide, templates for requests and OPA policies, and examples for local execution.

---

## Overview of OPA and Terraform

### What is Open Policy Agent (OPA)?
OPA is a tool that helps enforce rules and policies across your systems. For example, it can ensure that your Terraform configurations meet security, compliance, or best practice requirements.

### What is Terraform?
Terraform is a tool used to define and manage infrastructure as code. It allows you to create, update, and delete cloud resources (like servers, databases, or storage) using configuration files.

### Why Combine OPA and Terraform?
By using OPA with Terraform, you can automatically check that your infrastructure configurations follow your organization’s rules before they are deployed. This helps prevent mistakes and ensures compliance.

---

## Request Process

### Step 1: Submit a Request
1. **Use the OPA Request Template** (provided below) to submit a request.
   - This template ensures you provide all the necessary details for the OPA team to understand your needs.
2. **What to Include**:
   - **Terraform Resource/Configuration**: Describe the specific Terraform resource or configuration you want to evaluate (e.g., an S3 bucket or a virtual machine).
   - **Desired Conditions**: Clearly explain the rules or conditions the OPA policy should enforce (e.g., "All S3 buckets must have encryption enabled").
   - **Examples**: Provide examples of what a valid and invalid configuration looks like.
   - **Priority**: Indicate how urgent the request is (e.g., Low, Medium, High).
   - **Additional Context**: Include any relevant information, such as compliance requirements or security concerns.

### Step 2: OPA Team Review
1. The OPA team will review your request within **2 business days**.
2. If they need more information, they will contact you.
3. Once approved, the request will be prioritized and assigned to an OPA developer.

### Step 3: OPA Development
1. The OPA team will write the policy and create tests to ensure it works as expected.
2. They will use the **OPA Writing Template** (provided below) to ensure consistency and completeness.
3. You will be notified when the policy is ready for your review.

### Step 4: Testing and Validation
1. You will test the OPA policy locally to ensure it works as expected.
2. Provide feedback to the OPA team within **3 business days**.
3. The OPA team will address any issues and finalize the policy.

### Step 5: Deployment
1. The finalized OPA policy will be added to the appropriate repository.
2. You will be notified when the policy is deployed and ready for use.

---

## Template Request

To ensure your OPA request is clear, complete, and easy to process, include the following elements in your submission:

### 1. **Requester Information**
   - **Name**: Your name or the name of the person submitting the request.
   - **Date**: The date of the request.
   - **Priority**: The urgency of the request (Low, Medium, High).

### 2. **Terraform Resource/Configuration**
   - **Resource Type**: The type of Terraform resource (e.g., AWS S3 Bucket, Azure Virtual Machine).
   - **Configuration Example**: A snippet of the Terraform code or configuration you want to evaluate.

### 3. **Desired Conditions**
   - **Condition 1**: The first rule or condition the OPA policy should enforce (e.g., "All S3 buckets must have encryption enabled").
   - **Condition 2**: Additional rules or conditions, if applicable.

### 4. **Examples**
   - **Valid Configuration**: An example of a Terraform configuration that meets the desired conditions.
   - **Invalid Configuration**: An example of a Terraform configuration that does NOT meet the desired conditions.

### 5. **Additional Context**
   - **Compliance Requirements**: Any compliance standards the policy must adhere to (e.g., GDPR, HIPAA).
   - **Security Concerns**: Any security considerations the policy should address (e.g., "Prevent accidental exposure of sensitive data").
   - **Other**: Any other relevant information that could help the OPA team understand your request.

---

## OPA Request Template

Use this template to submit your OPA request. It ensures you provide all the necessary details for the OPA team to understand your needs.

```markdown
### OPA Request Form

**Requester Name**: [Your Name]  
**Date**: [Today’s Date]  
**Priority**: [Low/Medium/High]  

#### Terraform Resource/Configuration
- **Resource Type**: [e.g., AWS S3 Bucket]  
- **Configuration Example**: [Provide a snippet of the Terraform code]  

#### Desired Conditions
- **Condition 1**: [e.g., "All S3 buckets must have encryption enabled"]  
- **Condition 2**: [e.g., "All S3 buckets must block public access"]  

#### Examples
- **Valid Configuration**: [Provide an example of a Terraform configuration that meets the conditions]  
- **Invalid Configuration**: [Provide an example of a Terraform configuration that does NOT meet the conditions]  

#### Additional Context
- **Compliance Requirements**: [e.g., "Must comply with GDPR"]  
- **Security Concerns**: [e.g., "Prevent accidental exposure of sensitive data"]  
- **Other**: [Any other relevant information]  
```

---

## OPA Writing Template

This template guides the OPA team in writing policies and tests. It ensures that all necessary elements are included, such as rules, test cases, and mock data.

### 1. Policy Definition
```rego
package terraform.policies

# Define the policy rule
allow {
    # Condition 1
    # Condition 2
}

# Example: Ensure all S3 buckets have encryption enabled
deny[msg] {
    bucket := input.resource.aws_s3_bucket[name]
    bucket.server_side_encryption_configuration == null
    msg := sprintf("S3 bucket '%s' does not have encryption enabled", [name])
}
```

### 2. Test Cases
```rego
package terraform.policies

# Test valid configuration
test_valid_config {
    allow with input as {
        "resource": {
            "aws_s3_bucket": {
                "example_bucket": {
                    "server_side_encryption_configuration": {
                        "rule": {
                            "apply_server_side_encryption_by_default": {
                                "sse_algorithm": "AES256"
                            }
                        }
                    }
                }
            }
        }
    }
}

# Test invalid configuration
test_invalid_config {
    not allow with input as {
        "resource": {
            "aws_s3_bucket": {
                "example_bucket": {
                    "server_side_encryption_configuration": null
                }
            }
        }
    }
}
```

### 3. Mock Data
```json
{
    "resource": {
        "aws_s3_bucket": {
            "example_bucket": {
                "server_side_encryption_configuration": null
            }
        }
    }
}
```

---

## Local Execution Example

### How to Test the OPA Policy Locally
1. Save the OPA policy in a `.rego` file (e.g., `s3_encryption.rego`).
2. Save the mock data in a `.json` file (e.g., `mock_data.json`).
3. Run the following command in your terminal:
   ```bash
   opa eval --data s3_encryption.rego --input mock_data.json "data.terraform.policies.allow"
   ```
   - This command checks whether the mock data complies with the policy.

---

## Frequently Asked Questions (FAQ)

### 1. What if I don’t know how to write Terraform configurations?
- Provide as much detail as possible about the resource or configuration you want to evaluate. The OPA team can help refine your request.

### 2. How long does it take to develop an OPA policy?
- Development time depends on the complexity of the request. Simple policies may take a few hours, while more complex ones may take several days.

### 3. Can I test the OPA policy before it’s deployed?
- Yes, you will have the opportunity to test the policy locally before it is finalized.

### 4. What if the OPA policy doesn’t work as expected?
- Provide feedback to the OPA team, and they will address any issues.

---

## Conclusion
This document provides a clear and structured process for requesting and developing OPA policies for Terraform code and configurations. By following the provided templates and examples, you can ensure that your requests are completed efficiently and that the resulting policies meet your needs.

---
