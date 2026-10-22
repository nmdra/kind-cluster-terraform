# kind-cluster-terraform

Terraform configuration for one local Kind (Kubernetes in Docker) cluster. This project is for development and testing, not production workloads.

You can enable Ingress, Gateway API, and LoadBalancer support with **cloud-provider-kind**. It runs as a Docker container next to the cluster. No third-party Ingress controller is required for the bundled Ingress workflow.

## Features

- Configurable control-plane and worker counts, including HA setups
- Digest-pinned Kubernetes v1.37.0 node image, with custom tagged images supported
- Optional Kubernetes feature gates, runtime configuration, kubeadm patches, and host mounts
- Optional loading of local application images onto cluster nodes
- Generated cluster names with `random_pet`, or an explicit name
- Canonical kubectl context output plus a compatible short-name context alias
- Optional cloud-provider-kind v0.12.0 with a selectable Gateway channel

## How It Works

- Terraform manages a single cluster. An empty `kind_cluster_name` generates a random name.
- Ingress and LoadBalancer support are off by default. With `enable_ingress_lb=true`, the name gets the suffix `-ing` and Terraform starts cloud-provider-kind.
- The default Gateway channel is `standard`. The controller installs Gateway CRDs and provides Ingress-to-Gateway translation. The `disabled` channel also disables bundled Ingress, but not LoadBalancer Services.
- Creation selects a short-name kubectl context for compatibility. `cluster_context` reports the provider's canonical context, normally `kind-<cluster_name>`. Repository automation uses this output and `kubeconfig_path` explicitly, not the current context.
- Destruction removes this cluster and its kubeconfig entries, including the short alias. It does not restore a previously selected context.

**Controller scope:** cloud-provider-kind watches all Kind clusters on the Docker daemon, not just this Terraform cluster. Its fixed container name also prevents independent copies of this configuration from each owning a controller on the same daemon. The socket mount gives it access to the host Docker daemon. Use a disposable Docker environment for networking acceptance tests.

## Usage

