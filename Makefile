# Default target
.DEFAULT_GOAL := help
REPO_ROOT := $(patsubst %/,%,$(dir $(abspath $(lastword $(MAKEFILE_LIST)))))

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
KUBERNETES_VERSION ?= v1.37.0
IMAGE_NAME ?= kindest/node:$(KUBERNETES_VERSION)

.PHONY: help init up down status test clean-test test-plan test-upgrade lint format build-node-image

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

# Resolve the target from state, never from the user's active kubectl context.
define kube_target
KUBECONFIG_PATH=$$(terraform output -raw kubeconfig_path); \
CLUSTER_CONTEXT=$$(terraform output -raw cluster_context); \
if [ -z "$$CLUSTER_CONTEXT" ] || [ ! -f "$$KUBECONFIG_PATH" ]; then \
	echo "Missing cluster context or kubeconfig. Apply the configuration first." >&2; exit 1; \
fi; \
kube() { kubectl --kubeconfig="$$KUBECONFIG_PATH" --context="$$CLUSTER_CONTEXT" --request-timeout=15s "$$@"; }; \
kube config get-contexts "$$CLUSTER_CONTEXT" -o name | grep -Fx -- "$$CLUSTER_CONTEXT" >/dev/null
endef

status: ## Show cluster status using the context reported by Terraform
	@set -eu; $(kube_target); \
	echo "Context: $$CLUSTER_CONTEXT"; \
	echo "Kubeconfig: $$KUBECONFIG_PATH"; \
	CLUSTER_NAME=$$(terraform output -raw cluster_name); \
	echo "=== Kind/Docker containers ==="; \
	docker ps --filter "label=io.x-k8s.kind.cluster=$$CLUSTER_NAME" --format '{{.Names}}'; \
	docker ps --filter name='^/cloud-provider-kind$$' --format '{{.Names}}: {{.Status}}'; \
	echo "=== Kubernetes nodes ==="; \
	kube get nodes

test: ## Deploy httpbin and verify Ingress routing in the explicit cluster context
	@set -eu; $(kube_target); \
	diagnose() { \
		kube get pods,service,ingress -n default || true; \
		kube describe ingress httpbin -n default || true; \
		kube get events -n default --sort-by=.lastTimestamp || true; \
	}; \
	trap 'code=$$?; if [ "$$code" -ne 0 ]; then diagnose; fi' EXIT; \
	kube apply -n default -k "$(REPO_ROOT)/test/kustomize"; \
	kube rollout status deployment/httpbin -n default --timeout=180s; \
	attempt=1; \
	while [ $$attempt -le 24 ]; do \
		IP=$$(kube get ingress httpbin -n default -o jsonpath='{.status.loadBalancer.ingress[0].ip}'); \
		if [ -n "$$IP" ]; then \
			if RESPONSE=$$(curl --noproxy '*' -fsS --connect-timeout 2 --max-time 5 "http://$$IP/hostname") && \
				printf '%s' "$$RESPONSE" | grep -q '"hostname"'; then \
				printf 'Ingress passed: %s\n' "$$RESPONSE"; exit 0; \
			fi; \
		fi; \
		sleep 5; attempt=$$((attempt + 1)); \
	done; \
	echo "Timed out waiting for the Ingress address or HTTP response." >&2; exit 1

clean-test: ## Delete httpbin resources from the explicit cluster context
	@set -eu; $(kube_target); \
	kube delete -n default -k "$(REPO_ROOT)/test/kustomize" --ignore-not-found --wait=true --timeout=120s

test-plan: ## Run isolated mock-provider plan tests without local tfvars or state
	bash "$(REPO_ROOT)/test/test_plan.sh"

test-upgrade: ## Run disposable cluster acceptance (requires RUN_CLUSTER_TESTS=1)
	bash "$(REPO_ROOT)/test/test_upgrade.sh"

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
