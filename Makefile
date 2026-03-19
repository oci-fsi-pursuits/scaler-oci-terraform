.PHONY: init plan apply destroy ssh deploy build validate fmt help

help: ## Show this help
	@grep -E '^[a-z][a-zA-Z_-]+:.*## ' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*## "}; {printf "  \033[36m%-15s\033[0m %s\n", $$1, $$2}'

init: ## Run terraform init
	terraform init

validate: ## Validate the Terraform configuration
	terraform validate

fmt: ## Format Terraform files
	terraform fmt -recursive

plan: ## Show what Terraform will change
	terraform plan

apply: ## Apply the Terraform configuration
	terraform apply

destroy: ## Destroy all Terraform-managed resources
	terraform destroy

ssh: ## SSH to the scheduler via bastion
	./scripts/ssh-to-scheduler.sh

login: ## Log in to OCIR (requires OCI auth token — see README)
	@echo "Log in to OCIR with your OCI username and auth token."
	@echo "Generate an auth token: OCI Console > Identity > Users > Auth Tokens"
	@echo ""
	docker login $$(terraform output -raw ocir_login_server) \
		-u $$(terraform output -raw object_storage_namespace)/$$(read -p "OCI username: " u && echo $$u)

deploy: ## Deploy scaler source to the scheduler (SCALER_SRC required)
	@if [ -z "$(SCALER_SRC)" ]; then echo "Usage: make deploy SCALER_SRC=../opengris-scaler-oci"; exit 1; fi
	$$(terraform output -raw deploy_scheduler_command | sed "s|<path-to-scaler>|$(SCALER_SRC)|")

ADAPTER ?= hpc
build: ## Build and push worker images to OCIR (SCALER_SRC required, ADAPTER=hpc|raw|both)
	@if [ -z "$(SCALER_SRC)" ]; then echo "Usage: make build SCALER_SRC=../opengris-scaler-oci [ADAPTER=hpc]"; exit 1; fi
	./scripts/build-and-push.sh --scaler-src $(SCALER_SRC) --ocir-uri $$(terraform output -raw ocir_image_uri) --adapter $(ADAPTER)
