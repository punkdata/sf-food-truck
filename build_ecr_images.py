#!/usr/bin/env python3

import subprocess
import sys
import argparse
import json
from pathlib import Path

def run_cmd(cmd, cwd=None, input_text=None, hide_output=False):
    try:
        result = subprocess.run(
            cmd,
            cwd=cwd,
            input=input_text,
            check=True,
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
        )
        if not hide_output:
            print(result.stdout)
        return result.stdout.strip()
    except subprocess.CalledProcessError as e:
        print(f"Command failed: {' '.join(cmd)}")
        if not hide_output:
            print(f"stdout: {e.stdout}")
            print(f"stderr: {e.stderr}")
        sys.exit(1)

def docker_login(ecr_uri, region):
    print(f"Logging in to ECR: {ecr_uri}")
    password = run_cmd(["aws", "ecr", "get-login-password", "--region", region], hide_output=True)
    run_cmd(
        ["docker", "login", "--username", "AWS", "--password-stdin", ecr_uri],
        input_text=password,
        hide_output=True
    )

def delete_tag_if_exists(ecr_repo_name, ecr_uri, region, tag):
    print(f"Checking for existing tag '{tag}' in {ecr_repo_name}...")

    try:
        output = run_cmd([
            "aws", "ecr", "describe-images",
            "--repository-name", ecr_repo_name,
            "--region", region,
            "--query", f"imageDetails[?contains(imageTags, '{tag}')]",
            "--output", "json"
        ], hide_output=True)
        image_details = json.loads(output)

        if image_details:
            image_digest = image_details[0]["imageDigest"]
            print(f"Found existing :{tag} tag with digest: {image_digest}")
            print(f"Deleting existing :{tag} tag...")
            run_cmd([
                "aws", "ecr", "batch-delete-image",
                "--repository-name", ecr_repo_name,
                "--region", region,
                "--image-ids", f"imageDigest={image_digest}"
            ])
        else:
            print(f"No :{tag} tag found, continuing...")
    except Exception as e:
        print(f"Failed to check/delete :{tag} tag: {e}")
        sys.exit(1)

def build_image(ecr_repo_name, ecr_uri, dockerfile_path, custom_tag):
    dockerfile = Path(dockerfile_path)
    if not dockerfile.exists():
        print(f"Error: Dockerfile not found at {dockerfile}")
        sys.exit(1)

    latest_tag = f"{ecr_uri}/{ecr_repo_name}:latest"
    custom_tag_full = f"{ecr_uri}/{ecr_repo_name}:{custom_tag}"

    tags = [latest_tag, custom_tag_full]

    print(f"Building image with tags: {', '.join(tags)} using Dockerfile: {dockerfile}")
    build_context = dockerfile.parent

    build_cmd = [
        "docker", "build",
        "-f", str(dockerfile),
    ]
    for tag in tags:
        build_cmd.extend(["-t", tag])
    build_cmd.append(str(build_context))  # Proper build context

    run_cmd(build_cmd)

def push_all_tags(ecr_repo_name, ecr_uri):
    image_repo = f"{ecr_uri}/{ecr_repo_name}"
    print(f"Pushing all local tags for image: {image_repo}")
    run_cmd(["docker", "push", "--all-tags", image_repo])

def main():
    parser = argparse.ArgumentParser(
        description="Build and push Docker images to ECR with required tag argument."
    )
    parser.add_argument("--region", required=True, help="AWS region of the ECR repository.")
    parser.add_argument("--ecr-name", required=True, help="Name of the ECR repository (used for tagging).")
    parser.add_argument("--ecr-uri", required=True, help="URI of the ECR registry.")
    parser.add_argument("--dockerfile", required=True, help="Path to the Dockerfile.")
    parser.add_argument("--tag", required=True, help="Tag for the image to apply and push (e.g. full commit SHA).")

    args = parser.parse_args()

    # Shorten the tag to first 7 characters
    short_tag = args.tag[:7]
    print(f"Using shortened tag: {short_tag} (from {args.tag})")

    docker_login(args.ecr_uri, args.region)
    delete_tag_if_exists(args.ecr_name, args.ecr_uri, args.region, "latest")
    delete_tag_if_exists(args.ecr_name, args.ecr_uri, args.region, short_tag)

    build_image(args.ecr_name, args.ecr_uri, args.dockerfile, short_tag)
    push_all_tags(args.ecr_name, args.ecr_uri)

if __name__ == "__main__":
    main()
