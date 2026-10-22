# Cluster and networking tests

Run commands from the repository root. Use Terraform 1.15.x, Docker, host Kind CLI v0.33.0, and kubectl 1.37 for the acceptance matrix. These are acceptance targets. Live tests used kubectl 1.36.4 and host Kind CLI 0.32.0. The host tools were not upgraded. The provider embeds Kind 0.33.0. Core cluster acceptance passed. The full networking matrix did not pass. See the recorded result below.

For configuration, installation, normal cluster operations, and recovery procedures, see the [user guide](../docs/user-guide.md). This page covers test scope, approval, evidence, and cleanup. The commands below give instructions for an approved run. They are not evidence that a run passed.

## Prerequisites and approval

- Run from the repository root with Bash and GNU Make. Keep `.terraform.lock.hcl` present and use its approved provider selections. The isolated scripts initialize with `-lockfile=readonly`. They do not upgrade providers.
- Static checks need Terraform, ShellCheck, and kubectl for Kustomize rendering. Provider initialization needs access to the configured provider registry or an approved local cache. `terraform init -backend=false -lockfile=readonly` prepares local provider files without applying resources. Review any initialization change separately.
- All isolated cluster tests need Terraform, kubectl, Docker, and GNU `timeout`. Upgrade acceptance also needs `jq`, `curl`, and `make`. Kubeadm patch acceptance needs `jq`. The scripts use standard Unix utilities and need writable temporary storage.
- Live tests require permission to use the local `/var/run/docker.sock` daemon. They also require enough capacity for one control-plane node and one worker, and access to the required image registries. Upgrade acceptance builds a unique local application image from `busybox:1.37.0`. The configured Kubernetes node image must be available locally or available to pull. Docker socket access grants broad host control. Use only a trusted environment.
- The acceptance targets remain Terraform 1.15.x, host Kind v0.33.0, kubectl 1.37, and Kubernetes v1.37.0. The recorded host Kind and kubectl versions above identify the actual tools used. They are not evidence of a host upgrade. The live test scripts use the provider's embedded Kind, not the host Kind CLI. Host Kind is needed for workflows such as `make build-node-image`.
- Before a live run, obtain approval for its target daemon, resource creation, same-name cluster replacement, fixture changes, and automatic destruction. `RUN_CLUSTER_TESTS=1` authorizes script execution. It does not replace that approval. The scripts use auto-approved Terraform applies and destroys internally.
- Networking needs separate approval for host-wide controller activity and an independently supplied disposable Docker environment. Existing-state `make test` needs approval to change that development cluster. There is no environment-variable safety gate on `make test` or `make clean-test`.

Do not change provider/controller versions, host tools, privileges, connectivity flags, assertions, or the test scope to bypass a failure. Obtain separate approval for those changes and for manual recovery that deletes resources. `make up` and `make down` auto-approve root-state changes. They are not test preflight or isolated cleanup commands.

## Command-to-side-effects matrix

| Command or workflow | Target and side effects | Approval and evidence limits |
|---------------------|-------------------------|------------------------------|
| `terraform fmt -check -recursive`, `terraform validate`, `bash -n test/*.sh`, `shellcheck test/*.sh`, `kubectl kustomize ...` | Checks or renders local files. Validation needs initialized providers. Rendering does not apply manifests. | Does not create or delete clusters. Initialization can download providers and write local metadata. |
| `make test-plan` | Initializes providers and runs mock-provider plans in a temporary test root. Then deletes that root, including on failure. | Does not use live infrastructure or prove runtime behavior. If evidence is needed, capture terminal output. |
| `RUN_CLUSTER_TESTS=1 make test-upgrade` | Creates a two-node disposable cluster, builds and loads a unique application image, replaces the cluster under the same name, then destroys test resources. | Approved isolated baseline only. No host-wide controller unless networking is enabled. |
| `RUN_CLUSTER_TESTS=1 bash test/test_kubeadm_patches.sh` | Creates a two-node test cluster with kubeadm label patches and scheduling discovery enabled, then destroys it. | Approved isolated live run. Uses separate state and kubeconfig. |
| `RUN_CLUSTER_TESTS=1 bash test/test_admission_control.sh` | Writes temporary admission files, mounts them read-only into test nodes, creates a cluster, inspects API-server arguments, then destroys it. | Approved isolated live run. Checks configuration forwarding, not admission-policy enforcement. |
| `RUN_CLUSTER_TESTS=1 TEST_INGRESS=1 DISPOSABLE_DOCKER_ENVIRONMENT=1 make test-upgrade` | Runs baseline replacement, then enables the host-wide controller and tests Ingress, Services, Gateway listeners, and exact Gateway proxy restart. | Requires separate networking approval and a disposable daemon. If proxy removal is unconfirmed, cleanup can retain infrastructure. |
| `make test` | Reads root Terraform outputs and applies httpbin fixtures in `default` on that existing cluster. Leaves fixtures after success or failure. | Not isolated and not plan-only. On failure, prints diagnostics. Use approved fixture cleanup afterward. |
| `make clean-test` | Deletes the httpbin kustomization from the existing cluster selected by root Terraform outputs. | Does not destroy the cluster or controller. Does not perform the isolated suite's cleanup of the generated Gateway and proxies. |

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

