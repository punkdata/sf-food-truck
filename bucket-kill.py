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

def get_all_regions():
    """Get a list of all AWS regions."""
    ec2_client = boto3.client('ec2')
    regions = ec2_client.describe_regions()
    return [region['RegionName'] for region in regions['Regions']]

def check_permissions(s3_client, bucket_names):
    """
    Check if the user has permissions to list and delete buckets.
    Returns True if permissions are sufficient, False otherwise.
    """
    try:
        # Check if the user can list buckets
        s3_client.list_buckets()
        
        # Check if the user can access the specified buckets
        for bucket_name in bucket_names:
            s3_client.head_bucket(Bucket=bucket_name)
            s3_client.list_objects_v2(Bucket=bucket_name, MaxKeys=1)
        
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
    regions = get_all_regions()
    
    for region in regions:
        print(f"\nChecking region: {region}")
        s3_client = boto3.client('s3', region_name=region)
        
        # Perform a preliminary permission check
        if not check_permissions(s3_client, bucket_names):
            print(f"Insufficient permissions in region {region}. Skipping this region.")
            continue
        
        # Check if all specified buckets exist in this region
        non_existent_buckets = []
        for bucket_name in bucket_names:
            if not bucket_exists(s3_client, bucket_name):
                non_existent_buckets.append(bucket_name)
        
        if non_existent_buckets:
            print(f"The following buckets do not exist in region {region}:")
            for bucket in non_existent_buckets:
                print(f"- {bucket}")
            continue  # Skip to the next region
        
        # Check for non-empty buckets
        non_empty_buckets = list_non_empty_buckets(s3_client, bucket_names)
        
        if non_empty_buckets:
            print(f"The following buckets are not empty in region {region}:")
            for bucket in non_empty_buckets:
                print(f"- {bucket}")
        else:
            print(f"All specified buckets are empty in region {region}.")
        
        # Always ask for confirmation before deletion
        if not confirm_action(f"\nDo you want to proceed with deletion in region {region}? (yes/no): "):
            print(f"Deletion aborted for region {region}.")
            continue
        
        # Delete buckets
        for bucket_name in bucket_names:
            print(f"\nProcessing bucket: {bucket_name} in region {region}")
            if confirm_action(f"Are you sure you want to delete bucket '{bucket_name}' in region {region}? (yes/no): "):
                delete_bucket(s3_client, bucket_name)
            else:
                print(f"Skipping deletion of bucket '{bucket_name}' in region {region}.")

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
