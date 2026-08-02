# kind-cluster-terraform

Terraform configuration for a local Kind (Kubernetes in Docker) cluster. This project is for personal development and testing workflows.

You can enable Ingress and LoadBalancer support with **cloud-provider-kind**. It runs as a Docker container next to the Kind cluster.

> [!NOTE]
> From **cloud-provider-kind v0.9.0**, Ingress is supported natively. No third-party ingress controller (for example, NGINX) is required by default.

## Features

- Local Kubernetes cluster with **Kind**
- Optional Ingress and LoadBalancer support with **cloud-provider-kind**
- cloud-provider-kind runs as a **Docker container**
- Configurable control-plane and worker node counts, including HA setups
- Kubernetes feature gates and runtime configuration
- Auto-generated cluster names with `random_pet` (you can override the name)
- Automatic kubectl context switching, with cleanup on destruction
- All configuration is managed with Terraform variables
- For local development and testing

## How It Works

- By default, the Kind cluster has no Ingress or LoadBalancer support.
- If `kind_cluster_name` is empty, Terraform generates a random name with `random_pet`.
- When `enable_ingress_lb` is `true`:
  - The cluster name gets the suffix `-ing`.
  - Terraform deploys cloud-provider-kind as a Docker container.
  - You can use services of type `LoadBalancer`.
  - Ingress works by default. No third-party controller is required.
- After creation, kubectl uses the new cluster as its context.
- When Terraform destroys the cluster, it removes the context, cluster, and user entries from your kubeconfig.

## Usage

The `Makefile` is the easiest way to manage this infrastructure:

```bash
# Display all available commands
make help

# Initialize Terraform
make init

# Provision cluster using variables defined in terraform.tfvars
make up

# Provision cluster, overriding variables (e.g., enable Ingress & LoadBalancer)
make up ENABLE_INGRESS_LB=true WORKER_NODE_COUNT=2

# Provision an HA cluster with 3 control-plane nodes
make up CONTROL_PLANE_NODE_COUNT=3 WORKER_NODE_COUNT=2

# Build a custom Kind node-image from Kubernetes release binaries
make build-node-image KUBERNETES_VERSION=v1.31.0

# Provision the cluster using the custom-built image
make up KIND_CLUSTER_NODE_IMAGE=kindest/node:v1.31.0

# Check the status of Kind containers, the cluster, and Kubernetes nodes
make status

# Deploy the test application (httpbin) and verify Ingress routing
make test

# Destroy the cluster and clean up resources
make down

# Format and lint Terraform files
make lint
make format
```

For custom configurations, see [`terraform.tfvars.example`](./terraform.tfvars.example).

[**Test Ingress**](./test/README.md) contains example workloads and steps to verify the Ingress.

## Inputs

| Name | Description | Type | Default |
|------|-------------|------|---------|
| `kind_cluster_name` | The name of the cluster. If empty, Terraform generates a random name. | `string` | `""` |
| `kind_cluster_node_image` | The node image to use. You can also use a locally built tag. | `string` | `"kindest/node:v1.35.0"` |
| `kind_cluster_config_path` | The location where the kubeconfig file is saved. | `string` | `"~/.kube/config"` |
| `worker_node_count` | The number of worker nodes. Must be 0 or more. | `number` | `1` |
| `control_plane_node_count` | The number of control-plane nodes. Use `1` for a standard cluster or `3+` for HA. Must be 1 or more. | `number` | `1` |
| `enable_feature_gates` | Set `true` to enable the feature gates in `feature_gates`. | `bool` | `false` |
| `feature_gates` | Feature gates to enable or disable. If `enable_feature_gates` is `true`, Terraform applies these gates. | `map(bool)` | `{}` |
| `enable_runtime_config` | Set `true` to enable the runtime configuration in `runtime_config`. | `bool` | `false` |
| `runtime_config` | Runtime configuration for specific API groups. If `enable_runtime_config` is `true`, Terraform applies these entries. | `map(string)` | `{}` |
| `enable_ingress_lb` | Set `true` to enable Ingress and LoadBalancer support. | `bool` | `false` |
| `ingress_port_mappings` | Control-plane port mappings. Ports must be between 1 and 65535. Protocols must be `TCP` or `UDP`. | `list(object)` | See [variables.tf](./variables.tf) |
| `docker_host` | The Docker daemon socket or TCP host URI. The Docker provider uses it. | `string` | `"unix:///var/run/docker.sock"` |

### Input Verification

To prevent runtime errors, Terraform verifies:

- **Node image**: `kind_cluster_node_image` must be a valid Docker image reference with a tag (for example, `kindest/node:vX.Y.Z` or a locally built tag).
- **Worker node count**: `worker_node_count` must be 0 or more.
- **Control-plane node count**: `control_plane_node_count` must be 1 or more.
- **Port ranges**: All ports must be between 1 and 65535. Protocols must be `TCP` or `UDP`.

## Outputs

| Name | Description |
|------|-------------|
| `kubeconfig_path` | Path to the kubeconfig file for the Kind cluster |
| `cluster_name` | Name of the Kind cluster |

## Requirements

| Name | Version |
|------|---------|
| Terraform | `~> 1.15.0` |
| [kind](https://registry.terraform.io/providers/tehcyx/kind) | `~> 0.11.0` |
| [docker](https://registry.terraform.io/providers/kreuzwerker/docker) | `~> 4.5.0` |
| [random](https://registry.terraform.io/providers/hashicorp/random) | `~> 3.9.0` |

The following tools must be installed on your machine:

* Docker
* Terraform
* Kind
* kubectl

## Resources & References

* [Terraform Kind Provider](https://registry.terraform.io/providers/tehcyx/kind/latest/docs)
* [What is TFLint?](https://spacelift.io/blog/what-is-tflint)
* [Configuring Kind with Ingress (NGINX example)](https://nickjanetakis.com/blog/configuring-a-kind-cluster-with-nginx-ingress-using-terraform-and-helm)
* [Kind Ingress Documentation](https://kind.sigs.k8s.io/docs/user/ingress)
