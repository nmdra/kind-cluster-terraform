# kind-cluster-terraform

This Terraform configuration manages one local Kind (Kubernetes in Docker) cluster. Use this project for development and testing, not for production workloads.

You can enable Ingress, Gateway API, and LoadBalancer support with **cloud-provider-kind**. It runs as a Docker container next to the cluster. No third-party Ingress controller is required for the bundled Ingress workflow.

## Features

- Configurable control-plane and worker counts, including HA configurations
- Digest-pinned Kubernetes v1.37.0 node image, with support for custom tagged node images
- Optional Kubernetes feature gates, runtime configuration, kubeadm patches, and host mounts
- Optional loading of local application images onto cluster nodes
- Cluster names generated with `random_pet`, or an explicit name
- Canonical context output for kubectl, with a compatible short-name alias
- Optional cloud-provider-kind v0.12.0 with a selectable Gateway channel

## How It Works

- Terraform manages one cluster. If `kind_cluster_name` is empty, Terraform generates a random name.
- Ingress and LoadBalancer support are off by default. If `enable_ingress_lb=true`, Terraform adds the suffix `-ing` to the name and starts cloud-provider-kind.
- The default Gateway channel is `standard`. The controller installs Gateway CRDs and provides Ingress-to-Gateway translation. The `disabled` channel also disables bundled Ingress, but not LoadBalancer Services.
- Cluster creation selects the short-name alias for kubectl compatibility. `cluster_context` reports the provider's canonical context, normally `kind-<cluster_name>`. Repository automation explicitly uses this output and `kubeconfig_path`. It does not use the current context.
- Cluster destruction removes this cluster and its kubeconfig entries, including the short-name alias. It does not restore a previously selected context.

**Controller scope:** cloud-provider-kind watches all Kind clusters on the Docker daemon, not only this Terraform cluster. Its fixed container name also prevents each independent copy of this configuration from owning a controller on the same daemon. The socket mount gives the controller access to the host Docker daemon. Use a disposable Docker environment for networking acceptance tests.

## Documentation

