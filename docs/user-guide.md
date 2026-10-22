# User guide

This guide covers one local development cluster. Unless a section gives a different location, run commands from the repository root. Do not use this configuration for production workloads.

- [Prerequisites](#prerequisites)
- [Create your first cluster](#create-your-first-cluster)
- [Select and inspect the cluster](#select-and-inspect-the-cluster)
- [Change configuration safely](#change-configuration-safely)
- [Load local application images](#load-local-application-images)
- [Build a custom node image](#build-a-custom-node-image)
- [Enable networking](#enable-networking)
- [Configure Kubernetes](#configure-kubernetes)
- [Upgrade or replace a cluster](#upgrade-or-replace-a-cluster)
- [Troubleshooting](#troubleshooting)
- [Clean up](#clean-up)

The [README](../README.md) contains the complete input/output reference. The [test guide](../test/README.md) gives separate procedures for static checks, disposable-cluster acceptance, and smoke tests against your development cluster.

## Prerequisites

| Component | Requirement |
| --- | --- |
| Terraform | 1.15.x; the configuration requires `~> 1.15.0` |
| Docker | A working local daemon; the controller expects `/var/run/docker.sock` |
| kubectl | 1.37 is the acceptance target for Kubernetes 1.37 |
| Host Kind CLI | 0.33.0 for custom node-image builds. The Terraform provider does not use this executable to create clusters. |
| Shell and utilities | Bash for test scripts. Make for convenience targets. |
| Test tools | `jq`, `curl`, GNU `timeout`, and Make for the full acceptance procedure. See the test guide for each suite's requirements. |
| Optional lint tool | TFLint for `make lint`. ShellCheck for shell checks. |

Terraform installs the locked providers: Kind 0.13.0, Docker 4.6.0, and Random 3.9.1. The Kind provider includes an embedded Kind 0.33.0 library. A different host Kind executable does not change the provider's embedded library.

Check your tools and Docker access:

```bash
terraform version
docker info
kubectl version --client
make help
# Needed for custom node-image builds:
kind version
```

The node image supports amd64 and arm64 on matching host platforms. The live tests used Linux amd64 with kubectl 1.36.4 and host Kind 0.32.0. These results do not certify every host platform or the full target-tool matrix. Remote Docker daemons and rootless networking are not verified.

Docker socket access gives broad control over the host. Do not expose the socket to untrusted workloads. Do not treat the controller container as a security boundary.

## Create your first cluster

**Use a new checkout with no existing Terraform state for this procedure.** If the checkout already manages a cluster, use [Upgrade or replace a cluster](#upgrade-or-replace-a-cluster) instead. A plan can replace existing infrastructure even if you only intended to try a new setting.

1. Create a private variables file only if it does not exist:

   ```bash
   if [ ! -e terraform.tfvars ]; then
     cp terraform.tfvars.example terraform.tfvars
   else
     printf 'terraform.tfvars already exists; review it without overwriting it.\n'
   fi
   ```

2. Edit `terraform.tfvars`. Replace the matching entries. Do not add duplicate keys. Use this small starting configuration:

   ```hcl
   kind_cluster_name        = "dev"
   kind_cluster_config_path = "~/.kube/kind-terraform-dev"
   control_plane_node_count = 1
   worker_node_count        = 1
   enable_ingress_lb        = false
   ingress_port_mappings    = []
   ```

   Keep the example's digest-pinned v1.37.0 node image. Unless you need the scheduling profile, leave the feature-gate and runtime-config enable flags false. A dedicated kubeconfig separates this cluster from your usual kubeconfig. If necessary, create the kubeconfig parent directory:

   ```bash
   mkdir -p "$HOME/.kube"
   ```

   With `ingress_port_mappings = []`, the cluster does not reserve the default host ports 30082 and 30443. These node mappings are not necessary to expose the controller's Envoy proxies.

3. Initialize the provider selections in the repository. Check the configuration:

   ```bash
   terraform init -lockfile=readonly
   terraform fmt -check
   terraform validate
   make test-plan
   ```

   Initialization downloads providers. It does not create a cluster. `make test-plan` uses mocks. It does not load your private variables or state.

4. Review the real infrastructure plan:

   ```bash
   terraform plan
   ```

   In a new checkout, expect the plan to create resources. If the plan includes unexpected destruction or replacement, stop. Do not run `terraform init -upgrade` only to remove a lockfile mismatch.

5. After approval, create the cluster:

   ```bash
   terraform apply
   ```

   `terraform apply` makes a new plan and asks for approval. Review the new plan. The alternative command `make up` uses `-auto-approve`. It does not include this approval step.

6. Inspect the results:

   ```bash
   terraform output
   make status
   ```

   Continue with the explicit-context helper below. Do not assume that your shell's `KUBECONFIG` already specifies the dedicated file.

## Select and inspect the cluster

When Terraform creates the cluster, it writes the provider's canonical context. It also selects a short-name alias in the configured kubeconfig. For a cluster named `dev`, the canonical context and alias are normally `kind-dev` and `dev`. Always get the actual name from Terraform outputs. When you enable networking, the name gets the suffix `-ing`.

In your Bash session, load the outputs. Define a helper that checks these outputs:

```bash
KUBECONFIG_PATH=$(terraform output -raw kubeconfig_path)
CLUSTER_CONTEXT=$(terraform output -raw cluster_context)
kube() {
  if [ -z "${KUBECONFIG_PATH:-}" ] || [ ! -f "$KUBECONFIG_PATH" ] ||
     [ -z "${CLUSTER_CONTEXT:-}" ]; then
    printf 'Missing Terraform kubeconfig/context output. Stop and inspect state.\n' >&2
    return 1
  fi
  kubectl --kubeconfig="$KUBECONFIG_PATH" --context="$CLUSTER_CONTEXT" \
    --request-timeout=15s "$@"
}
kube config get-contexts
kube get nodes -o wide
kube get --raw /version
kube get pods -A
```

After a cluster-name or kubeconfig-path change, load both outputs again. The helper does not depend on `current-context`. Repository Makefile commands also specify the target explicitly.

The short-name alias remains available for manual use. Do not put a guessed context into automation. When Terraform destroys the cluster, it removes the cluster's contexts, cluster entry, and user entry. It does not select your previous context again.

## Change configuration safely

Keep settings that you use regularly in `terraform.tfvars`. Git ignores this file. If a plan does not match the defaults, review `*.auto.tfvars`, environment variables such as `TF_VAR_kind_cluster_node_image`, and command-line `-var` options. After a repository update, a private value can still select an older image.

For each change:

1. Edit the intended input.
2. Run `terraform validate` and `terraform plan`.
3. Check replacement and deletion actions.
4. If the cluster will be replaced, back up workloads and get approval.
5. Run `terraform apply`. Verify the resulting cluster.

Changes to node counts, node images, kubeadm patches, mounts, and Kind configuration do not provide an in-place Kubernetes upgrade. Treat each cluster replacement as loss of workloads and node-local data.

Makefile overrides are temporary. For example, `make up WORKER_NODE_COUNT=2` does not save the value in your variables file. Without that override, a later apply can plan to change the value again. For normal use, prefer saved configuration. Do not use an auto-approved override to omit plan review.

The setting `control_plane_node_count = 3` creates a development HA topology. This setting does not make the cluster or its single Docker host suitable for production.

## Load local application images

An application image is different from the node image that contains Kubernetes.

1. From your application's build directory, build an image with a unique tag. Use the same local Docker daemon that Kind uses:

   ```bash
   docker build -t myapp:dev-001 /absolute/path/to/myapp
   docker image inspect myapp:dev-001 --format '{{.Id}}'
   ```

2. Add the tag to the cluster's `terraform.tfvars`:

   ```hcl
   local_images = ["myapp:dev-001"]
   ```

3. From this repository, run `terraform plan`. After approval, run `terraform apply`.
4. Specify that tag in your workload manifest. For a strictly local image, set `imagePullPolicy: Never`. If you intend to use registry fallback, set `IfNotPresent`.
5. Inspect the workload with the explicit `kube` helper. For example, use `kube get pods -A` and `kube describe pod <pod-name> -n <namespace>`.

The provider loads images onto all cluster nodes. It does not pull missing images. After a same-name cluster replacement, the provider loads the images again. If you remove an entry, the image stays on the nodes.

Prefer a new tag for each build. Provider refresh does not compare a rebuilt local image ID. It accepts an image present on any one node. Thus, provider refresh does not provide full image drift reconciliation. If you intentionally reuse a tag already configured in `local_images`, review and approve an explicit reload:

```bash
terraform plan -replace='kind_load.local_images["myapp:dev"]'
terraform apply -replace='kind_load.local_images["myapp:dev"]'
```

Replace the resource key with your configured tag. After the reload, restart the affected application pods separately. Do not replace the whole cluster only to reload an application image.

## Build a custom node image

Use host Kind 0.33.0 for this optional workflow:

```bash
make build-node-image KUBERNETES_VERSION=v1.37.0 IMAGE_NAME=kindest/node:v1.37.0-local
```

The build downloads release artifacts and creates a local Docker image. It does not update the cluster. Set the image in `terraform.tfvars`:

```hcl
kind_cluster_node_image = "kindest/node:v1.37.0-local"
```

Before you apply the replacement plan, review the plan and follow the backup steps. A custom local build uses its own tag. Do not append the published image's digest to a different local build. Input validation supports tagged references with registry ports and optional SHA-256 digests.

## Enable networking

**A change to `enable_ingress_lb` changes the cluster name and replaces the cluster.** If you enable this setting, the name gets the suffix `-ing`. If you disable this setting, the name loses that suffix. Before you change this setting on a populated cluster, follow the replacement procedure.

Edit these values in `terraform.tfvars`:

```hcl
enable_ingress_lb                   = true
cloud_provider_kind_image           = "registry.k8s.io/cloud-provider-kind/cloud-controller-manager:v0.12.0"
cloud_provider_kind_gateway_channel = "standard"
```

The controller has the fixed Docker name `cloud-provider-kind`. It watches all Kind clusters on the daemon and installs Gateway CRDs. Do not take over a controller owned by another checkout. Separate Terraform state alone does not isolate controller access to the daemon.

| Channel | Behavior |
| --- | --- |
| `standard` | Standard Gateway API resources and bundled Ingress translation |
| `experimental` | Experimental Gateway resources/features and bundled Ingress. The live acceptance result does not cover this channel. |
| `disabled` | No bundled Gateway/Ingress controller. LoadBalancer Services remain separate. |

After an approved apply, load the explicit-context outputs again. Inspect readiness:

```bash
make status
kube get gatewayclass
kube get crd gateways.gateway.networking.k8s.io httproutes.gateway.networking.k8s.io
docker logs --tail 100 cloud-provider-kind
```

For the bundled Ingress smoke test against the cluster in this checkout's state:

```bash
make test
make clean-test
```

`make test` creates or updates httpbin resources in `default`. This is not an isolated mock or disposable-cluster test. `make clean-test` deletes those resources. Do not run this cleanup command while another procedure owns the same fixtures.

Before a manual direct-Gateway demonstration, confirm that no acceptance run owns namespace `tf-upgrade-gateway`. Then apply the fixture:

```bash
kube apply -k test/kustomize/gateway
kube -n tf-upgrade-gateway rollout status deployment/echo --timeout=180s
kube -n tf-upgrade-gateway get gateway,httproute
GATEWAY_IP=$(kube -n tf-upgrade-gateway get gateway upgrade \
  -o jsonpath='{.status.addresses[0].value}')
test -n "$GATEWAY_IP" && curl --noproxy '*' -fsS \
  --connect-timeout 2 --max-time 5 "http://$GATEWAY_IP/"
```

Before you test traffic, wait for an assigned address and current-generation `Accepted`/`Programmed` conditions. The expected content includes `kind-upgrade-ok`. Status conditions alone do not prove that HTTP routing works. If the address is empty, wait and inspect events. Do not send a request to a guessed endpoint.

The separate `test/kustomize/loadbalancer` fixture provides a Service of type `LoadBalancer` in namespace `tf-upgrade-loadbalancer`. Only if you own that namespace, apply the fixture with `kube apply -k test/kustomize/loadbalancer`. Use `kube -n tf-upgrade-loadbalancer get service echo` to inspect its assigned address.

If direct proxy IPs are unreachable on your platform, use only a discovered published host port. Use this port only if the controller's selected connectivity mode provides one. The default control-plane mappings do not expose Envoy proxy containers. No port-mapping/tunnel override flags or extra container privileges are configured. Either connectivity flag disables upstream automatic detection, even if the flag is false.

### Known Gateway restart limitation

[Issue #3](https://github.com/nmdra/kind-cluster-terraform/issues/3) records a failed HTTP recovery check after a Gateway proxy container restart. Normal Ingress traffic, LoadBalancer added-port traffic, and Gateway added-listener traffic passed. Full networking acceptance did not pass.

The v0.12.0 source installs Pod/Service routes when it creates a container. It skips that setup for an existing running container. Route loss after Docker restart is a suspected cause. The saved logs support this explanation, but do not conclusively identify the cause of this failure. The recorded searches did not establish an exact matching acknowledged upstream issue or fix.

Before you use a proxy restart as a routine recovery step, understand this limitation. This repository does not implement a custom controller image or an automatic workaround. The acceptance test keeps the failing recovery assertion. Do not increase a timeout or remove the assertion only to report a passing matrix.

## Configure Kubernetes

For the optional scheduling profile, set both enable flags as well as the maps:

```hcl
enable_feature_gates  = true
enable_runtime_config = true
feature_gates = {
  GenericWorkload = true
}
runtime_config = {
  "scheduling.k8s.io/v1beta1" = "true"
}
```

After an approved replacement, inspect discovery with `kube get --raw /apis/scheduling.k8s.io/v1beta1`. Kubernetes 1.37 does not serve the old scheduling v1alpha1 example. `GangScheduling` is not a 1.37 feature gate. `OpportunisticBatching` is already enabled by default.

Use kubeadm v1beta4 name/value lists for `extraArgs` and `kubeletExtraArgs`. If a label must reach every node role, include both InitConfiguration and JoinConfiguration patches. Use the examples in [terraform.tfvars.example](../terraform.tfvars.example). Do not use old map-style extra arguments.

`extra_mounts` applies to all configured node roles. Use absolute host paths that exist on the Docker host. Where possible, use `read_only = true`. A mount can expose private host files to the cluster. Do not mount a credentials directory only for convenience.

## Upgrade or replace a cluster

Changes to Git files or the lockfile do not upgrade a running cluster. If you apply a changed node image, Terraform destroys and recreates the cluster. Git rollback and Terraform state restoration do not restore workloads.

1. **Identify the existing target.** Run `terraform output` and `make status`. Check private image, name, and networking overrides. Do not overwrite your existing variables file with the example.
2. **Make secure backups outside the repository.** State, kubeconfig, and saved plans can contain credentials. For example:

   ```bash
   umask 077
   BACKUP_DIR=$(mktemp -d "${TMPDIR:-/tmp}/kind-upgrade-backup.XXXXXXXX")
   terraform state pull > "$BACKUP_DIR/state-before-upgrade.json"
   KUBECONFIG_PATH=$(terraform output -raw kubeconfig_path)
   test -f "$KUBECONFIG_PATH" && cp -- "$KUBECONFIG_PATH" "$BACKUP_DIR/kubeconfig"
   printf 'Secure backup directory: %s\n' "$BACKUP_DIR"
   ```

   If any backup step fails, stop. Before you rely on required backups, move the backups to secure durable storage. `/tmp` is not durable storage. `umask 077` also affects files that you create later in this shell.
3. **Preserve workloads and data.** Keep source manifests or Helm values outside the Kind nodes. Also keep an application-specific backup of persistent data outside the Kind nodes. A state backup is not a data backup. Do not publish exported Secrets or raw diagnostic bundles.
4. **Initialize and review.** Run `terraform init -lockfile=readonly`, `terraform validate`, and `terraform plan`. Confirm expected provider selections, image digest, replacement actions, context paths, and image reloads. Check that the random name does not change unexpectedly.
5. **Approve the destructive change.** Apply only when required data can be restored. Before you accept the fresh `terraform apply` plan, review the plan. Avoid `make up` for an unreviewed migration because the command auto-approves.
6. **Restore and verify.** Load context outputs again. Check server/node versions. Restore application workloads/data. Test required networking. Then run `terraform plan` again. Investigate any unexpected changes that remain.

For rollback, select a previously tested configuration/provider/node image combination. Review the replacement plan. Recreate the cluster. Restore workloads/data. Do not treat a Git revert as an in-place Kubernetes downgrade. Consider the known Gateway limitation when you make the upgrade decision.

## Troubleshooting

| Symptom | First checks and safe action |
| --- | --- |
| Plan still selects an older image | Inspect private tfvars, auto-loaded variables, environment variables, and CLI overrides. Repository defaults do not override explicit values. |
| Missing `cluster_context` output | Run `terraform output` and inspect state. An older state may not expose the new output until an approved apply. Do not use a guessed current context as an alternative. |
| Docker socket permission failure | Check `docker info` and daemon/socket access. Do not make the socket world-writable. Docker access effectively gives host-admin access. |
| `cloud-provider-kind` name conflict | Identify the container owner and the state that manages the container. Do not remove or import the container only to make this checkout apply. |
| Host port already allocated | Inspect configured `ingress_port_mappings`. Before you use free ports or `[]`, review the resulting replacement plan. |
| `ImagePullBackOff` or `ErrImageNeverPull` | Check the exact tag, local Docker image presence, `local_images`, and workload pull policy. Inspect pod events. Use a versioned rebuild or explicit image-load replacement. |
| Gateway address exists but HTTP fails | Inspect conditions, events, controller logs, backend pod readiness, and the actual proxy connectivity mode. An address and Programmed status do not prove that traffic works. |
| Traffic fails after Gateway proxy restart | See issue #3. Before you change anything, capture HTTP status/errors, proxy logs, and routes. No automatic recovery workaround is implemented. |
| Controller `version` prints no version suffix | The tested v0.12.0 image gave this output. Compare the running image ID with the published platform manifest's config digest. A local tag string alone is not proof. The acceptance script does this check. |
| A disposable test fails | Read the first error, retained test-root path, and cleanup result. Follow the test guide. Do not destroy from the repository root as a cleanup shortcut. |

Use the explicit `kube` helper for read-only diagnosis:

```bash
kube get nodes,pods -A
kube get ingress,service -A
kube get gateway,httproute -A
kube get events -A --sort-by=.lastTimestamp
docker logs --tail 200 cloud-provider-kind
```

Gateway API queries require installed CRDs. If networking is disabled, these queries can fail normally. Before you share logs, review and redact the logs. Never attach state, kubeconfig credentials, private tfvars, or unreviewed workload exports to an issue.

## Clean up

Delete only fixtures that you created and whose namespaces you own:

```bash
make clean-test
kube delete -k test/kustomize/gateway --ignore-not-found --wait=true --timeout=120s
kube delete -k test/kustomize/loadbalancer --ignore-not-found --wait=true --timeout=120s
```

The bundled Ingress translator can leave a generated `kind-ingress-gateway` in `default`. Do not delete that Gateway without review on a development cluster. The Gateway can serve other Ingress resources. Disposable acceptance cleanup can remove the Gateway because the whole cluster belongs to the test.

Before you remove the cluster managed by this checkout, preserve anything you need. Then review destruction:

```bash
terraform plan -destroy
# Run only after approval:
terraform destroy
```

`make down` also destroys the cluster, but the command auto-approves. Cluster destruction deletes workloads and node-local data. It also removes the cluster's kubeconfig entries. The controller image stays in local storage. Previously loaded application images are not individually unloaded. Their node storage is removed with the cluster.

Do not use `docker system prune`, blanket container removal, or an unrelated checkout's Terraform state to clean up this project.
