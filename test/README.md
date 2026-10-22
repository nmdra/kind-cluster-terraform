# Cluster and networking tests

Run commands from the repository root. Use Terraform 1.15.x, Docker, host Kind CLI v0.33.0, and kubectl 1.37 for the acceptance matrix. These are acceptance targets. Live tests ran with kubectl 1.36.4 and host Kind CLI 0.32.0, without upgrading host tools. The provider embeds Kind 0.33.0. Core cluster acceptance passed, but the networking matrix did not pass in full; see the recorded result below.

## Static checks

These checks do not create a cluster. Initialize the approved provider selections first.

```bash
terraform fmt -check -recursive
terraform validate
make test-plan
bash -n test/*.sh
shellcheck test/*.sh
kubectl kustomize test/kustomize/gateway
kubectl kustomize test/kustomize/loadbalancer
```

`make test-plan` copies only Terraform configuration, the provider lockfile, and the test file into a temporary root. It does not load local tfvars or existing state, and it clears ambient Terraform variable and command-line overrides. It uses mock providers and plan-only runs. It covers image validation, defaults, canonical context output, optional image loads, and controller inputs. It cannot prove real Kubernetes startup, image loading, or replacement cleanup.

## Isolated cluster acceptance

**These tests create, replace, and destroy disposable infrastructure. Obtain approval before running them.** The explicit `RUN_CLUSTER_TESTS=1` gate is required before any apply.

```bash
RUN_CLUSTER_TESTS=1 make test-upgrade
RUN_CLUSTER_TESTS=1 bash test/test_kubeadm_patches.sh
RUN_CLUSTER_TESTS=1 bash test/test_admission_control.sh
```

The shared helper copies root Terraform configuration and the lockfile into a temporary test root. It does not copy user tfvars or root state. Each run uses separate state, a unique cluster name, an absolute dedicated kubeconfig, and no static host port mappings. Kubernetes calls target the canonical context explicitly. Do not adapt the scripts to apply against your active root state.

The upgrade scenario checks:

- Kubernetes server and kubelet v1.37.0, Ready nodes, and an empty second plan
- Canonical context and compatible short alias, with an unrelated context selected
- A uniquely tagged local image running with `imagePullPolicy: Never` on every node
- The same image checks after replacement of `kind_cluster.default` under the same name
- Opt-in GenericWorkload scheduling API discovery under `scheduling.k8s.io/v1beta1`

The patch tests check node labels and the API-server admission configuration. Kubeadm v1beta4 extra arguments use name/value lists. The admission test explicitly enables `ManifestBasedAdmissionControlConfig` to exercise gate forwarding even though the gate is beta/default-on in Kubernetes 1.37.

An EXIT trap destroys only the test root's resources and preserves the original failure status. If destruction fails, the temporary root is retained with a warning. Inspect its diagnostics and state before manual cleanup. Do not remove unrelated containers or images. Pre-existing Docker images must not be deleted.

## Optional networking acceptance

Networking is a separate opt-in under `TEST_INGRESS=1`, in addition to `RUN_CLUSTER_TESTS=1`. Use a **disposable Docker environment with no unrelated Kind clusters**. cloud-provider-kind watches all clusters on its daemon and installs Gateway CRDs. The test must refuse to take over an existing `cloud-provider-kind` container.

After separate infrastructure approval, run the networking matrix with all three explicit opt-ins:

```bash
RUN_CLUSTER_TESTS=1 TEST_INGRESS=1 DISPOSABLE_DOCKER_ENVIRONMENT=1 make test-upgrade
```

The upgrade script requires `jq`, `curl`, `make`, and GNU `timeout` as well as Terraform, kubectl, and local Docker. The shared cluster-test helper requires `timeout` for bounded diagnostic collection. `DISPOSABLE_DOCKER_ENVIRONMENT=1` is an acknowledgment, not a mechanism that creates an isolated daemon. Supply the disposable environment yourself. The preflight refuses existing Kind clusters and an existing fixed-name controller.

The networking scenario uses the explicit v0.12.0 controller image and standard Gateway channel. It verifies the published image manifest for the host architecture before apply, then compares the running container's image ID with the platform manifest's config digest. The published v0.12.0 image prints a blank version suffix, so the version command is recorded but is not sufficient proof of image identity. It must not substitute a controller version or add privileges to bypass a failure.

The intended matrix includes:

| Scenario | Checks |
|----------|--------|
| Controller | Published platform image identity, startup/version logs, Gateway CRD establishment |
| Direct Gateway/HTTPRoute | GatewayClass acceptance, Gateway Accepted/Programmed, route Accepted/ResolvedRefs, HTTP content |
| Ingress | Bundled Ingress-to-Gateway translation, tested separately |
| LoadBalancer Service | HTTP content before and after adding a second Service port |
| Gateway listener addition | HTTP content after adding a listener and matching route parent section |
| Proxy restart | Traffic recovery with finite timeouts and failure diagnostics |