| Guide | Use it for |
| --- | --- |
| [Full user guide](docs/user-guide.md) | Prerequisites, first cluster, explicit contexts, configuration, application image loading, networking, upgrades, troubleshooting, and cleanup |
| [Test guide](test/README.md) | Static checks, isolated cluster tests, host-wide networking tests, diagnostic files, and recorded live results |
| [Configuration example](terraform.tfvars.example) | Input examples, opt-in scheduling, kubeadm patches, and mounts |
| [Known Gateway issue #3](https://github.com/nmdra/kind-cluster-terraform/issues/3) | Unresolved Gateway proxy restart recovery failure and criteria for follow-up work |

## Usage

**For a new checkout with no existing state**, start with the [first-cluster walkthrough](docs/user-guide.md#create-your-first-cluster). If this checkout already manages a cluster, use the [upgrade procedure](docs/user-guide.md#upgrade-or-replace-a-cluster) instead.

Install the tools in [Requirements](#requirements). Only if no private variables file exists, copy [`terraform.tfvars.example`](./terraform.tfvars.example). Then edit the copy before you create a plan:

```bash
if [ ! -e terraform.tfvars ]; then
  cp terraform.tfvars.example terraform.tfvars
fi
# Edit terraform.tfvars. Prefer a dedicated kubeconfig for this cluster.
terraform init -lockfile=readonly
terraform validate
make test-plan
terraform plan
# After reviewing and approving the infrastructure change:
terraform apply
make status
```

`terraform apply` asks for approval of its new plan. **`make up` and `make down` use automatic approval.** Do not use them to bypass review of a replacement or destruction plan. If you enable or disable `enable_ingress_lb`, Terraform adds or removes the `-ing` name suffix and replaces the cluster.

### Command reference

| Command | Effect |
| --- | --- |
| `make help` | List convenience targets |
| `make init` | Initialize providers without creating a cluster |
| `make status` | Read state outputs, Docker status, and cluster nodes in the explicit context |
| `make test-plan` | Run 22 mocked plan tests without private tfvars or existing state |
| `make lint` | Run formatting checks, Terraform validation, and TFLint |
| `make format` | Rewrite Terraform formatting. Review the diff afterward |
| `make up` | Apply with automatic approval. Can create or replace the cluster |
| `make test` | Apply httpbin fixtures to `default` in the state-selected development cluster and check Ingress |
| `make clean-test` | Delete those development-cluster fixtures |
| `make test-upgrade` | Create, replace, and destroy a disposable cluster. Requires explicit approval and `RUN_CLUSTER_TESTS=1` |
| `make down` | Destroy the state-managed cluster with automatic approval |

Make overrides such as `WORKER_NODE_COUNT=2` affect only that invocation. Save recurring choices in `terraform.tfvars` and review the same values in the plan. Networking tests require additional opt-ins and daemon isolation. Before you run these tests, see the test guide.

Core acceptance passed. The Gateway proxy restart HTTP check still blocks full networking acceptance. [issue #3](https://github.com/nmdra/kind-cluster-terraform/issues/3) tracks this failure. The assertion is not skipped. This project includes no workaround or custom controller image.

### Custom node images

A **node image** contains Kubernetes and the node runtime. It is not an application image. The published default is:

```text
kindest/node:v1.37.0@sha256:a1ed56cfb0e7b93589bdf97c8cd566405a265939e3620fc4f5de89adff580ae5
```

For a local release-binary build, use the host Kind CLI v0.33.0:

```bash
make build-node-image KUBERNETES_VERSION=v1.37.0 IMAGE_NAME=kindest/node:v1.37.0-local
terraform plan -var='kind_cluster_node_image=kindest/node:v1.37.0-local'
# After approving cluster replacement:
make up KIND_CLUSTER_NODE_IMAGE=kindest/node:v1.37.0-local
```

A local build uses a tag, not the published node image digest. The Kind provider embeds Kind v0.33.0. It does not execute the host Kind CLI. Updating that executable alone does not upgrade the provider.

### Local application images

`local_images` is a `set(string)` and defaults to `[]`. Before you apply, build application images in the same local Docker daemon that supplies the Kind nodes. Loading does not pull missing application images.

```bash
docker build -t myapp:dev-001 /absolute/path/to/myapp
terraform plan -var='local_images=["myapp:dev-001"]'
# After approval, apply with the same input:
terraform apply -var='local_images=["myapp:dev-001"]'
```

For recurring use, set `local_images` in `terraform.tfvars` instead of using a one-time CLI override. See the [application image walkthrough](docs/user-guide.md#load-local-application-images), which includes workload pull policies.

Use versioned, immutable tags for normal workflows. Use `imagePullPolicy: Never` or `IfNotPresent` in local workloads as appropriate. Terraform loads each application image onto all nodes and reloads it after cluster replacement. Removing a load resource does not unload the application image from nodes. Provider refresh accepts an application image that is present on any one node. It does not compare a rebuilt local application image ID. Thus, provider refresh does not provide full application image drift reconciliation.

For an intentional reload of a rebuilt tag already listed in `local_images`:

```bash
terraform apply -replace='kind_load.local_images["myapp:dev"]'
```

Restart or recreate the affected pods separately so they use the new application image.

### Kubernetes configuration

`kubeadm_config_patches` applies kubeadm YAML patches to nodes. Use `kubeadm.k8s.io/v1beta4` and name/value lists for extra arguments, as shown in the example. `extra_mounts` mounts host paths into nodes. Where possible, use read-only mounts. These settings apply when you create the cluster. They do not provide in-place upgrades.

For the opt-in scheduling profile, enable `GenericWorkload=true` and `scheduling.k8s.io/v1beta1=true` through the two enable flags. Kubernetes 1.37 does not include the old `GangScheduling` gate or serve the old scheduling v1alpha1 API. `OpportunisticBatching` is beta and enabled by default. Thus, the example does not repeat it.

## Inputs

| Name | Description | Type | Default |
|------|-------------|------|---------|
| `kind_cluster_name` | Cluster name. If empty, generate a random name | `string` | `""` |
| `kind_cluster_node_image` | Tagged node image, optionally pinned with a SHA-256 digest | `string` | Digest-pinned v1.37.0 image shown above |
| `kind_cluster_config_path` | Kubeconfig file location | `string` | `"~/.kube/config"` |
| `worker_node_count` | Worker node count, at least 0 | `number` | `1` |
| `control_plane_node_count` | Control-plane node count, at least 1. For HA, use 3+ | `number` | `1` |
| `local_images` | Application images already present in local Docker for loading onto nodes | `set(string)` | `[]` |
| `enable_feature_gates` | Apply `feature_gates` | `bool` | `false` |
| `feature_gates` | Feature gate values | `map(bool)` | `{}` |
| `enable_runtime_config` | Apply `runtime_config` | `bool` | `false` |
| `runtime_config` | API runtime configuration | `map(string)` | `{}` |
| `kubeadm_config_patches` | kubeadm YAML patches | `list(string)` | `[]` |
| `extra_mounts` | Host-to-node mounts with optional read-only, propagation, and SELinux settings | `list(object)` | `[]` |
| `enable_ingress_lb` | Start cloud-provider-kind | `bool` | `false` |
| `cloud_provider_kind_image` | Controller image | `string` | `"registry.k8s.io/cloud-provider-kind/cloud-controller-manager:v0.12.0"` |
| `cloud_provider_kind_gateway_channel` | `standard`, `experimental`, or `disabled`. The disabled channel also skips bundled Ingress | `string` | `"standard"` |
| `ingress_port_mappings` | Port mappings for the first control-plane node. These do not expose the Envoy proxy | `list(object)` | TCP 80→30082 and 443→30443 |
| `docker_host` | Docker provider endpoint. Does not provide general remote-Docker support | `string` | `"unix:///var/run/docker.sock"` |

### Input Verification

- Node images require a tag. Validation supports registry hosts with ports and an optional `@sha256:` followed by 64 hexadecimal digits. It rejects whitespace, empty tags, and malformed digests.
- Local application image entries and controller image strings must not be blank.
- The Gateway channel must be one of the three values above.
- Validation checks node counts and port ranges. Port protocols must be TCP or UDP.

## cloud-provider-kind capabilities and limits

| Capability | Adoption in this upgrade |
|------------|--------------------------|
| LoadBalancer Services | Retains the existing capability. An optional smoke test checks traffic after port additions. v0.12.0 recreation applies when ports are published on the host |
| Gateway/HTTPRoute | Retains the existing capability, which is not new in v0.12.0. Retains the standard channel with a separate smoke test |
| Gateway API v1.6.1 conformance and supportedFeatures reporting | Includes v0.12.0 upstream improvements. Does not claim project-level conformance certification |
| Ingress-to-Gateway translation | Retains the existing bundled workflow. The controller installs CRDs and generates Gateway/HTTPRoute resources |
| Added Service ports / Gateway listeners | Optional checks cover added ports. Published host ports require proxy recreation. Direct networking can update in place. This does not guarantee arbitrary port removal or mutation |
| WebSocket and runtime detection fixes, version command | Inherits these from v0.11.x. Does not add non-Docker runtime support to this project |
| ExternalAuth HTTPRoute filter | Requires opt-in and the experimental channel. Uses upstream fail-closed behavior. Authorization deployments remain outside acceptance scope |
| Envoy template overrides | Documents advanced follow-up work through upstream `--loadbalancer-config-dir` and `dump-loadbalancer-templates DIR`. Adds no template mount or input here |
| Linux tunnel and host port mapping | Documents follow-up work only. Makes no automatic privilege or host-network changes |

Live core-cluster acceptance passed. Ingress, LoadBalancer added-port traffic, and Gateway added-listener traffic also passed. Gateway proxy restart recovery failed its HTTP check. [issue #3](https://github.com/nmdra/kind-cluster-terraform/issues/3) still blocks full networking acceptance. See [the live test result](test/README.md#recorded-live-acceptance-result) for scope and limits.

Ingress translation can differ from other controllers, particularly in wildcard-host matching and shared namespace TLS/listener behavior. Before you move existing Ingress rules, review [upstream translation semantics](https://github.com/kubernetes-sigs/cloud-provider-kind/blob/v0.12.0/pkg/ingress/README.md).

By default, this configuration passes no connectivity override. Upstream selects connectivity automatically. If you explicitly set **either** `--enable-lb-port-mapping` or `--enable-lb-tunnel`, **even to false**, you disable automatic detection. The controller's socket mount alone does not prove access to the host interfaces that Linux tunnel mode needs. This configuration does not expose these flags or add privileges. Static Kind control-plane port mappings do not expose the controller's Envoy proxy containers. Direct container IP reachability depends on the host platform. Where supported, use only an actual published host port that you have discovered.

## Outputs

| Name | Description |
|------|-------------|
| `kubeconfig_path` | Expanded kubeconfig file path |
| `cluster_name` | Kind cluster name |
| `cluster_context` | Canonical context for kubectl, as reported by the provider |

To select the cluster explicitly for manual commands:

```bash
KUBECONFIG_PATH=$(terraform output -raw kubeconfig_path) &&
CLUSTER_CONTEXT=$(terraform output -raw cluster_context) &&
kubectl --kubeconfig="$KUBECONFIG_PATH" --context="$CLUSTER_CONTEXT" get nodes
```

## Requirements

| Name | Version |
|------|---------|
| Terraform | `~> 1.15.0` (unchanged) |
| [kind provider](https://registry.terraform.io/providers/tehcyx/kind) | `~> 0.13.0` |
| [docker provider](https://registry.terraform.io/providers/kreuzwerker/docker) | `~> 4.6.0` |
| [random provider](https://registry.terraform.io/providers/hashicorp/random) | `~> 3.9.1` |

The upgrade targets exact lock selections 0.13.0, 4.6.0, and 3.9.1. Install Docker, Terraform 1.15.x, and kubectl. kubectl 1.37 is the acceptance target for this Kubernetes 1.37 configuration. It is not a test result from this upgrade. Use host Kind CLI v0.33.0 for custom node image builds and test tooling. Provider build toolchain versions do not require a local Go installation.

The default configuration assumes a local Docker daemon with the standard socket available to cloud-provider-kind. The published node image supports amd64 and arm64 on matching host platforms. This upgrade does not verify other host platforms, remote daemons, or rootless networking.

## Migration and rollback

**Changing the node image destroys and replaces the cluster. Kubernetes workloads and node-local data do not survive replacement.** Provider upgrades can also affect the plan. Do not run `make up` against existing state until you review the changes. This command uses automatic approval.

Local `terraform.tfvars`, `*.auto.tfvars`, and command-line values override the new defaults. Before you create a plan, review existing image, feature-gate, and runtime-config overrides. This upgrade does not rewrite private configuration files.

1. Back up Terraform state and the kubeconfig file outside the repository. Use the [secure backup example](docs/user-guide.md#upgrade-or-replace-a-cluster) and durable storage. State, kubeconfig, and saved plans can contain credentials. Do not commit them.
2. Export required workload manifests and back up persistent data outside Kind. A Terraform state backup is not a workload backup.
3. Update the configuration and initialize the approved provider selections. Review `terraform plan`, including cluster and controller replacement and application image reloads. Check that an unchanged `random_pet.cluster` does not change the name unexpectedly.
4. Obtain separate approval to destroy the existing development cluster. Only after data recovery steps are ready, apply the plan.
5. Recreate the cluster, redeploy workloads, and verify versions, contexts, local application images, and any enabled networking.

To roll back, select a previously tested provider/node image and recreate the cluster. Then restore workloads and data. Reverting Git or restoring Terraform state does not restore deleted workloads. Neither action provides an in-place Kubernetes downgrade.

## Resources & References

- [Kind v0.33.0 node images](https://github.com/kubernetes-sigs/kind/releases/tag/v0.33.0)
- [Terraform Kind Provider 0.13.0](https://registry.terraform.io/providers/tehcyx/kind/0.13.0/docs)
- [cloud-provider-kind v0.12.0](https://github.com/kubernetes-sigs/cloud-provider-kind/releases/tag/v0.12.0)
- [Gateway and ExternalAuth documentation](https://github.com/kubernetes-sigs/cloud-provider-kind/blob/v0.12.0/docs/user/gateway/gatewayapi.md)
- [kubectl version skew policy](https://kubernetes.io/releases/version-skew-policy/)
