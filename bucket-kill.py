import boto3
import argparse
import sys
from botocore.exceptions import ClientError

def bucket_exists(s3_client, bucket_name):
    """Check if the bucket exists and is accessible."""
    try:
        s3_client.head_bucket(Bucket=bucket_name)
        return True
    except ClientError as e:
        error_code = e.response['Error']['Code']
        if error_code == '404':
            # Bucket does not exist
            print(f"Bucket '{bucket_name}' does not exist. Skipping to the next bucket.")
            return False
        elif error_code == '403':
            # Bucket exists, but access is forbidden
            print(f"Access to bucket '{bucket_name}' is forbidden. Skipping to the next bucket.")
            return False
        else:
            # Handle other errors
            print(f"Error checking bucket '{bucket_name}': {e}")
            return False

def delete_all_object_versions(s3_client, bucket_name):
    """Delete all object versions and delete markers in the bucket."""
    try:
        # List all object versions in the bucket
        response = s3_client.list_object_versions(Bucket=bucket_name)
        
        # Counters for versions and delete markers
        versions_deleted = 0
        markers_deleted = 0
        
        # Delete all versions without confirmation
        if 'Versions' in response:
            print(f"Found {len(response['Versions'])} object versions in bucket '{bucket_name}'.")
            for version in response['Versions']:
                s3_client.delete_object(
                    Bucket=bucket_name,
                    Key=version['Key'],
                    VersionId=version['VersionId']
                )
                versions_deleted += 1
            print(f"Deleted {versions_deleted} object versions.")
        
        # Delete all delete markers without confirmation
        if 'DeleteMarkers' in response:
            print(f"Found {len(response['DeleteMarkers'])} delete markers in bucket '{bucket_name}'.")
            for marker in response['DeleteMarkers']:
                s3_client.delete_object(
                    Bucket=bucket_name,
                    Key=marker['Key'],
                    VersionId=marker['VersionId']
                )
                markers_deleted += 1
            print(f"Deleted {markers_deleted} delete markers.")
        
        # Continue listing and deleting if there are more versions
        while response.get('IsTruncated'):
            response = s3_client.list_object_versions(
                Bucket=bucket_name,
                KeyMarker=response.get('NextKeyMarker'),
                VersionIdMarker=response.get('NextVersionIdMarker')
            )
            
            if 'Versions' in response:
                print(f"Found {len(response['Versions'])} additional object versions in bucket '{bucket_name}'.")
                for version in response['Versions']:
                    s3_client.delete_object(
                        Bucket=bucket_name,
                        Key=version['Key'],
                        VersionId=version['VersionId']
                    )
                    versions_deleted += 1
                print(f"Deleted {len(response['Versions'])} additional object versions.")
            
            if 'DeleteMarkers' in response:
                print(f"Found {len(response['DeleteMarkers'])} additional delete markers in bucket '{bucket_name}'.")
                for marker in response['DeleteMarkers']:
                    s3_client.delete_object(
                        Bucket=bucket_name,
                        Key=marker['Key'],
                        VersionId=marker['VersionId']
                    )
                    markers_deleted += 1
                print(f"Deleted {len(response['DeleteMarkers'])} additional delete markers.")
        
        print(f"All object versions and delete markers processed for bucket: {bucket_name}")
    except Exception as e:
        print(f"Error deleting object versions in bucket {bucket_name}: {e}")

def delete_all_objects(s3_client, bucket_name):
    """Delete all objects in the bucket."""
    try:
        # List all objects in the bucket
        response = s3_client.list_objects_v2(Bucket=bucket_name)
        
        # Counter for deleted objects
        objects_deleted = 0
        
        if 'Contents' in response:
            print(f"Found {len(response['Contents'])} objects in bucket '{bucket_name}'.")
            for obj in response['Contents']:
                s3_client.delete_object(Bucket=bucket_name, Key=obj['Key'])
                objects_deleted += 1
            print(f"Deleted {objects_deleted} objects.")
        
        # Continue listing and deleting if there are more objects
        while response.get('IsTruncated'):
            response = s3_client.list_objects_v2(
                Bucket=bucket_name,
                ContinuationToken=response.get('NextContinuationToken')
            )
            
            if 'Contents' in response:
                print(f"Found {len(response['Contents'])} additional objects in bucket '{bucket_name}'.")
                for obj in response['Contents']:
                    s3_client.delete_object(Bucket=bucket_name, Key=obj['Key'])
                    objects_deleted += 1
                print(f"Deleted {len(response['Contents'])} additional objects.")
        
        print(f"All objects processed for bucket: {bucket_name}")
    except Exception as e:
        print(f"Error deleting objects in bucket {bucket_name}: {e}")

def delete_bucket(s3_client, bucket_name):
    """Delete the bucket."""
    try:
        print(f"Deleting bucket: {bucket_name}")
        s3_client.delete_bucket(Bucket=bucket_name)
        print(f"Bucket {bucket_name} deleted successfully.")
    except Exception as e:
        print(f"Error deleting bucket {bucket_name}: {e}")

def main(bucket_names):
    """Main function to handle bucket deletion."""
    s3_client = boto3.client('s3')
    
    for bucket_name in bucket_names:
        print(f"\nProcessing bucket: {bucket_name}")
        
        # Check if the bucket exists and is accessible
        if not bucket_exists(s3_client, bucket_name):
            continue  # Skip to the next bucket
        
        # Delete all object versions and delete markers
        delete_all_object_versions(s3_client, bucket_name)
        
        # Delete all objects
        delete_all_objects(s3_client, bucket_name)
        
        # Delete the bucket
        delete_bucket(s3_client, bucket_name)

if __name__ == "__main__":
    # Set up argument parsing
    parser = argparse.ArgumentParser(description="Delete AWS S3 buckets and their contents.")
    parser.add_argument(
        "--s3-buckets",
        dest="s3_buckets",
        metavar="s3_bucket",
        nargs="+",
        help="List of S3 bucket names to delete.",
        required=True
    )
    args = parser.parse_args()

    # Call the main function with the bucket names
    main(args.s3_buckets)