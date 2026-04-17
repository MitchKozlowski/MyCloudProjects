import json
import os
import boto3
import requests

s3 = boto3.client("s3")

BUCKET = os.environ["BUCKET_NAME"]
KEY = os.environ["KEY_NAME"]

def load_servers():
    try:
        obj = s3.get_object(Bucket=BUCKET, Key=KEY)
        data = obj["Body"].read().decode("utf-8")
        return json.loads(data)
    except Exception as e:
        print(f"Error loading config: {e}")
        return []

def check_server(url):
    try:
        return requests.get(url, timeout=3).status_code == 200
    except:
        return False

def lambda_handler(event, context):
    servers = load_servers()

    if not servers:
        print("No servers found")
        return

    for server in servers:
        if check_server(server):
            print(f"[OK] {server}")
        else:
            print(f"[DOWN] {server}")