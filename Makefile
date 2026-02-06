SHELL := /bin/bash

AWS_REGION ?= us-east-1
AWS_ENDPOINT_PUBLIC ?= $(AWS_ENDPOINT_PUBLIC)

# IMPORTANT: endpoint interne (Lambda -> LocalStack / Docker)
GW ?= 172.17.0.1
AWS_ENDPOINT_INTERNAL ?= http://$(GW):4566
DOCKER_PROXY ?= http://$(GW):2375

# IDs
INSTANCE_ID_FILE := .instance_id
API_ID_FILE := .api_id

.PHONY: help deps up localstack ec2 lambda api deploy test bonus clean status

help:
	@echo "Targets:"
	@echo "  make deps               Install CLI deps (aws, awslocal, jq)"
	@echo "  make up                 Start LocalStack + show health"
	@echo "  make deploy             Create EC2 + deploy Lambda + API Gateway"
	@echo "  make test               Test HTTP start/stop EC2 via API Gateway"
	@echo "  make bonus              Setup docker-proxy + test start/stop container via API Gateway"
	@echo "  make status             Show EC2 + docker container status"
	@echo "  make clean              Delete API/Lambda/EC2 + stop containers"

deps:
	python3 -m pip install --user awscli awscli-local jq localstack
	@echo 'export PATH="$$HOME/.local/bin:$$PATH"'

up: localstack
localstack:
	@docker rm -f localstack 2>/dev/null || true
	docker run -d --name localstack \
	  -p 4566:4566 \
	  -e DEBUG=0 \
	  -e SERVICES=ec2,lambda,apigateway,iam,sts,logs \
	  -e GATEWAY_LISTEN=0.0.0.0:4566 \
	  -v /var/run/docker.sock:/var/run/docker.sock \
	  localstack/localstack:latest
	@sleep 2
	@curl -s http://127.0.0.1:4566/_localstack/health | head -c 200 ; echo

ec2:
	@test -n "$(AWS_ENDPOINT_PUBLIC)" || (echo "ERROR: AWS_ENDPOINT_PUBLIC is empty. Export it first."; exit 1)
	INSTANCE_ID=$$(aws --endpoint-url=$(AWS_ENDPOINT_PUBLIC) ec2 run-instances \
	  --image-id ami-12345678 --count 1 --instance-type t2.micro \
	  | jq -r '.Instances[0].InstanceId'); \
	echo $$INSTANCE_ID > $(INSTANCE_ID_FILE); \
	echo "INSTANCE_ID=$$INSTANCE_ID"

lambda:
	@test -f $(INSTANCE_ID_FILE) || (echo "ERROR: $(INSTANCE_ID_FILE) missing. Run make ec2 first."; exit 1)
	INSTANCE_ID=$$(cat $(INSTANCE_ID_FILE)); \
	mkdir -p lambda; \
	cat > lambda/lambda_function.py << 'PY'
import os
import boto3
import urllib.request

AWS_REGION = os.environ.get("AWS_REGION", "us-east-1")
INSTANCE_ID = os.environ["INSTANCE_ID"]
AWS_ENDPOINT_INTERNAL = os.environ["AWS_ENDPOINT_INTERNAL"]
DOCKER_PROXY = os.environ.get("DOCKER_PROXY")

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
PY
	cd lambda && zip -r ../lambda.zip . >/dev/null && cd ..; \
	aws --endpoint-url=$(AWS_ENDPOINT_PUBLIC) lambda create-function \
	  --function-name infra-controller \
	  --runtime python3.12 \
	  --handler lambda_function.handler \
	  --zip-file fileb://lambda.zip \
	  --role arn:aws:iam::000000000000:role/lambda-role \
	  --timeout 15 \
	  --environment "Variables={INSTANCE_ID=$$INSTANCE_ID,AWS_REGION=$(AWS_REGION),AWS_ENDPOINT_INTERNAL=$(AWS_ENDPOINT_INTERNAL),DOCKER_PROXY=$(DOCKER_PROXY)}" \
	|| aws --endpoint-url=$(AWS_ENDPOINT_PUBLIC) lambda update-function-code \
	  --function-name infra-controller --zip-file fileb://lambda.zip; \
	aws --endpoint-url=$(AWS_ENDPOINT_PUBLIC) lambda update-function-configuration \
	  --function-name infra-controller --timeout 15 \
	  --environment "Variables={INSTANCE_ID=$$INSTANCE_ID,AWS_REGION=$(AWS_REGION),AWS_ENDPOINT_INTERNAL=$(AWS_ENDPOINT_INTERNAL),DOCKER_PROXY=$(DOCKER_PROXY)}"

