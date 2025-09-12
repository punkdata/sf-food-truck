import boto3
import random
import string
import os

# Initialize the S3 client
s3_client = boto3.client('s3')

def generate_random_string(length=8):
    """Generate a random string of fixed length."""
    letters = string.ascii_lowercase
    return ''.join(random.choice(letters) for _ in range(length))

def create_s3_bucket(bucket_name):
    """Create an S3 bucket with the given name."""
    try:
        s3_client.create_bucket(Bucket=bucket_name)
        print(f"Bucket '{bucket_name}' created successfully.")
        return True
    except Exception as e:
        print(f"Error creating bucket '{bucket_name}': {e}")
        return False

def create_random_file(file_path, content_length=100):
    """Create a file with random content."""
    random_content = ''.join(random.choice(string.ascii_letters + string.digits) for _ in range(content_length))
    with open(file_path, 'w') as f:
        f.write(random_content)
    print(f"File '{file_path}' created with random content.")

def upload_file_to_s3(bucket_name, folder_name, file_path):
    """Upload a file to a specific folder in an S3 bucket."""
    try:
        s3_key = f"{folder_name}/{os.path.basename(file_path)}"
        s3_client.upload_file(file_path, bucket_name, s3_key)
        print(f"File '{file_path}' uploaded to 's3://{bucket_name}/{s3_key}'.")
    except Exception as e:
        print(f"Error uploading file '{file_path}' to bucket '{bucket_name}': {e}")

def main():
    # Number of buckets to create
    num_buckets = 3
    prefix = "testkill-"
    created_buckets = []  # List to store created bucket names

    for _ in range(num_buckets):
        # Generate a random bucket name with the prefix
        random_suffix = generate_random_string()
        bucket_name = prefix + random_suffix

        # Create the S3 bucket
        if create_s3_bucket(bucket_name):
            created_buckets.append(bucket_name)  # Add bucket name to the list

            # Create a randomly named folder in the bucket
            folder_name = generate_random_string()
            print(f"Folder '{folder_name}' created in bucket '{bucket_name}'.")

            # Create a randomly named file with random content
            file_name = generate_random_string() + ".txt"
            file_path = os.path.join(os.getcwd(), file_name)
            create_random_file(file_path)

            # Upload the file to the folder in the bucket
            upload_file_to_s3(bucket_name, folder_name, file_path)

            # Clean up the local file
            os.remove(file_path)
            print(f"Local file '{file_path}' deleted.")

    # Print the list of created bucket names
    print("\nList of created buckets:")
    for bucket in created_buckets:
        print(f"- {bucket}")

if __name__ == "__main__":
    main()