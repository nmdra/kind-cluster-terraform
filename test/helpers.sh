#!/usr/bin/env bash
# Shared disposable-cluster harness. Source this file; do not execute it directly.
set -euo pipefail

fail() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }
require_command() { command -v "$1" >/dev/null || fail "Required command not found: $1"; }

tf() { terraform -chdir="$TEST_ROOT" "$@"; }
kube() { kubectl --kubeconfig="$KUBECONFIG" --context="$CLUSTER_CONTEXT" --request-timeout=15s "$@"; }

cleanup_test() {
  local status=$? cleanup_failed=0
  trap - EXIT INT TERM
  set +e
  if declare -F cleanup_network >/dev/null; then
    cleanup_network || cleanup_failed=1
  fi
  # Keep the controller alive if fixture/proxy cleanup could not be confirmed.
  if (( cleanup_failed == 0 )) && [[ "$APPLY_ATTEMPTED" == 1 ]]; then
    tf destroy -input=false -auto-approve -no-color >"$TEST_ROOT/destroy.log" 2>&1 || cleanup_failed=1
  fi
  if (( cleanup_failed == 0 )) && declare -F cleanup_image >/dev/null; then
    cleanup_image || cleanup_failed=1
  fi
  if (( cleanup_failed != 0 )); then
    printf 'WARNING: cleanup incomplete. Resources may remain. Test root retained: %s\n' "$TEST_ROOT" >&2
    printf 'Review destroy.log and network diagnostics before manual cleanup.\n' >&2
    (( status != 0 )) || status=1
  elif (( status != 0 )); then
    printf 'Test failed; resources destroyed. Diagnostics retained: %s\n' "$TEST_ROOT" >&2
  else
    rm -rf -- "$TEST_ROOT"
  fi
  exit "$status"
}

setup_test() {
  [[ "${RUN_CLUSTER_TESTS:-}" == 1 ]] || fail 'Destructive test disabled. Set RUN_CLUSTER_TESTS=1 only after approval.'
  local command variable
  for command in terraform kubectl docker timeout; do require_command "$command"; done
  REPO_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
  # Ambient Terraform options must not redirect state, add user var files, or select a workspace.
  for variable in ${!TF_VAR_@} ${!TF_CLI_ARGS@}; do unset "$variable"; done
  unset TF_DATA_DIR TF_WORKSPACE TF_CLI_CONFIG_FILE
  export TF_IN_AUTOMATION=1 TF_INPUT=0
  # The provider, node image builder, and Docker CLI must use the same local daemon.
  [[ "${DOCKER_HOST:-unix:///var/run/docker.sock}" == unix:///var/run/docker.sock ]] || fail 'Tests require the local /var/run/docker.sock Docker daemon.'
  unset DOCKER_CONTEXT DOCKER_TLS_VERIFY DOCKER_CERT_PATH
  export DOCKER_HOST=unix:///var/run/docker.sock
  TEST_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/kind-tf-test.XXXXXXXX")
  APPLY_ATTEMPTED=0
  trap cleanup_test EXIT
  trap 'exit 130' INT
  trap 'exit 143' TERM
  cp "$REPO_ROOT"/*.tf "$REPO_ROOT/.terraform.lock.hcl" "$TEST_ROOT/"
  export KUBECONFIG="$TEST_ROOT/kubeconfig"
  CLUSTER_NAME="tf-test-$(basename "$TEST_ROOT" | tr '[:upper:].' '[:lower:]-')"
  CLUSTER_CONTEXT="kind-$CLUSTER_NAME"
  cat >"$TEST_ROOT/terraform.tfvars" <<EOF
kind_cluster_name = "$CLUSTER_NAME"
kind_cluster_config_path = "$KUBECONFIG"
control_plane_node_count = 1
worker_node_count = 1
ingress_port_mappings = []
enable_ingress_lb = false
docker_host = "unix:///var/run/docker.sock"
EOF
  printf 'Disposable test root: %s\n' "$TEST_ROOT"
}

init_test() { tf init -backend=false -input=false -lockfile=readonly; }
apply_test() {
  APPLY_ATTEMPTED=1
  tf apply -input=false -auto-approve "$@"
  local actual_context actual_name actual_path
  actual_context=$(tf output -raw cluster_context)
  actual_name=$(tf output -raw cluster_name)
  actual_path=$(tf output -raw kubeconfig_path)
  [[ "$actual_context" == "$CLUSTER_CONTEXT" && "$actual_name" == "$CLUSTER_NAME" && "$actual_path" == "$KUBECONFIG" ]] || fail 'Isolated output/context contract mismatch.'
  kube config get-contexts "$CLUSTER_CONTEXT" >/dev/null
}

assert_empty_plan() {
  local result=0
  tf plan -input=false -detailed-exitcode -no-color >"$TEST_ROOT/second-plan.log" 2>&1 || result=$?
  [[ "$result" == 0 ]] || { cat "$TEST_ROOT/second-plan.log"; fail "Second plan is not empty (exit $result)."; }
}

wait_nodes() { kube wait --for=condition=Ready nodes --all --timeout=300s; }
