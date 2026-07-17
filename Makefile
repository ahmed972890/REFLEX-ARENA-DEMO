.DEFAULT_GOAL := help
COMPOSE = docker compose
FRONTEND_PORT ?= 3000

help: ## Show available targets
	@grep -hE '^[a-zA-Z_-]+:.*## ' $(MAKEFILE_LIST) | awk -F':.*## ' '{printf "  \033[36m%-16s\033[0m %s\n", $$1, $$2}'

## ---------- local development ----------

dev: ## Run the full stack locally (app on http://localhost:3000)
	$(COMPOSE) up --build -d
	@echo "→ app: http://localhost:$(FRONTEND_PORT)   api docs: http://localhost:8000/docs"

logs: ## Tail local stack logs
	$(COMPOSE) logs -f

dev-down: ## Stop the local stack
	$(COMPOSE) down -v

venv: ## Create the backend virtualenv with dev dependencies (uses uv)
	cd backend && uv venv --python 3.12 && uv pip install -e ".[dev]"

test: ## Run backend tests
	cd backend && .venv/bin/pytest

lint: ## Ruff lint + format check
	cd backend && .venv/bin/ruff check . && .venv/bin/ruff format --check .

fmt: ## Auto-format + autofix backend
	cd backend && .venv/bin/ruff format . && .venv/bin/ruff check --fix .

## ---------- load & scaling ----------

smoke-local: ## 30s k6 smoke test against the local stack
	k6 run -e BASE_URL=http://localhost:$(FRONTEND_PORT) loadtest/k6-smoke.js

loadtest-local: ## Full k6 load profile against the local stack
	k6 run -e BASE_URL=http://localhost:$(FRONTEND_PORT) loadtest/k6-load.js

loadtest: ## Full k6 load profile against the cloud: make loadtest URL=http://<nlb-host>
	@test -n "$(URL)" || { echo "usage: make loadtest URL=http://<nlb-hostname>"; exit 1; }
	k6 run -e BASE_URL=$(URL) loadtest/k6-load.js

watch-scaling: ## Live HPA / pod view for the scaling demo
	./scripts/watch-scaling.sh

chaos: ## Kill a random backend pod (reliability demo)
	./scripts/chaos-kill-pod.sh

## ---------- infrastructure ----------

tf-init: ## Bootstrap the S3+DynamoDB state backend, then terraform init
	./scripts/bootstrap-state.sh
	terraform -chdir=infra init -backend-config=backend.hcl

tf-plan: ## Terraform plan
	terraform -chdir=infra plan

tf-apply: ## Provision AWS infra (~15-20 min for EKS)
	terraform -chdir=infra apply

tf-destroy: ## Destroy Terraform-managed infra only — prefer 'make down-cloud'
	terraform -chdir=infra destroy

down-cloud: ## Full teardown: remove k8s workloads (releases the NLB), then destroy AWS infra
	-kubectl delete -k k8s/ --ignore-not-found=true
	@echo "⏳ waiting 90s for AWS to release the NLB created by the Service..."
	@sleep 90
	terraform -chdir=infra destroy

kubeconfig: ## Point kubectl at the EKS cluster
	aws eks update-kubeconfig \
		--region $$(terraform -chdir=infra output -raw region) \
		--name $$(terraform -chdir=infra output -raw cluster_name)

url: ## Print the public URL of the deployed app
	@echo "http://$$(kubectl -n reflex get svc reflex-frontend -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')"

.PHONY: help dev logs dev-down venv test lint fmt smoke-local loadtest-local loadtest \
	watch-scaling chaos tf-init tf-plan tf-apply tf-destroy down-cloud kubeconfig url
