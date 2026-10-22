#!/usr/bin/env bash
set -euo pipefail
# shellcheck source-path=SCRIPTDIR
# shellcheck source=helpers.sh
source "$(dirname "$0")/helpers.sh"
setup_test
mkdir -p "$TEST_ROOT/admission/validating-policies" "$TEST_ROOT/admission/mutating-policies"
cat >"$TEST_ROOT/admission/admission-config.yaml" <<'EOF'
apiVersion: apiserver.config.k8s.io/v1
kind: AdmissionConfiguration
plugins:
- name: ValidatingAdmissionPolicy
  configuration:
    apiVersion: apiserver.config.k8s.io/v1
    kind: ValidatingAdmissionPolicyConfiguration
    staticManifestsDir: /etc/kubernetes/admission/validating-policies/
- name: MutatingAdmissionPolicy
  configuration:
    apiVersion: apiserver.config.k8s.io/v1
    kind: MutatingAdmissionPolicyConfiguration
    staticManifestsDir: /etc/kubernetes/admission/mutating-policies/
EOF
cat >"$TEST_ROOT/admission.auto.tfvars" <<EOF
# Beta and default-on in 1.37; explicit true also tests feature-gate forwarding.
enable_feature_gates = true
feature_gates = { ManifestBasedAdmissionControlConfig = true }
extra_mounts = [{
  host_path = "$TEST_ROOT/admission"
  container_path = "/etc/kubernetes/admission"
  read_only = true
}]
kubeadm_config_patches = [
  <<-EOT
  apiVersion: kubeadm.k8s.io/v1beta4
  kind: ClusterConfiguration
  apiServer:
    extraArgs:
    - name: admission-control-config-file
      value: /etc/kubernetes/admission/admission-config.yaml
    extraVolumes:
    - name: admission-policies
      hostPath: /etc/kubernetes/admission
      mountPath: /etc/kubernetes/admission
      readOnly: true
      pathType: Directory
  EOT
]
EOF
init_test
apply_test -no-color
wait_nodes
kube wait --for=condition=Ready pod -n kube-system -l component=kube-apiserver --timeout=180s
args=$(kube get pods -n kube-system -l component=kube-apiserver -o jsonpath='{.items[*].spec.containers[*].command}')
[[ "$args" == *'--admission-control-config-file=/etc/kubernetes/admission/admission-config.yaml'* ]] || fail 'API server admission argument missing.'
[[ "$args" == *'ManifestBasedAdmissionControlConfig=true'* ]] || fail 'Explicit admission gate missing.'
printf 'Admission configuration and explicit feature gate verified.\n'
