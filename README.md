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

```bash
# Create cluster with ingress & load balancer disabled
terraform apply

# Create cluster with ingress & load balancer enabled
terraform apply -var="enable_ingress_lb=true"
```

See [`terraform.tfvars.example`](./terraform.tfvars.example) for a complete example of variable values.

👉 **[Test Ingress](./test/README.md)** for example workloads and verification steps.

## Inputs

| Name | Description | Type | Default |
|------|-------------|------|---------|
| `kind_cluster_name` | The name of the cluster. If empty, a random name is generated. | `string` | `""` |
| `kind_cluster_node_image` | The node image/version to use. | `string` | `"kindest/node:v1.35.0"` |
| `kind_cluster_config_path` | The location where this cluster's kubeconfig will be saved to. | `string` | `"~/.kube/config"` |
| `worker_node_count` | The number of worker nodes to create in the cluster. | `number` | `1` |
| `runtime_config` | Kubernetes runtime configuration to enable/disable specific API groups. | `map(string)` | n/a |
| `feature_gates` | Map of Kubernetes feature gates to enable/disable. | `map(bool)` | n/a |
| `enable_ingress_lb` | Enable ingress and load balancer support. | `bool` | `false` |
| `ingress_port_mappings` | List of port mappings to expose on the control-plane node. | `list(object)` | See [variables.tf](./variables.tf) |

## Outputs

| Name | Description |
|------|-------------|
| `kubeconfig_path` | Path to the kubeconfig file for the Kind cluster |
| `cluster_name` | Name of the Kind cluster |

## Requirements

| Name | Version |
|------|---------|
| Terraform | `~> 1.14.0` |
| [kind](https://registry.terraform.io/providers/tehcyx/kind) | `~> 0.11.0` |
| [docker](https://registry.terraform.io/providers/kreuzwerker/docker) | `~> 3.6.2` |
| [null](https://registry.terraform.io/providers/hashicorp/null) | `~> 3.2.4` |
| [random](https://registry.terraform.io/providers/hashicorp/random) | `~> 3.7.2` |

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