api:
	API_ID=$$(aws --endpoint-url=$(AWS_ENDPOINT_PUBLIC) apigateway create-rest-api --name "infra-api" | jq -r '.id'); \
	ROOT_ID=$$(aws --endpoint-url=$(AWS_ENDPOINT_PUBLIC) apigateway get-resources --rest-api-id $$API_ID | jq -r '.items[0].id'); \
	RESOURCE_ID=$$(aws --endpoint-url=$(AWS_ENDPOINT_PUBLIC) apigateway create-resource --rest-api-id $$API_ID --parent-id $$ROOT_ID --path-part infra | jq -r '.id'); \
	aws --endpoint-url=$(AWS_ENDPOINT_PUBLIC) apigateway put-method --rest-api-id $$API_ID --resource-id $$RESOURCE_ID --http-method GET --authorization-type NONE; \
	aws --endpoint-url=$(AWS_ENDPOINT_PUBLIC) apigateway put-integration --rest-api-id $$API_ID --resource-id $$RESOURCE_ID --http-method GET --type AWS_PROXY --integration-http-method POST \
	  --uri "arn:aws:apigateway:$(AWS_REGION):lambda:path/2015-03-31/functions/arn:aws:lambda:$(AWS_REGION):000000000000:function:infra-controller/invocations"; \
	aws --endpoint-url=$(AWS_ENDPOINT_PUBLIC) apigateway create-deployment --rest-api-id $$API_ID --stage-name dev >/dev/null; \
	echo $$API_ID > $(API_ID_FILE); \
	echo "API_ID=$$API_ID"

deploy: ec2 lambda api

test:
	@test -n "$(AWS_ENDPOINT_PUBLIC)" || (echo "ERROR: AWS_ENDPOINT_PUBLIC is empty"; exit 1)
	@test -f $(API_ID_FILE) || (echo "ERROR: $(API_ID_FILE) missing. Run make deploy"; exit 1)
	API_ID=$$(cat $(API_ID_FILE)); \
	echo "GET start EC2:"; \
	curl -s "$(AWS_ENDPOINT_PUBLIC)/restapis/$$API_ID/dev/_user_request_/infra?action=start" ; echo; \
	echo "GET stop EC2:"; \
	curl -s "$(AWS_ENDPOINT_PUBLIC)/restapis/$$API_ID/dev/_user_request_/infra?action=stop" ; echo

bonus:
	@docker rm -f docker-proxy 2>/dev/null || true
	docker run -d --name docker-proxy \
	  -p 2375:2375 \
	  -e CONTAINERS=1 -e POST=1 \
	  -v /var/run/docker.sock:/var/run/docker.sock \
	  tecnativa/docker-socket-proxy
	@docker rm -f mycontainer 2>/dev/null || true
	@docker run -d --name mycontainer nginx:alpine >/dev/null
	@test -f $(API_ID_FILE) || (echo "ERROR: $(API_ID_FILE) missing. Run make deploy"; exit 1)
	API_ID=$$(cat $(API_ID_FILE)); \
	echo "GET stop container:"; \
	curl -s "$(AWS_ENDPOINT_PUBLIC)/restapis/$$API_ID/dev/_user_request_/infra?target=docker&action=stop&name=mycontainer" ; echo; \
	echo "GET start container:"; \
	curl -s "$(AWS_ENDPOINT_PUBLIC)/restapis/$$API_ID/dev/_user_request_/infra?target=docker&action=start&name=mycontainer" ; echo

status:
	@echo "EC2:"
	@aws --endpoint-url=$(AWS_ENDPOINT_PUBLIC) ec2 describe-instances | jq '.Reservations[].Instances[] | {InstanceId, State}'
	@echo "Docker:"
	@docker ps --format "table {{.Names}}\t{{.Status}}" | (head -n 1; grep -E "localstack|docker-proxy|mycontainer" || true)

clean:
	@echo "Cleaning resources..."
	@aws --endpoint-url=$(AWS_ENDPOINT_PUBLIC) apigateway delete-rest-api --rest-api-id $$(cat $(API_ID_FILE) 2>/dev/null) 2>/dev/null || true
	@aws --endpoint-url=$(AWS_ENDPOINT_PUBLIC) lambda delete-function --function-name infra-controller 2>/dev/null || true
	@aws --endpoint-url=$(AWS_ENDPOINT_PUBLIC) ec2 terminate-instances --instance-ids $$(cat $(INSTANCE_ID_FILE) 2>/dev/null) 2>/dev/null || true
	@rm -f $(API_ID_FILE) $(INSTANCE_ID_FILE) lambda.zip out.json
	@docker rm -f docker-proxy mycontainer localstack 2>/dev/null || true
	@echo "Done."
