# Default target
.DEFAULT_GOAL := help

# Optional variables that can be passed to override configurations
# E.g. make up ENABLE_INGRESS_LB=true WORKER_NODE_COUNT=2
TF_ARGS =
ifdef ENABLE_INGRESS_LB
  TF_ARGS += -var="enable_ingress_lb=$(ENABLE_INGRESS_LB)"
endif
ifdef WORKER_NODE_COUNT
  TF_ARGS += -var="worker_node_count=$(WORKER_NODE_COUNT)"
endif
ifdef CONTROL_PLANE_NODE_COUNT
  TF_ARGS += -var="control_plane_node_count=$(CONTROL_PLANE_NODE_COUNT)"
endif
ifdef DOCKER_HOST
  TF_ARGS += -var="docker_host=$(DOCKER_HOST)"
endif
ifdef ENABLE_FEATURE_GATES
  TF_ARGS += -var="enable_feature_gates=$(ENABLE_FEATURE_GATES)"
endif
ifdef ENABLE_RUNTIME_CONFIG
  TF_ARGS += -var="enable_runtime_config=$(ENABLE_RUNTIME_CONFIG)"
endif
ifdef KIND_CLUSTER_NODE_IMAGE
  TF_ARGS += -var="kind_cluster_node_image=$(KIND_CLUSTER_NODE_IMAGE)"
endif

# Variables for building node images
KUBERNETES_VERSION ?= v1.35.0
IMAGE_NAME ?= kindest/node:$(KUBERNETES_VERSION)

.PHONY: help init up down status test clean-test lint format build-node-image

help: ## Show this help message
	@echo "Usage: make [target]"
	@echo ""
	@echo "Targets:"
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-15s\033[0m %s\n", $$1, $$2}'

init: ## Initialize Terraform working directory
	@echo "Initializing Terraform..."
	terraform init

up: ## Provision the Kind cluster and optional cloud-provider-kind container
	@echo "Provisioning Kind cluster..."
	terraform apply -auto-approve $(TF_ARGS)

down: ## Destroy the Kind cluster and resources
	@echo "Destroying Kind cluster..."
	terraform destroy -auto-approve $(TF_ARGS)

status: ## Show cluster status, kubeconfig path, docker containers, and k8s nodes
	@CLUSTER_NAME=$$(terraform output -raw cluster_name 2>/dev/null || echo ""); \
	if [ -z "$$CLUSTER_NAME" ]; then \
		echo "No active cluster found in Terraform state. Run 'make up' first."; \
		exit 0; \
	fi; \
	echo "=== Cluster Info ==="; \
	echo "Name: $$CLUSTER_NAME"; \
	KUBECONFIG_PATH=$$(terraform output -raw kubeconfig_path 2>/dev/null); \
	echo "Kubeconfig Path: $$KUBECONFIG_PATH"; \
	echo ""; \
	echo "=== Kind/Docker Status ==="; \
	if docker ps --format '{{.Names}}' | grep -q "^$$CLUSTER_NAME-control-plane$$"; then \
		echo "Control plane container is running."; \
	else \
		echo "Control plane container is NOT running."; \
	fi; \
	if docker ps --format '{{.Names}}' | grep -q "^cloud-provider-kind$$"; then \
		echo "cloud-provider-kind container is running."; \
	else \
		echo "cloud-provider-kind container is NOT running (disabled or stopped)."; \
	fi; \
	echo ""; \
	echo "=== Kubernetes Nodes ==="; \
	if [ -f "$$KUBECONFIG_PATH" ]; then \
		kubectl get nodes --kubeconfig="$$KUBECONFIG_PATH" || echo "Failed to connect to cluster."; \
	else \
		echo "Kubeconfig file not found at $$KUBECONFIG_PATH"; \
	fi

test: ## Deploy test application and verify ingress/load balancer functionality
	@KUBECONFIG_PATH=$$(terraform output -raw kubeconfig_path 2>/dev/null); \
	if [ -z "$$KUBECONFIG_PATH" ] || [ ! -f "$$KUBECONFIG_PATH" ]; then \
		echo "No kubeconfig found. Is the cluster running?"; \
		exit 1; \
	fi; \
	echo "Applying test kustomize resources..."; \
	kubectl apply -k test/kustomize --kubeconfig="$$KUBECONFIG_PATH"; \
	echo "Waiting for Ingress to be assigned an IP address..."; \
	attempt=1; \
	max_attempts=24; \
	while [ $$attempt -le $$max_attempts ]; do \
		IP=$$(kubectl get ingress httpbin -o jsonpath='{.status.loadBalancer.ingress[0].ip}' --kubeconfig="$$KUBECONFIG_PATH" 2>/dev/null || echo ""); \
		if [ -n "$$IP" ]; then \
			echo "Ingress IP assigned: $$IP"; \
			echo "Testing ingress endpoint..."; \
			sleep 2; \
			if curl -s -f http://$$IP/hostname > /dev/null; then \
				echo "Response: $$(curl -s http://$$IP/hostname)"; \
				echo "Success! Ingress test passed."; \
				exit 0; \
			else \
				echo "Curl failed, retrying..."; \
			fi; \
		fi; \
		echo "Waiting... (attempt $$attempt/$$max_attempts)"; \
		sleep 5; \
		attempt=$$((attempt + 1)); \
	done; \
	echo "Timeout waiting for Ingress IP or ingress connection."; \
	exit 1

clean-test: ## Delete test application resources
	@KUBECONFIG_PATH=$$(terraform output -raw kubeconfig_path 2>/dev/null); \
	if [ -n "$$KUBECONFIG_PATH" ] && [ -f "$$KUBECONFIG_PATH" ]; then \
		echo "Deleting test kustomize resources..."; \
		kubectl delete -k test/kustomize --kubeconfig="$$KUBECONFIG_PATH" --ignore-not-found; \
	fi

lint: ## Run format check, validate, and tflint
	@echo "Checking formatting (terraform fmt -check)..." \
	&& terraform fmt -check || (echo "Formatting issues found. Run 'make format' to fix." && exit 1)
	@echo "Validating configuration (terraform validate)..." \
	&& terraform validate
	@echo "Linting with tflint..." \
	&& tflint --init \
	&& tflint

format: ## Format all Terraform configuration files
	@echo "Formatting Terraform files..."
	terraform fmt

build-node-image: ## Build a Kind node-image from Kubernetes release binaries (requires KUBERNETES_VERSION)
	@echo "Building node-image from Kubernetes release binaries for version $(KUBERNETES_VERSION)..."
	kind build node-image --type release --image=$(IMAGE_NAME) $(KUBERNETES_VERSION)
