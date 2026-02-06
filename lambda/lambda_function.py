import os
import boto3
import urllib.request

AWS_REGION = os.environ.get("AWS_REGION", "us-east-1")
INSTANCE_ID = os.environ["INSTANCE_ID"]
AWS_ENDPOINT_INTERNAL = os.environ["AWS_ENDPOINT_INTERNAL"]  # ex: http://172.17.0.1:4566

DOCKER_PROXY = os.environ.get("DOCKER_PROXY")  # ex: http://docker-proxy:2375

ec2 = boto3.client("ec2", endpoint_url=AWS_ENDPOINT_INTERNAL, region_name=AWS_REGION)

def docker_action(action: str, name: str):
    if not DOCKER_PROXY:
        return False, "DOCKER_PROXY not configured"
    if not name:
        return False, "missing name (?name=...)"

    if action == "start":
        req = urllib.request.Request(f"{DOCKER_PROXY}/containers/{name}/start", method="POST")
    elif action == "stop":
        req = urllib.request.Request(f"{DOCKER_PROXY}/containers/{name}/stop", method="POST")
    else:
        return False, "invalid docker action"

    try:
        with urllib.request.urlopen(req, timeout=10) as r:
            return True, f"docker {action} {name} -> {r.status}"
    except Exception as e:
        return False, f"docker error: {e}"

def handler(event, context):
    qs = (event or {}).get("queryStringParameters") or {}
    action = qs.get("action")
    target = qs.get("target", "ec2")  # ec2 | docker

    if target == "docker":
        ok, msg = docker_action(action, qs.get("name"))
        return {"statusCode": 200 if ok else 400, "body": msg}

    if action == "start":
        ec2.start_instances(InstanceIds=[INSTANCE_ID])
        return {"statusCode": 200, "body": f"started {INSTANCE_ID}"}

    if action == "stop":
        ec2.stop_instances(InstanceIds=[INSTANCE_ID])
        return {"statusCode": 200, "body": f"stopped {INSTANCE_ID}"}

    return {"statusCode": 400, "body": "use ?action=start|stop (optional: &target=docker&name=...)"}
