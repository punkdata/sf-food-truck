import boto3
import argparse
import sys

```
AWS S3 perms to read and delete buckets


{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": [
                "s3:ListAllMyBuckets",
                "s3:GetBucketLocation"
            ],
            "Resource": "*"
        },
        {
            "Effect": "Allow",
            "Action": [
                "s3:ListBucket",
                "s3:GetObject",
                "s3:DeleteObject",
                "s3:DeleteObjectVersion",
                "s3:ListBucketVersions",
                "s3:BypassGovernanceRetention",
                "s3:PutObjectLegalHold",
                "s3:PutObjectRetention"
            ],
            "Resource": [
                "arn:aws:s3:::example-bucket-name",
                "arn:aws:s3:::example-bucket-name/*"
            ]
        },
        {
            "Effect": "Allow",
            "Action": "s3:DeleteBucket",
            "Resource": "arn:aws:s3:::example-bucket-name"
        }
    ]
}
```

def check_permissions(s3_client, bucket_names):
    """
    Check if the user has the required permissions to delete the specified buckets and their contents.
    Returns True if permissions are sufficient, False otherwise.
    """
    required_permissions = [
        "s3:ListBucket",
        "s3:GetObject",
        "s3:DeleteObject",
        "s3:DeleteObjectVersion",
        "s3:ListBucketVersions",
        "s3:BypassGovernanceRetention",
        "s3:PutObjectLegalHold",
        "s3:PutObjectRetention",
        "s3:DeleteBucket",
        "s3:DeleteBucketPolicy",
        "s3:ListAllMyBuckets",
    ]
    
    try:
        # Check if the user can list all buckets (s3:ListAllMyBuckets permission)
        s3_client.list_buckets()
        
        # Check if the user has permissions to delete the specified buckets and their contents
        for bucket_name in bucket_names:
            # Check if the user can access the bucket (s3:ListBucket permission)
            s3_client.head_bucket(Bucket=bucket_name)
            
            # Check if the user can list objects in the bucket (s3:ListBucket permission)
            s3_client.list_objects_v2(Bucket=bucket_name, MaxKeys=1)
            
            # Check if the user can list object versions (s3:ListBucketVersions permission)
            s3_client.list_object_versions(Bucket=bucket_name, MaxKeys=1)
            
            # Check if the user can delete objects (s3:DeleteObject permission)
            # This is a proxy check using delete operation on a non-existent object
            s3_client.delete_object(Bucket=bucket_name, Key="non-existent-object")
            
            # Check if the user can delete object versions (s3:DeleteObjectVersion permission)
            # This is a proxy check using delete operation on a non-existent object version
            s3_client.delete_object(Bucket=bucket_name, Key="non-existent-object", VersionId="non-existent-version-id")
            
            # Check if the user can bypass governance retention (s3:BypassGovernanceRetention permission)
            # This is a proxy check using a dummy object retention configuration
            try:
                s3_client.put_object_retention(
                    Bucket=bucket_name,
                    Key="non-existent-object",
                    Retention={
                        'Mode': 'GOVERNANCE',
                        'RetainUntilDate': '2030-01-01T00:00:00Z'
                    },
                    BypassGovernanceRetention=True
                )
            except s3_client.exceptions.NoSuchKey:
                pass  # Expected error since the object does not exist
            
            # Check if the user can put object legal holds (s3:PutObjectLegalHold permission)
            try:
                s3_client.put_object_legal_hold(
                    Bucket=bucket_name,
                    Key="non-existent-object",
                    LegalHold={'Status': 'ON'}
                )
            except s3_client.exceptions.NoSuchKey:
                pass  # Expected error since the object does not exist
            
            # Check if the user can put object retention (s3:PutObjectRetention permission)
            try:
                s3_client.put_object_retention(
                    Bucket=bucket_name,
                    Key="non-existent-object",
                    Retention={
                        'Mode': 'COMPLIANCE',
                        'RetainUntilDate': '2030-01-01T00:00:00Z'
                    }
                )
            except s3_client.exceptions.NoSuchKey:
                pass  # Expected error since the object does not exist
        
        return True
    except Exception as e:
        print(f"Permission check failed: {e}")
        return False

