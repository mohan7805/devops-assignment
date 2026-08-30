# Convenience wrappers. Everything here also runs in CI.

SHELL       := /bin/bash
PROJECT     ?= devops-assignment
ENVIRONMENT ?= prod
TF_DIR      := terraform/envs/prod
GIT_SHA     := $(shell git rev-parse --short=7 HEAD 2>/dev/null || echo local)
APP_VERSION ?= 1.0.0

.DEFAULT_GOAL := help

.PHONY: help
help: ## Show this help
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | \
		awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-22s\033[0m %s\n", $$1, $$2}'

# ---------------------------------------------------------------- application
.PHONY: install
install: ## Install application dependencies
	cd app && npm install

.PHONY: test
test: ## Run the unit tests
	cd app && npm test

.PHONY: build
build: ## Build the container image tagged with the short git SHA
	docker build \
		--build-arg APP_VERSION=$(APP_VERSION) \
		--build-arg GIT_COMMIT_SHA=$(GIT_SHA) \
		--build-arg BUILD_DATE=$$(date -u +%Y-%m-%dT%H:%M:%SZ) \
		-t $(PROJECT):$(GIT_SHA) .

.PHONY: scan
scan: build ## Scan the image with Trivy (fails on HIGH/CRITICAL)
	trivy image --severity HIGH,CRITICAL --exit-code 1 $(PROJECT):$(GIT_SHA)

# ------------------------------------------------------------------ local run
.PHONY: up
up: ## Start the local stack (2 API replicas behind nginx) on :8080
	APP_VERSION=$(APP_VERSION) GIT_COMMIT_SHA=$(GIT_SHA) \
		docker compose up --build -d --scale api=2
	@echo "Waiting for the stack..." && sleep 5
	@curl -fsS http://localhost:8080/info || true

.PHONY: down
down: ## Stop the local stack
	docker compose down -v

.PHONY: logs
logs: ## Tail the local stack logs
	docker compose logs -f

.PHONY: compose-test
compose-test: ## Run the unit tests inside the container image
	docker compose --profile test run --rm tests

.PHONY: smoke
smoke: ## Smoke test the local stack
	./scripts/smoke-test.sh http://localhost:8080

# ------------------------------------------------------------------ terraform
.PHONY: tf-fmt
tf-fmt: ## Format the Terraform code
	terraform fmt -recursive terraform/

.PHONY: tf-validate
tf-validate: ## Validate the Terraform code (no backend required)
	terraform -chdir=$(TF_DIR) init -backend=false -input=false
	terraform -chdir=$(TF_DIR) validate

.PHONY: tf-init
tf-init: ## terraform init against the S3 backend (set TF_STATE_BUCKET / TF_LOCK_TABLE)
	terraform -chdir=$(TF_DIR) init -input=false \
		-backend-config="bucket=$(TF_STATE_BUCKET)" \
		-backend-config="key=$(ENVIRONMENT)/terraform.tfstate" \
		-backend-config="region=$(AWS_REGION)" \
		-backend-config="dynamodb_table=$(TF_LOCK_TABLE)"

.PHONY: tf-plan
tf-plan: ## terraform plan
	terraform -chdir=$(TF_DIR) plan -input=false -out=tfplan

.PHONY: tf-apply
tf-apply: ## terraform apply
	terraform -chdir=$(TF_DIR) apply -input=false tfplan

.PHONY: tf-output
tf-output: ## Show the stack outputs
	terraform -chdir=$(TF_DIR) output

# ----------------------------------------------------------------- operations
.PHONY: ssh
ssh: ## Open a shell on an instance via SSM Session Manager (no SSH, no bastion)
	./scripts/ssm-session.sh $(PROJECT) $(ENVIRONMENT)

.PHONY: probe
probe: ## Run the zero-downtime probe against the deployed ALB
	./scripts/zero-downtime-check.sh $$(terraform -chdir=$(TF_DIR) output -raw app_url)

.PHONY: alarm-demo
alarm-demo: ## Drive 5XX traffic until the CloudWatch alarm fires
	./scripts/trigger-alarm.sh \
		$$(terraform -chdir=$(TF_DIR) output -raw app_url) \
		$(PROJECT)-$(ENVIRONMENT)-target-5xx
