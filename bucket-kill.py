import boto3
import argparse
import sys

def confirm_action(prompt):
    """Ask the user to confirm an action. Exit the script if the user says 'no'."""
    while True:
        choice = input(prompt).strip().lower()
        if choice == 'yes':
            return True
        elif choice == 'no':
            print("Delete operation aborted. No changes made.")
            sys.exit()  # Exit the script entirely
        else:
            print("Invalid input. Please enter 'yes' or 'no'.")

def delete_all_object_versions(s3_client, bucket_name):
    """Delete all object versions and delete markers in the bucket."""
    try:
        # List all object versions in the bucket
        response = s3_client.list_object_versions(Bucket=bucket_name)
        
        # Counters for versions and delete markers
        versions_deleted = 0
        markers_deleted = 0
        
        # Delete all versions if confirmed
        if 'Versions' in response:
            print(f"Found {len(response['Versions'])} object versions in bucket '{bucket_name}'.")
            if confirm_action("Do you want to delete all object versions? (yes/no): "):
                for version in response['Versions']:
                    s3_client.delete_object(
                        Bucket=bucket_name,
                        Key=version['Key'],
                        VersionId=version['VersionId']
                    )
                    versions_deleted += 1
                print(f"Deleted {versions_deleted} object versions.")
        
        # Delete all delete markers if confirmed
        if 'DeleteMarkers' in response:
            print(f"Found {len(response['DeleteMarkers'])} delete markers in bucket '{bucket_name}'.")
            if confirm_action("Do you want to delete all delete markers? (yes/no): "):
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
                if confirm_action("Do you want to delete these additional object versions? (yes/no): "):
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
                if confirm_action("Do you want to delete these additional delete markers? (yes/no): "):
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
            if confirm_action("Do you want to delete all objects? (yes/no): "):
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
                if confirm_action("Do you want to delete these additional objects? (yes/no): "):
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
        if confirm_action(f"Are you sure you want to delete bucket '{bucket_name}'? (yes/no): "):
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
        "buckets",
        nargs="+",
        help="List of S3 bucket names to delete."
    )
    args = parser.parse_args()

    # Call the main function with the bucket names
    main(args.buckets)