def bucket_exists(s3_client, bucket_name):
    """Check if the bucket exists."""
    try:
        s3_client.head_bucket(Bucket=bucket_name)
        return True
    except Exception as e:
        # If the bucket does not exist or there's a permission issue, return False
        return False

def is_bucket_empty(s3_client, bucket_name):
    """Check if the bucket is empty."""
    try:
        response = s3_client.list_objects_v2(Bucket=bucket_name)
        return 'Contents' not in response
    except Exception as e:
        print(f"Error checking if bucket {bucket_name} is empty: {e}")
        return False

def delete_bucket(s3_client, bucket_name):
    """Delete the bucket."""
    try:
        print(f"Deleting bucket: {bucket_name}")
        s3_client.delete_bucket(Bucket=bucket_name)
        print(f"Bucket {bucket_name} deleted successfully.")
    except Exception as e:
        print(f"Error deleting bucket {bucket_name}: {e}")

def list_non_empty_buckets(s3_client, bucket_names):
    """List buckets that are not empty."""
    non_empty_buckets = []
    for bucket_name in bucket_names:
        if not is_bucket_empty(s3_client, bucket_name):
            non_empty_buckets.append(bucket_name)
    return non_empty_buckets

def confirm_action(prompt):
    """Ask the user to confirm an action."""
    choice = input(prompt).strip().lower()
    return choice == 'yes'

def main(bucket_names):
    """Main function to handle bucket deletion."""
    s3_client = boto3.client('s3')
    
    # Check if the user has the required permissions
    if not check_permissions(s3_client, bucket_names):
        print("\nYou do not have the required permissions to delete the specified buckets.")
        print("Please ensure you have the following permissions:")
        print("- s3:ListBucket")
        print("- s3:GetObject")
        print("- s3:DeleteObject")
        print("- s3:DeleteObjectVersion")
        print("- s3:ListBucketVersions")
        print("- s3:BypassGovernanceRetention")
        print("- s3:PutObjectLegalHold")
        print("- s3:PutObjectRetention")
        print("- s3:DeleteBucket")
        print("- s3:DeleteBucketPolicy")
        print("- s3:ListAllMyBuckets")
        sys.exit(1)
    
    # Check if all specified buckets exist
    non_existent_buckets = []
    for bucket_name in bucket_names:
        if not bucket_exists(s3_client, bucket_name):
            non_existent_buckets.append(bucket_name)
    
    if non_existent_buckets:
        print("\nThe following buckets do not exist or you do not have permission to access them:")
        for bucket in non_existent_buckets:
            print(f"- {bucket}")
        print("Exiting script.")
        sys.exit(1)
    
    # Check for non-empty buckets
    non_empty_buckets = list_non_empty_buckets(s3_client, bucket_names)
    
    if non_empty_buckets:
        print("\nThe following buckets are not empty:")
        for bucket in non_empty_buckets:
            print(f"- {bucket}")
    else:
        print("\nAll buckets are empty.")
    
    # Always ask for confirmation before deletion
    if not confirm_action("\nDo you want to proceed with deletion? (yes/no): "):
        print("Deletion aborted by user.")
        return
    
    # Delete buckets
    for bucket_name in bucket_names:
        print(f"\nProcessing bucket: {bucket_name}")
        if confirm_action(f"Are you sure you want to delete bucket '{bucket_name}'? (yes/no): "):
            delete_bucket(s3_client, bucket_name)
        else:
            print(f"Skipping deletion of bucket '{bucket_name}'.")

if __name__ == "__main__":
    # Set up argument parsing
    parser = argparse.ArgumentParser(description="Delete AWS S3 buckets after checking if they are empty.")
    parser.add_argument(
        "buckets",
        nargs="+",
        help="List of S3 bucket names to delete."
    )
    args = parser.parse_args()

    # Call the main function with the bucket names
    main(args.buckets)