`make test-plan` copies only Terraform configuration, the provider lockfile, and the test file into a temporary test root. It does not load local tfvars or existing state. It clears ambient Terraform variable and command-line overrides. It uses mock providers and plan-only runs. It covers image validation, defaults, canonical context output, optional application image loads, and controller inputs. It cannot prove real Kubernetes startup, application image loading, or replacement cleanup.

## Isolated cluster acceptance

**These tests create, replace, and destroy disposable infrastructure. Obtain approval before running them.** The explicit `RUN_CLUSTER_TESTS=1` gate is required before any apply.

```bash
RUN_CLUSTER_TESTS=1 make test-upgrade
RUN_CLUSTER_TESTS=1 bash test/test_kubeadm_patches.sh
RUN_CLUSTER_TESTS=1 bash test/test_admission_control.sh
```

The shared helper copies root Terraform configuration and the lockfile into a temporary test root. It does not copy user tfvars or root state. Each run uses separate state, a unique cluster name, and a dedicated kubeconfig with an absolute path. It uses no static host port mappings. Kubernetes calls target the canonical context explicitly. Do not adapt the scripts to apply against your active root state.

The upgrade scenario checks:

- Kubernetes server and kubelet v1.37.0, Ready nodes, and an empty second plan
- Canonical context and compatible short-name alias, with an unrelated context selected
- A uniquely tagged local application image running with `imagePullPolicy: Never` on every node
- The same application image checks after replacement of `kind_cluster.default` under the same name
- Opt-in GenericWorkload scheduling API discovery under `scheduling.k8s.io/v1beta1`

The patch tests check node labels and the API-server admission configuration. Kubeadm v1beta4 extra arguments use name/value lists. The admission test explicitly enables `ManifestBasedAdmissionControlConfig` to exercise gate forwarding even though the gate is beta/default-on in Kubernetes 1.37.

An EXIT trap destroys only the temporary test root's resources and preserves the original failure status. A successful run removes its temporary test root. A failed run retains that root and its diagnostics even when resource destruction succeeds. If cleanup is incomplete, the run also retains the root and gives a warning. Incomplete cleanup makes an otherwise successful run fail. Do not assume that a retained directory means resources still exist. Do not assume that a test failure means cleanup failed.

Inspect diagnostics and state before manual cleanup. Do not adapt the scripts to apply against retained state for a routine rerun. An approved fresh invocation creates a new temporary test root. Do not remove unrelated containers or images. Pre-existing Docker images must not be deleted.

## Optional networking acceptance

Networking requires a separate opt-in with `TEST_INGRESS=1`, in addition to `RUN_CLUSTER_TESTS=1`. Use a **disposable Docker environment with no unrelated Kind clusters**. cloud-provider-kind watches all clusters on its daemon and installs Gateway CRDs. The test must refuse to take over an existing `cloud-provider-kind` container.

After separate infrastructure approval, run the networking matrix with all three explicit opt-ins:

```bash
RUN_CLUSTER_TESTS=1 TEST_INGRESS=1 DISPOSABLE_DOCKER_ENVIRONMENT=1 make test-upgrade
```

The upgrade script requires `jq`, `curl`, `make`, and GNU `timeout` as well as Terraform, kubectl, and local Docker. The shared cluster-test helper requires `timeout` for bounded diagnostic collection. `DISPOSABLE_DOCKER_ENVIRONMENT=1` records an acknowledgment. It does not create an isolated daemon. Supply the disposable environment yourself. The preflight refuses existing Kind clusters and an existing fixed-name controller.

