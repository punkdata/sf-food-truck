import boto3
import csv
import io
import json
import logging
from datetime import datetime, timedelta
from botocore.exceptions import BotoCoreError, ClientError

# Configure logging
logger = logging.getLogger()
logger.setLevel(logging.INFO)

# AWS clients
session = boto3.Session()
cloudtrail = session.client("cloudtrail")
iam = session.client("iam")
s3 = session.client("s3")

# Config
SERVICES = ["sns.amazonaws.com", "sqs.amazonaws.com", "events.amazonaws.com"]
LOOKBACK_DAYS = 30
OUTPUT_BUCKET = "my-report-bucket"   # <-- replace with your S3 bucket
OUTPUT_KEY = "reports/cloudtrail_access.csv"


def get_events():
    """Retrieve CloudTrail events for SNS, SQS, EventBridge."""
    start_time = datetime.utcnow() - timedelta(days=LOOKBACK_DAYS)
    end_time = datetime.utcnow()

    events = []
    try:
        for service in SERVICES:
            paginator = cloudtrail.get_paginator("lookup_events")
            for page in paginator.paginate(
                LookupAttributes=[
                    {"AttributeKey": "EventSource", "AttributeValue": service}
                ],
                StartTime=start_time,
                EndTime=end_time,
            ):
                events.extend(page.get("Events", []))
    except (BotoCoreError, ClientError) as e:
        logger.error(f"Error retrieving CloudTrail events: {e}")
    return events


def get_identity_info(event):
    """Extract user/role name and type."""
    username = "Unknown"
    principal_type = "Unknown"

    try:
        detail = json.loads(event.get("CloudTrailEvent", "{}")).get("userIdentity", {})
        principal_type = detail.get("type", "Unknown")

        if principal_type == "IAMUser":
            username = detail.get("userName", "Unknown")
            principal_type = "User"

        elif principal_type == "AssumedRole":
            arn = detail.get("arn", "")
            # arn:aws:sts::123456789012:assumed-role/RoleName/SessionName
            if "assumed-role/" in arn:
                username = arn.split("/")[-2]
            else:
                username = arn
            principal_type = "Role"

        elif principal_type == "AWSService":
            username = detail.get("invokedBy", "AWSService")
            principal_type = "Service"

    except (ValueError, KeyError) as e:
        logger.warning(f"Failed to parse identity info: {e}")

    return username, principal_type


def get_tag_value(name, principal_type):
    """Retrieve the AIT tag if present on the user/role."""
    try:
        if principal_type == "User":
            tags = iam.list_user_tags(UserName=name)["Tags"]
        elif principal_type == "Role":
            tags = iam.list_role_tags(RoleName=name)["Tags"]
        else:
            return ""
        for tag in tags:
            if tag["Key"] == "AIT":
                return tag["Value"]
    except (BotoCoreError, ClientError) as e:
        logger.warning(f"Could not fetch tags for {principal_type} {name}: {e}")
    return ""


def lambda_handler(event, context):
    logger.info("Starting CloudTrail report generation")
    results = {}

    try:
        events = get_events()
        logger.info(f"Retrieved {len(events)} CloudTrail events")
    except Exception as e:
        logger.error(f"Fatal error retrieving events: {e}")
        return {"statusCode": 500, "body": "Failed to retrieve events"}

    for e in events:
        try:
            username, principal_type = get_identity_info(e)
            if username == "Unknown":
                continue

            last_time = e.get("EventTime")
            key = (username, principal_type)

            if key not in results or (
                last_time and results[key]["last_time"] < last_time
            ):
                results[key] = {
                    "username": username,
                    "type": principal_type,
                    "last_time": last_time,
                    "AIT": get_tag_value(username, principal_type),
                }
        except Exception as err:
            logger.warning(f"Skipping malformed event: {err}")

    # Write CSV to memory
    csv_buffer = io.StringIO()
    writer = csv.DictWriter(
        csv_buffer, fieldnames=["Name", "Type", "LastTimeAccessed", "AIT"]
    )
    writer.writeheader()

    for entry in results.values():
        writer.writerow(
            {
                "Name": entry["username"],
                "Type": entry["type"],
                "LastTimeAccessed": entry["last_time"].isoformat()
                if entry["last_time"]
                else "",
                "AIT": entry["AIT"],
            }
        )

    # Upload to S3
    try:
        s3.put_object(
            Bucket=OUTPUT_BUCKET,
            Key=OUTPUT_KEY,
            Body=csv_buffer.getvalue(),
            ContentType="text/csv",
        )
        logger.info(f"Report written to s3://{OUTPUT_BUCKET}/{OUTPUT_KEY}")
        return {
            "statusCode": 200,
            "body": f"Report written to s3://{OUTPUT_BUCKET}/{OUTPUT_KEY}",
        }
    except (BotoCoreError, ClientError) as e:
        logger.error(f"Failed to upload CSV to S3: {e}")
        return {"statusCode": 500, "body": "Failed to upload report to S3"}
