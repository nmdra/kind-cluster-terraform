# kind-cluster-terraform

Terraform configuration to provision a **local Kind (Kubernetes in Docker) cluster** for personal development and testing workflows.

This setup optionally enables **Ingress and LoadBalancer support** using **cloud-provider-kind**, which runs as a Docker container alongside the Kind cluster.

> [!NOTE]  
> Starting from **cloud-provider-kind v0.9.0**, Ingress is supported natively. No third-party ingress controllers (such as NGINX) are required by default.


## Features

- Local Kubernetes cluster using **Kind**
- Optional **Ingress + LoadBalancer** support via **cloud-provider-kind**
- cloud-provider-kind runs as a **Docker container**
- Configurable worker node count, Kubernetes feature gates, and runtime config
- Auto-generated cluster names using `random_pet` (with optional override)
- Automatic kubectl context switching after cluster creation
- Fully controlled using Terraform variables
- Ideal for local development and testing

## How It Works

- By default, the Kind cluster is created **without** Ingress or LoadBalancer support.
- If no `kind_cluster_name` is provided, a random name is generated using `random_pet`.
- When the `enable_ingress_lb` variable is set to `true`:
  - The cluster name is suffixed with `-ing`
  - `cloud-provider-kind` is automatically deployed as a Docker container
  - Kubernetes `Service` resources of type `LoadBalancer` are supported
  - Ingress works out-of-the-box without installing a third-party controller
- After creation, the kubectl context is automatically set to the new cluster.

## Usage

The easiest way to manage this infrastructure is via the provided `Makefile`:

```bash
# Display all available commands
make help

# Initialize Terraform
make init

# Provision cluster using variables defined in terraform.tfvars
make up

# Provision cluster, overriding variables (e.g., enable Ingress & LoadBalancer)
make up ENABLE_INGRESS_LB=true WORKER_NODE_COUNT=2

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

👉 **[Test Ingress](./test/README.md)** for example workloads and manual verification steps.

## Inputs

| Name | Description | Type | Default |
|------|-------------|------|---------|
| `kind_cluster_name` | The name of the cluster. If empty, a random name is generated. | `string` | `""` |
| `kind_cluster_node_image` | The node image/version to use. Supports custom built local tags. | `string` | `"kindest/node:v1.35.0"` |
| `kind_cluster_config_path` | The location where this cluster's kubeconfig will be saved to. | `string` | `"~/.kube/config"` |
| `worker_node_count` | The number of worker nodes. Enforces $\ge 0$. | `number` | `1` |
| `enable_feature_gates` | Flag to enable custom Kubernetes feature gates configured in `feature_gates`. | `bool` | `false` |
| `feature_gates` | Map of Kubernetes feature gates to enable/disable. Only applied if `enable_feature_gates` is true. | `map(bool)` | `{}` |
| `enable_runtime_config` | Flag to enable custom Kubernetes runtime configurations configured in `runtime_config`. | `bool` | `false` |
| `runtime_config` | Kubernetes runtime configuration to enable/disable specific API groups. Only applied if `enable_runtime_config` is true. | `map(string)` | `{}` |
| `enable_ingress_lb` | Enable ingress and load balancer support. | `bool` | `false` |
| `ingress_port_mappings` | List of control-plane port mappings. Enforces ports inside `1-65535` and protocols `TCP`/`UDP`. | `list(object)` | See [variables.tf](./variables.tf) |
| `docker_host` | The Docker daemon socket or TCP host URI. Used by the Docker provider. | `string` | `"unix:///var/run/docker.sock"` |

### Input Validations

To prevent runtime errors, the configuration validates:
- **Node image reference**: Ensures `kind_cluster_node_image` is a valid Docker image reference containing a tag (e.g., `kindest/node:vX.Y.Z` or a custom built tag).
- **Worker node count**: Enforces that `worker_node_count` is a non-negative integer.
- **Port ranges**: Validates that all ports are between 1 and 65535, and protocols are `TCP` or `UDP`.

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
| [docker](https://registry.terraform.io/providers/kreuzwerker/docker) | `~> 4.4.0` |
| [random](https://registry.terraform.io/providers/hashicorp/random) | `~> 3.9.0` |

Additionally, the following tools must be installed locally:

* Docker
* Terraform
* Kind
* kubectl

## Resources & References

* [Terraform Kind Provider](https://registry.terraform.io/providers/tehcyx/kind/latest/docs)
* [What is TFLint?](https://spacelift.io/blog/what-is-tflint)
* [Configuring Kind with Ingress (NGINX example)](https://nickjanetakis.com/blog/configuring-a-kind-cluster-with-nginx-ingress-using-terraform-and-helm)
* [Kind Ingress Documentation](https://kind.sigs.k8s.io/docs/user/ingress)