The networking scenario uses the explicit v0.12.0 controller image and standard Gateway channel. Before apply, it verifies the published image manifest for the host architecture. It then compares the running container's image ID with the platform manifest's config digest. The published v0.12.0 image prints a blank version suffix. The test records the version command, but that command is not sufficient proof of image identity. Do not substitute a controller version or add privileges to bypass a failure.

The intended matrix includes:

| Scenario | Checks |
|----------|--------|
| Controller | Published platform image identity, startup/version logs, Gateway CRD establishment |
| Direct Gateway/HTTPRoute | GatewayClass acceptance, Gateway Accepted/Programmed, route Accepted/ResolvedRefs, HTTP content |
| Ingress | Bundled Ingress-to-Gateway translation, tested separately |
| LoadBalancer Service | HTTP content before and after adding a second Service port |
| Gateway listener addition | HTTP content after adding a listener and matching route parent section |
| Proxy restart | Traffic recovery with finite timeouts and failure diagnostics |

Gateway/HTTPRoute and Ingress support existed before v0.12.0. Proxy recreation after a port is added is a v0.12.0 change for published host ports. Direct networking can update Envoy in place. The test requires recreation only when the existing proxy publishes ports. It checks HTTP traffic in both modes. The checks do not certify arbitrary port removal/mutation, experimental ExternalAuth, custom Envoy templates, Linux tunnel activation, rootless networking, or other host platforms.

The direct Gateway fixture in `test/kustomize/gateway` and Service fixture in `test/kustomize/loadbalancer` use their own namespaces. They are not part of the Ingress kustomization. Cleanup removes fixtures and the Ingress translator's generated `default/kind-ingress-gateway`. It waits for the exact cluster-owned proxies to disappear. It then destroys the controller and cluster. Unrelated containers do not block cleanup and are never removed. Report leftovers instead of deleting containers owned by another user or cluster.

Direct proxy container IPs might not be reachable on your platform. Use an actual discovered published host port only when the selected controller mode supports one. Static Kind control-plane mappings do not expose Envoy proxies. This configuration sets neither `--enable-lb-port-mapping` nor `--enable-lb-tunnel`. Setting either flag, even to false, disables upstream automatic connectivity detection. The socket mount alone does not supply the host interface access needed for tunnel mode.

## Recorded live acceptance result

