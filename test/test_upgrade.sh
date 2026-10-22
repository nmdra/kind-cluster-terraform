#!/usr/bin/env bash
set -euo pipefail
# shellcheck source-path=SCRIPTDIR
# shellcheck source=helpers.sh
source "$(dirname "$0")/helpers.sh"

CONTROLLER_IMAGE=registry.k8s.io/cloud-provider-kind/cloud-controller-manager:v0.12.0
NETWORK_STARTED=0
IMAGE_CREATED=0
INGRESS_ATTEMPTED=0
GATEWAY_ATTEMPTED=0
LOADBALANCER_ATTEMPTED=0

cleanup_image() {
  # This exact tag was checked absent before building; never prune or remove base images.
  if [[ "$IMAGE_CREATED" == 1 ]] && docker image inspect "$LOCAL_IMAGE" >/dev/null 2>&1; then
    docker image rm "$LOCAL_IMAGE" >"$TEST_ROOT/image-cleanup.log" 2>&1
  fi
}

network_diagnostics() {
  timeout 20s docker logs --tail 200 cloud-provider-kind >"$TEST_ROOT/controller.log" 2>&1 || true
  timeout 20s docker ps -a --no-trunc >"$TEST_ROOT/containers.log" 2>&1 || true
  kube get gateway,httproute -A -o yaml >"$TEST_ROOT/gateways.yaml" 2>&1 || true
  kube get service,pod,ingress -A -o yaml >"$TEST_ROOT/workloads.yaml" 2>&1 || true
  kube get events -A --sort-by=.lastTimestamp >"$TEST_ROOT/events.log" 2>&1 || true
}

cleanup_network() {
  [[ "$NETWORK_STARTED" == 1 ]] || return 0
  local failed=0 id attempt present
  network_diagnostics
  # Attempt every delete even if one fixture was only partially applied.
  if [[ "$GATEWAY_ATTEMPTED" == 1 ]]; then
    kube delete -k "$REPO_ROOT/test/kustomize/gateway" --ignore-not-found --wait=true --timeout=120s || failed=1
  fi
  if [[ "$LOADBALANCER_ATTEMPTED" == 1 ]]; then
    kube delete -k "$REPO_ROOT/test/kustomize/loadbalancer" --ignore-not-found --wait=true --timeout=120s || failed=1
  fi
  if [[ "$INGRESS_ATTEMPTED" == 1 ]]; then
    kube delete -n default -k "$REPO_ROOT/test/kustomize" --ignore-not-found --wait=true --timeout=120s || failed=1
    # The bundled translator leaves its namespace singleton after the last Ingress.
    # This namespace belongs to our isolated cluster; remove only its known test Gateway.
    kube delete gateway kind-ingress-gateway -n default --ignore-not-found --wait=true --timeout=120s || failed=1
  fi
  # Observe exact cluster-owned proxies, including partial applies without an address.
  # Unrelated containers created while a test is paused must not block its cleanup.
  for ((attempt=0; attempt<60; attempt++)); do
    present=0
    if ! docker ps -aq --no-trunc --filter "label=io.x-k8s.cloud-provider-kind.cluster=$CLUSTER_NAME" >"$TEST_ROOT/cleanup-container-ids"; then return 1; fi
    while read -r id; do
      [[ -n "$id" ]] && printf '%s\n' "$id" >>"$TEST_ROOT/proxy-ids"
    done <"$TEST_ROOT/cleanup-container-ids"
    sort -u "$TEST_ROOT/proxy-ids" -o "$TEST_ROOT/proxy-ids"
    while read -r id; do
      [[ -n "$id" ]] || continue
      if docker container inspect "$id" >/dev/null 2>&1; then present=1; fi
    done <"$TEST_ROOT/proxy-ids"
    if (( present == 0 )); then break; fi
    sleep 2
  done
  if (( present != 0 )); then
    printf 'WARNING: test proxy containers remain; leaving controller/cluster alive. See %s/proxy-ids\n' "$TEST_ROOT" >&2
    failed=1
  fi
  return "$failed"
}