Gateway/HTTPRoute and Ingress support existed before v0.12.0. The added-port proxy recreation is a v0.12.0 change for host-published ports. Direct networking can update Envoy in place. The test requires recreation only when the existing proxy publishes ports, and checks HTTP traffic in both modes. The checks do not certify arbitrary port removal/mutation, experimental ExternalAuth, custom Envoy templates, Linux tunnel activation, rootless networking, or other host platforms.

The direct Gateway fixture in `test/kustomize/gateway` and Service fixture in `test/kustomize/loadbalancer` use their own namespaces. They are not part of the Ingress kustomization. Cleanup removes fixtures and the Ingress translator's generated `default/kind-ingress-gateway`, waits for exact cluster-owned proxies to disappear, and then destroys the controller and cluster. Unrelated containers do not block cleanup and are never removed. Report leftovers instead of deleting containers owned by another user or cluster.

Direct proxy container IPs might not be reachable on your platform. Use an actual discovered published host port only when the selected controller mode supports one. Static Kind control-plane mappings do not expose Envoy proxies. Neither `--enable-lb-port-mapping` nor `--enable-lb-tunnel` is set by this configuration: setting either, even to false, disables upstream automatic connectivity detection. The socket mount alone does not supply the host interface access needed for tunnel mode.

## Recorded live acceptance result

The Gateway proxy restart failure remains unresolved and is tracked in [issue #3](https://github.com/nmdra/kind-cluster-terraform/issues/3). The networking suite keeps its failure assertion; no workaround or custom controller image is included in this upgrade.

| Check | Result |
|-------|--------|
| Kubernetes v1.37.0, Ready nodes, scheduling API, contexts, empty baseline plans | Passed |
| Local image on both nodes before and after same-name cluster replacement | Passed |
| Kubeadm patches and admission control | Passed; admission cleanup needed one manual retry before a successful full rerun |
| Controller v0.12.0 platform image identity, Gateway CRDs and GatewayClass | Passed |
| Ingress translation and HTTP routing | Passed |
| LoadBalancer HTTP on original port 80 and added port 8081 | Passed |
| Gateway/HTTPRoute HTTP before and after adding listener 8081 | Passed |
| Gateway proxy restart recovery | Failed: port 80 did not return expected HTTP content within the direct-address retry window |
| Final networking plan and random-name assertion | Not reached after the restart failure |
| Final cleanup and protected files | No test containers or test image tags remain; root tfvars/state and user kubeconfig hashes unchanged |

The networking run was interrupted, then resumed on its existing temporary cluster. It was not a successful end-to-end networking run. The direct-address check makes ten attempts with a two-second delay and at most five seconds per request. The saved output does not distinguish a connection failure, an HTTP error, or unexpected content, so the cause of restart recovery failure is not established. No discovered host port was available in the tested direct-network mode. Do not treat Gateway status conditions alone as proof of data-plane recovery.

The user separately approved this Docker daemon despite unrelated non-Kind containers. That approval did not make the daemon disposable. No controller version, privileges, connectivity flags, or Terraform CLI version were changed to bypass the failure.

Host-local evidence: `/tmp/kind-live-upgrade.log`, `/tmp/kind-live-kubeadm.log`, `/tmp/kind-live-admission-rerun.log`, `/tmp/kind-live-networking-final.log`, and `/tmp/kind-live-networking-resume.log`. Failed-run diagnostics remain in `/tmp/kind-tf-test.K27CLhLI/`. These temporary paths are not durable CI artifacts. Future HTTP checks save the last response headers, body, and curl error to the test root to improve failure diagnosis.

## Test Ingress on an existing development cluster

This workflow writes to the cluster in the root Terraform state. It is **not** the isolated acceptance suite. Enable `enable_ingress_lb=true` with Gateway channel `standard` or `experimental`, review the Terraform plan, and approve any replacement first. The `disabled` channel also disables bundled Ingress translation.

```bash
make test
make clean-test
```

Both commands use `cluster_context` and `kubeconfig_path` from Terraform outputs. The smoke test applies the httpbin resources and checks `/hostname` with finite timeouts.

For manual inspection, target both outputs explicitly:

```bash
KUBECONFIG_PATH=$(terraform output -raw kubeconfig_path) &&
CLUSTER_CONTEXT=$(terraform output -raw cluster_context) &&
kubectl --kubeconfig="$KUBECONFIG_PATH" --context="$CLUSTER_CONTEXT" \
  get ingress httpbin -n default
```

A missing IP, unreachable address, or failed controller must be diagnosed, not treated as a passed networking check. Review controller logs and resource status. Ingress translation has wildcard-host and shared namespace TLS/listener semantics that can differ from other Ingress controllers; see the [tagged upstream documentation](https://github.com/kubernetes-sigs/cloud-provider-kind/blob/v0.12.0/pkg/ingress/README.md).