Install the tools in [Requirements](#requirements), then review [`terraform.tfvars.example`](./terraform.tfvars.example) and copy the settings you need to `terraform.tfvars`.

```bash
make help
make init

# Review before applying. make up and make down use automatic approval.
terraform plan
make up

# Override selected inputs
make up ENABLE_INGRESS_LB=true WORKER_NODE_COUNT=2
make up CONTROL_PLANE_NODE_COUNT=3 WORKER_NODE_COUNT=2

make status

# Requires cloud-provider-kind with standard or experimental Gateway channel
make test
make clean-test

# Destructive: removes the cluster and its workloads
make down

make lint
make test-plan
make format
```

See [test/README.md](./test/README.md) for isolated acceptance checks, networking limits, and recorded live results. Core acceptance passed, but full networking acceptance remains blocked by the Gateway proxy restart HTTP check, tracked in [issue #3](https://github.com/nmdra/kind-cluster-terraform/issues/3).

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

A local build uses a tag, not the published image digest. The Kind provider embeds Kind v0.33.0; it does not execute the host Kind CLI. Updating that executable alone does not upgrade the provider.

### Local application images

`local_images` is a `set(string)` and defaults to `[]`. Build images in the same local Docker daemon that supplies the Kind nodes before applying. Loading does not pull missing images.

```bash
docker build -t myapp:dev-001 .
terraform apply -var='local_images=["myapp:dev-001"]'
```

Use versioned, immutable tags for normal workflows. Use `imagePullPolicy: Never` or `IfNotPresent` in local workloads as appropriate. Terraform loads each image onto all nodes and reloads it after cluster replacement. Removing a load resource does not unload the image from nodes. Provider refresh accepts an image present on any one node and does not compare a rebuilt local image ID, so it is not full image drift reconciliation.

For an intentional reload of a rebuilt tag already listed in `local_images`:

```bash
terraform apply -replace='kind_load.local_images["myapp:dev"]'
```

Restart or recreate the affected pods separately so they use the new image.

### Kubernetes configuration

`kubeadm_config_patches` applies kubeadm YAML patches to nodes. Use `kubeadm.k8s.io/v1beta4` and name/value lists for extra arguments, as shown in the example. `extra_mounts` mounts host paths into nodes; use read-only mounts where possible. These are cluster-creation settings, not an in-place upgrade mechanism.

For the opt-in scheduling profile, enable `GenericWorkload=true` and `scheduling.k8s.io/v1beta1=true` through the two enable flags. The old `GangScheduling` gate is absent in Kubernetes 1.37; the old scheduling v1alpha1 API is not served. `OpportunisticBatching` is beta and enabled by default, so the example does not repeat it.

## Inputs

| Name | Description | Type | Default |
|------|-------------|------|---------|
| `kind_cluster_name` | Cluster name; empty generates a random name | `string` | `""` |
| `kind_cluster_node_image` | Tagged node image, optionally pinned with a SHA-256 digest | `string` | Digest-pinned v1.37.0 image shown above |
| `kind_cluster_config_path` | Kubeconfig file location | `string` | `"~/.kube/config"` |
| `worker_node_count` | Worker count, at least 0 | `number` | `1` |
| `control_plane_node_count` | Control-plane count, at least 1; use 3+ for HA | `number` | `1` |
| `local_images` | Images already present in local Docker to load onto nodes | `set(string)` | `[]` |
| `enable_feature_gates` | Apply `feature_gates` | `bool` | `false` |
| `feature_gates` | Feature gate values | `map(bool)` | `{}` |
| `enable_runtime_config` | Apply `runtime_config` | `bool` | `false` |
| `runtime_config` | API runtime configuration | `map(string)` | `{}` |
| `kubeadm_config_patches` | kubeadm YAML patches | `list(string)` | `[]` |
| `extra_mounts` | Host-to-node mounts with optional read-only, propagation, and SELinux settings | `list(object)` | `[]` |
| `enable_ingress_lb` | Start cloud-provider-kind | `bool` | `false` |
| `cloud_provider_kind_image` | Controller image | `string` | `"registry.k8s.io/cloud-provider-kind/cloud-controller-manager:v0.12.0"` |
| `cloud_provider_kind_gateway_channel` | `standard`, `experimental`, or `disabled`; disabled also skips bundled Ingress | `string` | `"standard"` |
| `ingress_port_mappings` | First control-plane node port mappings, not Envoy proxy exposure | `list(object)` | TCP 80→30082 and 443→30443 |
| `docker_host` | Docker provider endpoint; not general remote-Docker support | `string` | `"unix:///var/run/docker.sock"` |

### Input Verification

- Node images require a tag. Registry hosts with ports and optional `@sha256:` plus 64 hexadecimal digits are supported. Whitespace, empty tags, and malformed digests are rejected.
- Local image entries and controller image strings must not be blank.
- The Gateway channel must be one of the three values above.
- Node counts and port ranges are checked. Port protocols must be TCP or UDP.

## cloud-provider-kind capabilities and limits

| Capability | Adoption in this upgrade |
|------------|--------------------------|
| LoadBalancer Services | Existing capability, retained; optional smoke test checks traffic after port additions; v0.12.0 recreation applies when ports are host-published |
| Gateway/HTTPRoute | Existing capability, not new in v0.12.0; standard channel retained with a separate smoke test |
| Gateway API v1.6.1 conformance and supportedFeatures reporting | v0.12.0 upstream improvements; no claim of project-level conformance certification |
| Ingress-to-Gateway translation | Existing bundled workflow retained; controller installs CRDs and generates Gateway/HTTPRoute resources |
| Added Service ports / Gateway listeners | Optional checks cover added ports; host-published ports require proxy recreation, while direct networking can update in place. Not a guarantee for arbitrary port removal or mutation |
| WebSocket and runtime detection fixes, version command | Inherited from v0.11.x; no new non-Docker runtime support in this project |
| ExternalAuth HTTPRoute filter | Experimental channel only, opt-in; upstream fail-closed behavior. Authorization deployments remain outside acceptance scope |
| Envoy template overrides | Advanced follow-up via upstream `--loadbalancer-config-dir` and `dump-loadbalancer-templates DIR`; no template mount/input added here |
| Linux tunnel and host port mapping | Documented follow-up only; no automatic privilege or host-network changes |

Live core-cluster acceptance passed. Ingress, LoadBalancer added-port traffic, and Gateway added-listener traffic also passed, but Gateway proxy restart recovery failed its HTTP check. Full networking acceptance remains blocked by [issue #3](https://github.com/nmdra/kind-cluster-terraform/issues/3). See [the live test result](test/README.md#recorded-live-acceptance-result) for scope and limits.

Ingress translation can differ from other controllers, notably in wildcard-host matching and shared namespace TLS/listener behavior. Review [upstream translation semantics](https://github.com/kubernetes-sigs/cloud-provider-kind/blob/v0.12.0/pkg/ingress/README.md) before moving existing Ingress rules.

No connectivity override is passed by default. Upstream selects connectivity automatically. Explicitly setting **either** `--enable-lb-port-mapping` or `--enable-lb-tunnel`, **even to false**, disables automatic detection. The socket-mounted controller does not by itself prove access to host interfaces needed for Linux tunnel mode. This configuration does not expose these flags or add privileges. Static Kind control-plane port mappings do not expose the controller's Envoy proxy containers. Direct container IP reachability depends on the host platform; use only an actual discovered published host port when supported.

## Outputs

| Name | Description |
|------|-------------|
| `kubeconfig_path` | Expanded kubeconfig file path |
| `cluster_name` | Kind cluster name |
| `cluster_context` | Provider-reported canonical kubectl context |

For explicit manual targeting:

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

The upgrade targets exact lock selections 0.13.0, 4.6.0, and 3.9.1. Install Docker, Terraform 1.15.x, and kubectl. kubectl 1.37 is the acceptance target for this Kubernetes 1.37 configuration, not a test result from this upgrade. Use host Kind CLI v0.33.0 for custom node-image builds and test tooling. Provider build toolchain versions do not require a local Go installation.

The default setup assumes a local Docker daemon with the standard socket available to cloud-provider-kind. The published node image supports amd64 and arm64 on matching host platforms. Other host platforms, remote daemons, and rootless networking are not verified by this upgrade.

## Migration and rollback

**Changing the node image destroys and replaces the cluster. Kubernetes workloads and node-local data do not survive replacement.** Provider upgrades can also affect the plan. Do not run `make up` against existing state until you review the changes, because it uses automatic approval.

Local `terraform.tfvars`, `*.auto.tfvars`, and command-line values override the new defaults. Review existing image, feature-gate, and runtime-config overrides before planning; this upgrade does not rewrite private configuration files.

1. Back up Terraform state (`terraform state pull > state-before-upgrade.json`) and the kubeconfig file. Store backups securely; they can contain credentials.
2. Export required workload manifests and back up persistent data outside Kind. A Terraform state backup is not a workload backup.
3. Update the configuration and initialize the approved provider selections. Review `terraform plan`, including cluster/controller replacement and image reloads. Check that an unchanged `random_pet.cluster` does not rotate the name unexpectedly.
4. Obtain separate approval for destruction of the existing development cluster. Apply only after data recovery steps are ready.
5. Recreate, redeploy workloads, and verify versions, contexts, local images, and any enabled networking.

Rollback means selecting a previously tested provider/node image and recreating the cluster, then restoring workloads and data. Reverting Git or restoring Terraform state does not restore deleted workloads and is not an in-place Kubernetes downgrade.

## Resources & References

- [Kind v0.33.0 node images](https://github.com/kubernetes-sigs/kind/releases/tag/v0.33.0)
- [Terraform Kind Provider 0.13.0](https://registry.terraform.io/providers/tehcyx/kind/0.13.0/docs)
- [cloud-provider-kind v0.12.0](https://github.com/kubernetes-sigs/cloud-provider-kind/releases/tag/v0.12.0)
- [Gateway and ExternalAuth documentation](https://github.com/kubernetes-sigs/cloud-provider-kind/blob/v0.12.0/docs/user/gateway/gatewayapi.md)
- [kubectl version skew policy](https://kubernetes.io/releases/version-skew-policy/)
