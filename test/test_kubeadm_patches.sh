#!/bin/bash
set -e

cd "$(dirname "$0")/.."

echo "Creating test.tfvars..."
cat <<EOF > test.tfvars
kubeadm_config_patches = [
  <<-EOT
  kind: InitConfiguration
  nodeRegistration:
    kubeletExtraArgs:
      node-labels: "my-custom-test-label=true"
  EOT
  ,
  <<-EOT
  kind: JoinConfiguration
  nodeRegistration:
    kubeletExtraArgs:
      node-labels: "my-custom-test-label=true"
  EOT
]
EOF

echo "Running terraform apply..."
terraform apply -var-file=test.tfvars -auto-approve

echo "Verifying node labels..."
KUBECONFIG_PATH=$(terraform output -raw kubeconfig_path 2>/dev/null || echo "")
if [ -z "$KUBECONFIG_PATH" ]; then
  echo "Error: Kubeconfig path not found."
  exit 1
fi

# Kind config path might contain ~, we need to expand it if used directly with kubectl,
# but terraform output usually gives absolute path if pathexpand was used.
KUBECONFIG_EXPANDED=$(eval echo $KUBECONFIG_PATH)
export KUBECONFIG=$KUBECONFIG_EXPANDED

# Wait for nodes to be ready
echo "Waiting for nodes to be ready..."
kubectl wait --for=condition=Ready nodes --all --timeout=120s

# Check if any node has the label my-custom-test-label=true
echo "Checking for labeled nodes..."
NODE_COUNT=$(kubectl get nodes -l my-custom-test-label=true --no-headers 2>/dev/null | grep -c . || true)

if [ "$NODE_COUNT" -gt 0 ]; then
  echo "Success: Found $NODE_COUNT node(s) with label my-custom-test-label=true"
else
  echo "Error: No nodes found with the expected label."
  kubectl get nodes --show-labels
  terraform destroy -var-file=test.tfvars -auto-approve
  rm test.tfvars
  exit 1
fi

echo "Cleaning up..."
terraform destroy -var-file=test.tfvars -auto-approve
rm test.tfvars

echo "Test passed successfully!"