The Gateway proxy restart failure remains unresolved and [issue #3 remains open](https://github.com/nmdra/kind-cluster-terraform/issues/3). Missing routes after the Docker Gateway proxy restart are a suspected explanation, not a proven specific root cause. The networking suite keeps its failure assertion. This upgrade implements no workaround and includes no custom controller image.

| Check | Result |
|-------|--------|
| Kubernetes v1.37.0, Ready nodes, scheduling API, contexts, empty baseline plans | Passed |
| Local application image on both nodes before and after same-name cluster replacement | Passed |
| Kubeadm patches and admission control | Passed; admission cleanup needed one manual retry before a successful full rerun |
| Controller v0.12.0 platform image identity, Gateway CRDs and GatewayClass | Passed |
| Ingress translation and HTTP routing | Passed |
| LoadBalancer HTTP on original port 80 and added port 8081 | Passed |
| Gateway/HTTPRoute HTTP before and after adding listener 8081 | Passed |
| Gateway proxy restart recovery | Failed: port 80 did not return expected HTTP content within the direct-address retry window |
| Final networking plan and random-name assertion | Not reached after the restart failure |
| Final cleanup and protected files | No test containers or test application image tags remain. Root tfvars/state and user kubeconfig hashes unchanged |

The networking run was interrupted. It then resumed on its existing temporary cluster. It was not a successful end-to-end networking run. The direct-address check makes ten attempts with a two-second delay and at most five seconds per request. The saved output does not distinguish a connection failure, an HTTP error, or unexpected content. Thus, the cause of restart recovery failure is not established. No discovered host port was available in the tested direct-network mode. Do not treat Gateway status conditions alone as proof of data-plane recovery.

The user separately approved this Docker daemon despite unrelated non-Kind containers. That approval did not make the daemon disposable. No controller version, privileges, connectivity flags, or Terraform CLI version were changed to bypass the failure.

Host-local evidence: `/tmp/kind-live-upgrade.log`, `/tmp/kind-live-kubeadm.log`, `/tmp/kind-live-admission-rerun.log`, `/tmp/kind-live-networking-final.log`, and `/tmp/kind-live-networking-resume.log`. Failed-run diagnostics remain in `/tmp/kind-tf-test.K27CLhLI/`. These temporary paths are not durable CI artifacts. Future HTTP checks save the last response headers, body, and curl error to the temporary test root to improve failure diagnosis.

## Failure interpretation, retained diagnostics, and secrets

A nonzero exit means the run failed or is incomplete. It does not give permission to skip assertions. Use the last completed stage to limit the claim:

| Failure stage | Inspect and report |
|---------------|--------------------|
| Preflight or initialization | Missing commands, daemon/socket mismatch, existing clusters/controller, registry access, provider lock selections, or image architecture. A refusal is a safety check, not cluster acceptance. |
| Apply, readiness, patches, or admission | Terraform output, node/API-server status, patch syntax, configured mounts and gates. Admission acceptance verifies arguments and readiness only. |
| Baseline second plan | `second-plan.log`: detailed exit code 2 means a nonempty plan. Exit code 1 means a plan error. Neither is an empty-plan pass. |
| Local-image or replacement assertion | Exact test application image tag, Pod readiness and marker content on both nodes, `replacement-ids.log`, and node container identity. A stable provider cluster ID alone does not disprove replacement. |
| Networking HTTP or status assertion | Controller image evidence, resource generation/status, assigned address, exact proxy ownership, and HTTP evidence. Status conditions alone do not prove traffic recovery. Report later checks as not reached. |
| Cleanup | `destroy.log`, fixture deletion output, `proxy-ids`, and remaining exact test-owned resources. A cleanup warning needs review even if earlier acceptance checks passed. |

The harness prints `Disposable test root: ...` at startup and the retained path on failure. Available files depend on the stage reached. Networking diagnostics include `controller.log`, `containers.log`, `gateways.yaml`, `workloads.yaml`, and `events.log`. Image identity evidence includes `controller-manifest.json`, `controller-platform-manifest.json`, `controller-version.log`, and `controller-startup.log`. Proxy restart output is in `proxy-restart.log`. Current HTTP checks retain the last failed response headers, body, and curl error in `http-direct-*` or `http-published-*` files. These improvements do not retroactively establish the cause of the recorded partial run.

Networking cleanup first collects diagnostics. It then deletes attempted fixtures and the known generated Ingress Gateway, and waits for the exact cluster-owned proxies. If that cleanup fails, the harness leaves the controller and cluster running for review. It does not continue to Terraform destruction or image cleanup. Otherwise, it destroys the isolated resources and removes only the uniquely created test application image tag. Base images can remain in the Docker cache.

Before manual recovery, record the exact temporary test root, cluster/context, state ownership, application image tag, and proxy labels/IDs. Review any destroy plan in that retained root and obtain approval before executing it. If fixture or proxy cleanup still needs reconciliation, keep the controller available. Do not use blanket container deletion, Docker prune, root-state `make down`, or kubeconfig-wide deletion as test cleanup. After you confirm resource cleanup and retain the evidence, remove only the exact temporary test directory. See the [user guide](../docs/user-guide.md) for the broader recovery workflow.

Treat Terraform state/plans, generated kubeconfig, tfvars, logs, YAML snapshots, HTTP bodies, and container listings as potentially sensitive. They can contain credentials, workload data, host paths, addresses, and unrelated container metadata. Retain evidence in access-controlled storage. Before you share it or attach it to issue #3, redact it. Do not commit it. Keep credentials, personal tfvars/state, and user kubeconfig outside test artifacts. The isolated helper clears ambient Terraform overrides. It is not a general tool for removing secrets. When you repeat acceptance, preserve protected-file checks. The recorded unchanged hashes apply only to the recorded run.

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

If an IP is missing, an address is unreachable, or a controller has failed, diagnose the problem. Do not treat it as a passed networking check. Review controller logs and resource status. Ingress translation has wildcard-host and shared namespace TLS/listener semantics that can differ from other Ingress controllers. See the [tagged upstream documentation](https://github.com/kubernetes-sigs/cloud-provider-kind/blob/v0.12.0/pkg/ingress/README.md).
