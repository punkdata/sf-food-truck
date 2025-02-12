S
# Request Process for Open Policy Agent (OPA) Code Modifications and Terraform Configurations

## Overview
This document defines the process for engineers to request the creation or modification of Open Policy Agent (OPA) code for use with Terraform code and configurations. The goal is to ensure that requests are clear, well-structured, and include sufficient information for the OPA team to efficiently develop effective policies. The document also provides templates for request submissions, as well as examples for writing OPA rules, creating tests, and integrating into local and CI/CD pipelines.

---

## Request Process Definition

### 1. Initiating a Request
- **Requester**: Developer or team responsible for the infrastructure or Terraform code requiring policy enforcement.
- **Submit to OPA Team**: Submit a request through the designated internal tracking system or via email.

### 2. Required Information for Submission
The request must include the following details:
- **Requestor’s Contact Information**: Name, email, and team information.
- **Context**: A brief description of the Terraform resource or configuration that the OPA policy will apply to.
- **Policy Type**: Indicate whether it is a new policy or an update to an existing policy.
- **Policy Goal**: A clear description of what the policy should enforce or prevent. Examples include restrictions on resource sizes, specific tags, or ensuring certain resource types are always used.
- **Terraform Resources and Code**: Provide the relevant Terraform code that needs to be checked by OPA, as well as a description of any configurations that impact policy.
- **Mock Data for Testing**: A sample of real or near-real Terraform input data that will allow OPA to validate the policies against common use cases. Ensure this data is anonymized if sensitive.
- **Expected Outcome**: Describe the expected outcome if the policy is violated or if it passes validation.

### 3. Template for Request Submission
Use the following template to submit your request:
```plaintext
**Requestor Name:**
- Name:
- Team/Department:
- Contact Email:

**Policy Type:**
- New Policy / Update to Existing Policy

**Policy Description:**
- What is the specific problem that the OPA policy should address? Example: "Ensure all EC2 instances have the tag 'Environment' set to 'Production'."

**Relevant Terraform Code:**
- Provide the section of the Terraform configuration or module being referenced.

**Mock Data (Sample Terraform Variables/Resources):**
- Include any relevant Terraform variable definitions or mock data to test against the policy.

**Expected Outcome:**
- Describe the result of a policy violation (e.g., a violation of a tag requirement would result in the resource not being created).

**Testing Requirements:**
- Specify if any additional test scenarios should be included, such as edge cases or resource configurations outside of typical usage.
```

### 4. OPA Development Timeline
- **Initial Review**: Upon receiving the request, the OPA team will acknowledge receipt and schedule a review.
- **Development**: The OPA team will draft the policy and associated tests.
- **Review & Feedback**: A review will be conducted with the requestor for validation and adjustments.
- **Final Approval**: After testing in staging or local environments, the policy will be ready for deployment.

---

## OPA Writing Template

To ensure consistency and maintainability of OPA policies, use the following template when writing OPA code.

```rego
# Define the policy rule
package terraform.policies

# Main rule defining the policy
allow {
    input.resource_type == "aws_instance"
    input.tags["Environment"] == "Production"
}

# Rego rule to check resource tag for production
deny {
    input.resource_type == "aws_instance"
    not input.tags["Environment"]
}

# Optional: Helper functions for validation
is_valid_instance_type(resource_type) {
    resource_type == "t2.micro"  # Example of validation
}

# Tests for the OPA rule
test_allow {
    input := {
        "resource_type": "aws_instance",
        "tags": {
            "Environment": "Production"
        }
    }
    allow with input as input
}

test_deny {
    input := {
        "resource_type": "aws_instance",
        "tags": {}
    }
    deny with input as input
}
```

### Explanation:
- **Main Policy Rule**: The `allow` rule defines what is considered valid behavior, whereas `deny` defines what is invalid.
- **Helper Functions**: These are reusable functions that provide validation logic, such as checking for valid instance types.
- **Tests**: The `test_allow` and `test_deny` sections simulate the inputs and validate the expected outputs.

---

## Writing Valid and Effective OPAs

When writing OPAs:
1. **Keep it Simple**: Avoid complex, nested conditions that can be hard to maintain.
2. **Be Descriptive**: Use comments and clear variable names to describe the purpose of each rule.
3. **Edge Case Handling**: Consider edge cases and ensure they are covered by tests (e.g., missing or unexpected tags).
4. **Test Coverage**: Include test cases for all possible scenarios to ensure that the OPA rule behaves correctly across various inputs.

---

## Local and CI/CD Pipeline Execution Examples

### Local Execution Example
To test OPA locally, you can use the `opa` command-line tool:

1. **Install OPA**:
   - Download and install OPA from [OPA's website](https://www.openpolicyagent.org/docs/latest/getting-started/#1-download-opa).

2. **Test Locally**:
   - Save your policy (e.g., `policy.rego`) and a test input (e.g., `input.json`).
   - Run the following command to test the policy:
     ```bash
     opa eval --data policy.rego --input input.json "data.terraform.policies.allow"
     ```

   This will evaluate the `allow` rule in the `terraform.policies` package.

### CI/CD Pipeline Integration Example for AWS CodeBuild

You can set up AWS CodeBuild to validate your Terraform code and OPA policies by using the `opa` command in a `buildspec.yml` file.

#### 1. Prepare your `buildspec.yml`:
The `buildspec.yml` file defines the commands AWS CodeBuild will execute during the build process. Below is an example `buildspec.yml` for validating Terraform code with OPA:

```yaml
version: 0.2

phases:
  install:
    commands:
      # Install OPA (Open Policy Agent)
      - echo "Installing OPA..."
      - curl -LO https://openpolicyagent.org/downloads/latest/opa_linux_amd64
      - chmod +x opa_linux_amd64
      - mv opa_linux_amd64 /usr/local/bin/opa
      - echo "OPA installation complete."

      # Install Terraform (if needed)
      - echo "Installing Terraform..."
      - curl -LO https://releases.hashicorp.com/terraform/1.4.6/terraform_1.4.6_linux_amd64.zip
      - unzip terraform_1.4.6_linux_amd64.zip
      - mv terraform /usr/local/bin/
      - terraform --version
      - echo "Terraform installation complete."

  build:
    commands:
      # Initialize Terraform (this step is optional, depending on your project setup)
      - echo "Initializing Terraform..."
      - terraform init

      # Validate Terraform configuration
      - echo "Validating Terraform code..."
      - terraform validate

      # Assuming 'policy.rego' and 'terraform_input.json' are part of your repository:
      - echo "Running OPA policy validation..."
      - opa eval --data policy.rego --input terraform_input.json "data.terraform.policies.allow"

      # If needed, you can also run Terraform plan to validate resources
      - echo "Running Terraform plan..."
      - terraform plan -out=tfplan

  post_build:
    commands:
      - echo "Build complete. OPA validation passed!"
      - echo "Terraform plan execution complete."
```

#### Explanation of the `buildspec.yml`:
1. **Install Phase**:
   - Downloads and installs **OPA** (Open Policy Agent) and **Terraform** in the environment where CodeBuild will execute the build.
   
2. **Build Phase**:
   - Runs `terraform init` to initialize Terraform (if required).
   - Runs `terraform validate` to validate the Terraform configuration files.
   - Runs the `opa eval` command to evaluate the `policy.rego` policy file against `terraform_input.json`, where `terraform_input.json` represents the mock data or the input configuration you're testing.
   - Optionally, the build phase can also include a `terraform plan` command to simulate applying the Terraform configuration and view its effects (this is a good safety step before deployment).

3. **Post-Build Phase**:
   - Outputs a confirmation message to indicate that the build, OPA validation, and Terraform plan ran successfully.

---

#### 2. Integrating into AWS CodePipeline:

After creating the `buildspec.yml` file, ensure it's placed at the root of your repository. AWS CodeBuild will use this file to execute the build.

To integrate this into an AWS CodePipeline, follow these steps:

1. **Create a CodePipeline** (or update an existing one) that has:
   - **Source Stage**: Pulls the latest code from a repository (e.g., GitHub, AWS CodeCommit).
   - **Build Stage**: Uses the AWS CodeBuild project configured with the `buildspec.yml` file above.

2. **Create a CodeBuild Project**:
   - In the AWS Management Console, go to **AWS CodeBuild** and create a new project.
   - Under **Environment**, select the appropriate operating system and runtime (for example, `Ubuntu`).
   - Under **Buildspec**, select "Use a buildspec file" and ensure the file is at the root of your repository (or you can specify a path to it).
   - Connect your CodeBuild project to your **AWS CodePipeline**.

3. **Define the Pipeline in CodePipeline**:
   - **Source**: Set up a source stage for your repository.
   - **Build**: Add a build stage where CodeBuild will execute the `buildspec.yml` file.

---

#### 3. Optional: Artifact Output in CodeBuild:

If you need to output any results from your validation, such as logs or reports, you can configure **artifacts** in CodeBuild. For example, modify the `buildspec.yml` to output logs:

```yaml
artifacts:
  files:
    - '**/*'
  discard-paths: yes
```

This will include all files in the build directory as artifacts, which can be useful for storing the output logs or other relevant files for later reference.

---

## Conclusion
With this configuration, every time CodePipeline triggers a build in CodeBuild, it will validate the Terraform configuration against the defined OPA policy using the `buildspec.yml`. This ensures that your Terraform configurations conform to the defined policies before being applied to the environment, thus enhancing security and compliance automation in your CI/CD pipeline.
