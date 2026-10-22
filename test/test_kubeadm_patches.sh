#!/usr/bin/env bash
set -euo pipefail
# shellcheck source-path=SCRIPTDIR
# shellcheck source=helpers.sh
source "$(dirname "$0")/helpers.sh"
setup_test
require_command jq
cat >"$TEST_ROOT/patches.auto.tfvars" <<'EOF'
enable_feature_gates = true
feature_gates = { GenericWorkload = true }
enable_runtime_config = true
runtime_config = { "scheduling.k8s.io/v1beta1" = "true" }
kubeadm_config_patches = [
  <<-EOT
  apiVersion: kubeadm.k8s.io/v1beta4
  kind: InitConfiguration
  nodeRegistration:
    kubeletExtraArgs:
    - name: node-labels
      value: my-custom-test-label=true
  EOT
  ,
  <<-EOT
  apiVersion: kubeadm.k8s.io/v1beta4
  kind: JoinConfiguration
  nodeRegistration:
    kubeletExtraArgs:
    - name: node-labels
      value: my-custom-test-label=true
  EOT
]
EOF
init_test
apply_test -no-color
wait_nodes
[[ $(kube get nodes -o name | wc -l) -eq 2 ]] || fail 'Expected two nodes.'
[[ $(kube get nodes -l my-custom-test-label=true -o name | wc -l) -eq 2 ]] || fail 'Both nodes must have the kubeadm label.'
# Query discovery directly so a missing group/version fails instead of using a cached list.
kube get --raw /apis/scheduling.k8s.io/v1beta1 >"$TEST_ROOT/scheduling-discovery.json"
jq -e '([.resources[].name] | index("workloads") != null) and ([.resources[].name] | index("podgroups") != null)' \
  "$TEST_ROOT/scheduling-discovery.json" >/dev/null
printf 'Kubeadm label and scheduling discovery checks passed.\n'
