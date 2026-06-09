#!/bin/bash
set -e

cd "$(dirname "$0")/.."

echo "Creating admission directory and config..."
mkdir -p admission/validating-policies admission/mutating-policies
cat <<EOF > admission/admission-config.yaml
# AdmissionConfiguration for manifest-based admission control.
# Pass to kube-apiserver via --admission-control-config-file
apiVersion: apiserver.config.k8s.io/v1
kind: AdmissionConfiguration
plugins:
- name: ValidatingAdmissionPolicy
  configuration:
    apiVersion: apiserver.config.k8s.io/v1
    kind: ValidatingAdmissionPolicyConfiguration
    staticManifestsDir: "/etc/kubernetes/admission/validating-policies/"
- name: MutatingAdmissionPolicy
  configuration:
    apiVersion: apiserver.config.k8s.io/v1
    kind: MutatingAdmissionPolicyConfiguration
    staticManifestsDir: "/etc/kubernetes/admission/mutating-policies/"
EOF

echo "Creating test-admission.tfvars..."
cat <<EOF > test-admission.tfvars
enable_feature_gates = true
feature_gates = {
  "ManifestBasedAdmissionControlConfig" = true
}

extra_mounts = [
  {
    host_path      = "./admission"
    container_path = "/etc/kubernetes/admission"
    read_only      = true
  }
]

kubeadm_config_patches = [
  <<-EOT
  kind: ClusterConfiguration
  apiServer:
    extraArgs:
      admission-control-config-file: /etc/kubernetes/admission/admission-config.yaml
    extraVolumes:
    - name: admission-policies
      hostPath: /etc/kubernetes/admission
      mountPath: /etc/kubernetes/admission
      readOnly: true
  EOT
]
EOF

echo "Running terraform fmt and validate..."
terraform fmt
terraform validate

echo "Running terraform apply..."
terraform apply -var-file=test-admission.tfvars -auto-approve

echo "Verifying API server pod args for admission-control-config-file..."
KUBECONFIG_PATH=$(terraform output -raw kubeconfig_path 2>/dev/null || echo "")
if [ -z "$KUBECONFIG_PATH" ]; then
  echo "Error: Kubeconfig path not found."
  exit 1
fi

KUBECONFIG_EXPANDED=$(eval echo $KUBECONFIG_PATH)
export KUBECONFIG=$KUBECONFIG_EXPANDED

echo "Waiting for pods in kube-system..."
kubectl wait --for=condition=Ready pod -n kube-system -l component=kube-apiserver --timeout=120s || true

# Check the API server pod configuration
POD_NAME=$(kubectl get pods -n kube-system -l component=kube-apiserver -o jsonpath='{.items[0].metadata.name}')
echo "Found API server pod: $POD_NAME"

echo "Checking if extra arg is present..."
if kubectl get pod "$POD_NAME" -n kube-system -o yaml | grep -q "admission-control-config-file=/etc/kubernetes/admission/admission-config.yaml"; then
  echo "API server arg verified!"
else
  echo "Error: API server arg not found in pod spec."
  kubectl get pod "$POD_NAME" -n kube-system -o yaml
  terraform destroy -var-file=test-admission.tfvars -auto-approve
  rm -rf admission test-admission.tfvars
  exit 1
fi

echo "Cleaning up..."
terraform destroy -var-file=test-admission.tfvars -auto-approve
rm -rf admission test-admission.tfvars

echo "Test passed successfully!"