network_preflight() {
  [[ "${DISPOSABLE_DOCKER_ENVIRONMENT:-}" == 1 ]] || fail 'Networking is host-wide. Set DISPOSABLE_DOCKER_ENVIRONMENT=1 only for a disposable Docker daemon.'
  local clusters architecture platform_digest
  clusters=$(docker ps -a --filter label=io.x-k8s.kind.cluster --format '{{.Names}}')
  [[ -z "$clusters" ]] || fail "Networking refuses existing Kind clusters: $clusters"
  if docker container inspect cloud-provider-kind >/dev/null 2>&1; then
    fail 'Fixed controller container cloud-provider-kind already exists; it will not be removed.'
  fi
  docker manifest inspect "$CONTROLLER_IMAGE" >"$TEST_ROOT/controller-manifest.json" || fail "Cannot inspect published image $CONTROLLER_IMAGE"
  architecture=$(docker version --format '{{.Server.Arch}}')
  platform_digest=$(jq -er --arg arch "$architecture" '
    [.manifests[] | select(.platform.os == "linux" and .platform.architecture == $arch)] |
    if length == 1 then .[0].digest else error("expected one platform manifest") end' \
    "$TEST_ROOT/controller-manifest.json") || fail "Published controller image has no unique linux/$architecture manifest."
  docker manifest inspect "${CONTROLLER_IMAGE%:*}@$platform_digest" >"$TEST_ROOT/controller-platform-manifest.json"
  EXPECTED_CONTROLLER_IMAGE_ID=$(jq -er '.config.digest | select(test("^sha256:[a-f0-9]{64}$"))' \
    "$TEST_ROOT/controller-platform-manifest.json")
}

check_baseline() {
  wait_nodes
  [[ $(kube get nodes -o json | jq '.items | length') == 2 ]] || fail 'Expected one control plane and one worker.'
  [[ $(kube get --raw /version | jq -r .gitVersion) == v1.37.0 ]] || fail 'Server is not v1.37.0.'
  kube get nodes -o json | jq -e 'all(.items[]; .status.nodeInfo.kubeletVersion == "v1.37.0")' >/dev/null
  # Keep current-context invalid to prove all automation uses the explicit output context.
  kube config set-context unrelated --cluster=unrelated --user=unrelated >/dev/null
  kube config use-context unrelated >/dev/null
  kube get nodes >/dev/null
  kube --context="$CLUSTER_NAME" get nodes >/dev/null
  kube get --raw /apis/scheduling.k8s.io/v1beta1 | jq -e '
    [.resources[].name] | index("workloads") != null and index("podgroups") != null' >/dev/null
  assert_empty_plan
}

check_local_image() {
  local node index=0
  while read -r node; do
    cat <<EOF | kube apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: local-image-$index
spec:
  nodeName: $node
  tolerations:
  - operator: Exists
  containers:
  - name: local
    image: $LOCAL_IMAGE
    imagePullPolicy: Never
    command: ["sh", "-c", "sleep 3600"]
    readinessProbe:
      exec:
        command: ["cat", "/image-marker"]
      initialDelaySeconds: 1
      periodSeconds: 2
EOF
    kube wait --for=condition=Ready "pod/local-image-$index" --timeout=120s
    [[ $(kube exec "local-image-$index" -- cat /image-marker) == "$CLUSTER_NAME" ]] || fail "Wrong image content on $node"
    index=$((index + 1))
  done < <(kube get nodes -o jsonpath='{range .items[*]}{.metadata.name}{"\n"}{end}')
  [[ "$index" == 2 ]] || fail 'Local image was not tested on both nodes.'
}

wait_address() {
  local namespace=$1 resource=$2 path=$3 address attempt
  for ((attempt=0; attempt<90; attempt++)); do
    address=$(kube -n "$namespace" get "$resource" -o "jsonpath=$path")
    if [[ -n "$address" ]]; then printf '%s\n' "$address"; return 0; fi
    sleep 2
  done
  printf 'No address for %s/%s\n' "$namespace" "$resource" >&2
  return 1
}

# Match the exact network and controller ownership labels, not an IP on any network.
# Label keys are defined in cloud-provider-kind v0.12.0 pkg/constants/constants.go.
proxy_for_address() {
  local address=$1 id found='' matches=0
  while read -r id; do
    [[ -n "$id" ]] || continue
    grep -Fxq "$id" "$TEST_ROOT/network-before-ids" && continue
    if docker inspect "$id" | jq -e --arg address "$address" --arg cluster "$CLUSTER_NAME" '
      .[0] | .Config.Labels as $labels |
      ($labels["io.x-k8s.cloud-provider-kind.cluster"] == $cluster) and
      ((($labels["io.x-k8s.cloud-provider-kind.loadbalancer.name"] // "") | startswith($cluster + "/")) or
       (($labels["io.x-k8s.cloud-provider-kind.gateway.name"] // "") | startswith($cluster + "/"))) and
      (.NetworkSettings.Networks.kind | .IPAddress == $address or .GlobalIPv6Address == $address)' >/dev/null; then
      found=$id
      matches=$((matches + 1))
    fi
  done < <(docker ps -q --no-trunc --filter network=kind --filter "label=io.x-k8s.cloud-provider-kind.cluster=$CLUSTER_NAME")
  [[ "$matches" == 1 ]] || { printf 'Expected exactly one owned proxy for %s, found %s\n' "$address" "$matches" >&2; return 1; }
  printf '%s\n' "$found" >>"$TEST_ROOT/proxy-ids"
  printf '%s\n' "$found"
}

http_check() {
  local address=$1 port=$2 id=$3 attempt body mapping host published
  # Test direct proxy address first. Static Kind API/control-plane mappings are not proxy ports.
  for ((attempt=0; attempt<10; attempt++)); do
    if body=$(curl --noproxy '*' -fsS --connect-timeout 2 --max-time 5 --dump-header "$TEST_ROOT/http-direct-$id-$port.headers" "http://$address:$port/" 2>"$TEST_ROOT/http-direct-$id-$port.error") && [[ "$body" == *kind-upgrade-ok* ]]; then return 0; fi
    printf '%s\n' "$body" >"$TEST_ROOT/http-direct-$id-$port.body"
    sleep 2
  done
  printf 'HTTP content check failed at direct proxy address %s:%s; checking discovered published port.\n' "$address" "$port" >&2
  mapping=$(docker port "$id" "$port/tcp" 2>/dev/null | head -n 1) || true
  [[ -n "$mapping" ]] || { printf 'No published host port in the tested controller mode.\n' >&2; return 1; }
  host=${mapping%:*}
  published=${mapping##*:}
  case "$host" in
    0.0.0.0|127.0.0.1) host=127.0.0.1 ;;
    '[::]'|'[::1]') host='[::1]' ;;
  esac
  printf 'Testing discovered mapping %s:%s\n' "$host" "$published" >&2
  for ((attempt=0; attempt<30; attempt++)); do
    if body=$(curl --noproxy '*' -fsS --connect-timeout 2 --max-time 5 --dump-header "$TEST_ROOT/http-published-$id-$port.headers" "http://$host:$published/" 2>"$TEST_ROOT/http-published-$id-$port.error") && [[ "$body" == *kind-upgrade-ok* ]]; then return 0; fi
    printf '%s\n' "$body" >"$TEST_ROOT/http-published-$id-$port.body"
    sleep 2
  done
  return 1
}

wait_gateway() {
  local attempt
  for ((attempt=0; attempt<90; attempt++)); do
    if kube -n tf-upgrade-gateway get gateway upgrade -o json | jq -e '
      .metadata.generation as $generation | .status.conditions as $conditions |
      all(["Accepted", "Programmed"][]; . as $type |
        any($conditions[]; .type == $type and .status == "True" and .observedGeneration == $generation))' >/dev/null; then return 0; fi
    sleep 2
  done
  return 1
}

wait_route() {
  local attempt
  for ((attempt=0; attempt<90; attempt++)); do
    if kube -n tf-upgrade-gateway get httproute echo -o json | jq -e '
      .metadata.generation as $generation |
      (.spec.parentRefs | length) as $expected |
      (.status.parents // []) as $parents |
      ($parents | length == $expected) and
      all($parents[]; .conditions as $conditions |
        all(["Accepted", "ResolvedRefs"][]; . as $type |
          any($conditions[]; .type == $type and .status == "True" and .observedGeneration == $generation)))' >/dev/null; then return 0; fi
    sleep 2
  done
  return 1
}

network_tests() {
  local attempt address proxy old_proxy requires_recreation
  cat >"$TEST_ROOT/network.auto.tfvars" <<EOF
enable_ingress_lb = true
cloud_provider_kind_image = "$CONTROLLER_IMAGE"
cloud_provider_kind_gateway_channel = "standard"
EOF
  # Recheck ownership immediately before enabling the host-wide controller.
  if docker container inspect cloud-provider-kind >/dev/null 2>&1; then fail 'Controller appeared during baseline tests; refusing takeover.'; fi
  [[ -z $(docker ps -a --filter label=io.x-k8s.kind.cluster --format '{{.Label "io.x-k8s.kind.cluster"}}' | grep -vxF "$CLUSTER_NAME" || true) ]] || fail 'An unrelated Kind cluster appeared during baseline tests.'
  docker ps -aq --no-trunc >"$TEST_ROOT/network-before-ids"
  # The preserved root naming rule adds -ing when networking is enabled. This
  # is separate from the same-name replacement acceptance performed above.
  CLUSTER_NAME="$CLUSTER_NAME-ing"
  export CLUSTER_CONTEXT="kind-$CLUSTER_NAME"
  # Arm cleanup before apply or make, including partial failures.
  NETWORK_STARTED=1
  : >"$TEST_ROOT/proxy-ids"
  apply_test
  [[ $(docker inspect cloud-provider-kind --format '{{.State.Running}}') == true ]] || fail 'Controller is not running.'
  docker exec cloud-provider-kind /bin/cloud-provider-kind version >"$TEST_ROOT/controller-version.log" 2>&1
  [[ $(docker inspect cloud-provider-kind --format '{{.Image}}') == "$EXPECTED_CONTROLLER_IMAGE_ID" ]] || fail 'Running controller does not match the published v0.12.0 platform image.'
  [[ $(docker image inspect "$CONTROLLER_IMAGE" --format '{{.Id}}') == "$EXPECTED_CONTROLLER_IMAGE_ID" ]] || fail 'Local controller tag does not match the published v0.12.0 platform image.'
  if ! grep -q '0.12.0' "$TEST_ROOT/controller-version.log"; then
    printf 'NOTE: controller version output omits the version; verified published platform manifest/config digest %s instead.\n' "$EXPECTED_CONTROLLER_IMAGE_ID"
  fi
  docker logs cloud-provider-kind >"$TEST_ROOT/controller-startup.log" 2>&1
  for ((attempt=0; attempt<90; attempt++)); do
    if kube get crd gateways.gateway.networking.k8s.io httproutes.gateway.networking.k8s.io >/dev/null 2>&1 &&
       kube get gatewayclass cloud-provider-kind >/dev/null 2>&1; then break; fi
    sleep 2
  done
  kube wait --for=condition=Established crd/gateways.gateway.networking.k8s.io crd/httproutes.gateway.networking.k8s.io --timeout=180s
  kube wait --for=condition=Accepted gatewayclass/cloud-provider-kind --timeout=180s
  # Test the existing Ingress translation separately, using isolated state and repository-relative fixture paths.
  INGRESS_ATTEMPTED=1
  (cd "$TEST_ROOT" && make -f "$REPO_ROOT/Makefile" test)
  address=$(wait_address default ingress/httpbin '{.status.loadBalancer.ingress[0].ip}')
  proxy_for_address "$address" >/dev/null

  LOADBALANCER_ATTEMPTED=1
  kube apply -k "$REPO_ROOT/test/kustomize/loadbalancer"
  kube -n tf-upgrade-loadbalancer rollout status deployment/echo --timeout=180s
  address=$(wait_address tf-upgrade-loadbalancer service/echo '{.status.loadBalancer.ingress[0].ip}')
  proxy=$(proxy_for_address "$address")
  http_check "$address" 80 "$proxy"
  old_proxy=$proxy
  requires_recreation=0
  if docker inspect "$proxy" | jq -e '.[0].HostConfig.PortBindings // {} | length > 0' >/dev/null; then requires_recreation=1; fi
  kube -n tf-upgrade-loadbalancer patch service echo --type=json -p='[{"op":"add","path":"/spec/ports/-","value":{"name":"http-second","port":8081,"targetPort":8080,"protocol":"TCP"}}]'
  # Published ports require recreation; direct networking can update Envoy in place.
  # Re-read the address in either mode instead of retaining a stale IP.
  for ((attempt=0; attempt<90; attempt++)); do
    address=$(wait_address tf-upgrade-loadbalancer service/echo '{.status.loadBalancer.ingress[0].ip}')
    proxy=$(proxy_for_address "$address") || { sleep 2; continue; }
    [[ "$requires_recreation" == 0 || "$proxy" != "$old_proxy" ]] && break
    sleep 2
  done
  [[ "$requires_recreation" == 0 || "$proxy" != "$old_proxy" ]] || fail 'LoadBalancer proxy with published ports was not recreated for the added port.'
  http_check "$address" 80 "$proxy"
  http_check "$address" 8081 "$proxy"

  GATEWAY_ATTEMPTED=1
  kube apply -k "$REPO_ROOT/test/kustomize/gateway"
  kube -n tf-upgrade-gateway rollout status deployment/echo --timeout=180s
  wait_gateway
  wait_route
  address=$(wait_address tf-upgrade-gateway gateway/upgrade '{.status.addresses[0].value}')
  proxy=$(proxy_for_address "$address")
  http_check "$address" 80 "$proxy"
  old_proxy=$proxy
  requires_recreation=0
  if docker inspect "$proxy" | jq -e '.[0].HostConfig.PortBindings // {} | length > 0' >/dev/null; then requires_recreation=1; fi
  kube -n tf-upgrade-gateway patch gateway upgrade --type=json -p='[{"op":"add","path":"/spec/listeners/-","value":{"name":"http-second","protocol":"HTTP","port":8081}}]'
  kube -n tf-upgrade-gateway patch httproute echo --type=json -p='[{"op":"add","path":"/spec/parentRefs/-","value":{"name":"upgrade","sectionName":"http-second"}}]'
  for ((attempt=0; attempt<90; attempt++)); do
    address=$(wait_address tf-upgrade-gateway gateway/upgrade '{.status.addresses[0].value}')
    proxy=$(proxy_for_address "$address") || { sleep 2; continue; }
    [[ "$requires_recreation" == 0 || "$proxy" != "$old_proxy" ]] && break
    sleep 2
  done
  [[ "$requires_recreation" == 0 || "$proxy" != "$old_proxy" ]] || fail 'Gateway proxy with published ports was not recreated for the added listener.'
  wait_gateway
  wait_route
  http_check "$address" 80 "$proxy"
  http_check "$address" 8081 "$proxy"
  # Restart only the exact proxy discovered from this test Gateway's assigned address.
  docker restart "$proxy" >"$TEST_ROOT/proxy-restart.log"
  http_check "$address" 80 "$proxy"
  http_check "$address" 8081 "$proxy"
  assert_empty_plan
}

setup_test
for command in jq curl make; do require_command "$command"; done
if [[ "${TEST_INGRESS:-0}" == 1 ]]; then network_preflight; fi
LOCAL_IMAGE="kind-tf-local-test:$CLUSTER_NAME"
if docker image inspect "$LOCAL_IMAGE" >/dev/null 2>&1; then fail "Refusing pre-existing image tag $LOCAL_IMAGE"; fi
mkdir "$TEST_ROOT/image"
cat >"$TEST_ROOT/image/Dockerfile" <<EOF
FROM busybox:1.37.0
RUN echo '$CLUSTER_NAME' > /image-marker
EOF
# Track the tag before build, so a partial build is also eligible for cleanup.
IMAGE_CREATED=1
docker build -t "$LOCAL_IMAGE" "$TEST_ROOT/image"
printf 'local_images = ["%s"]\n' "$LOCAL_IMAGE" >"$TEST_ROOT/images.auto.tfvars"
cat >"$TEST_ROOT/scheduling.auto.tfvars" <<'EOF'
enable_feature_gates = true
feature_gates = { GenericWorkload = true }
enable_runtime_config = true
runtime_config = { "scheduling.k8s.io/v1beta1" = "true" }
EOF
init_test
apply_test
check_baseline
check_local_image
original_random_name=$(tf show -json | jq -r '.values.root_module.resources[] | select(.address == "random_pet.cluster") | .values.id')
original_node_id=$(docker inspect "$CLUSTER_NAME-control-plane" --format '{{.Id}}')
original_cluster_id=$(tf show -json | jq -r '.values.root_module.resources[] | select(.address == "kind_cluster.default") | .values.id')
apply_test -replace=kind_cluster.default
new_cluster_id=$(tf show -json | jq -r '.values.root_module.resources[] | select(.address == "kind_cluster.default") | .values.id')
# The provider may use the stable cluster name as its ID. Record both for diagnostics, not as a replacement assertion.
printf 'before=%s\nafter=%s\n' "$original_cluster_id" "$new_cluster_id" >"$TEST_ROOT/replacement-ids.log"
[[ $(docker inspect "$CLUSTER_NAME-control-plane" --format '{{.Id}}') != "$original_node_id" ]] || fail 'Control-plane container did not change after replacement.'
check_baseline
check_local_image
if [[ "${TEST_INGRESS:-0}" == 1 ]]; then network_tests; fi
[[ $(tf show -json | jq -r '.values.root_module.resources[] | select(.address == "random_pet.cluster") | .values.id') == "$original_random_name" ]] || fail 'random_pet.cluster rotated during acceptance.'
printf 'Upgrade acceptance checks passed. EXIT cleanup will destroy only this test root.\n'
