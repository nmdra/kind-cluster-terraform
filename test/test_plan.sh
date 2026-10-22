#!/usr/bin/env bash
# Run mocked plan tests without loading the developer's local tfvars or state.
set -euo pipefail
# Do not inherit variable files, test flags, workspaces, or data paths from the caller.
for variable in ${!TF_VAR_@} ${!TF_CLI_ARGS@}; do unset "$variable"; done
unset TF_DATA_DIR TF_WORKSPACE
export TF_IN_AUTOMATION=1 TF_INPUT=0
ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
TEST_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/kind-plan.XXXXXXXX")
trap 'rm -rf -- "$TEST_ROOT"' EXIT
cp "$ROOT"/*.tf "$ROOT/.terraform.lock.hcl" "$TEST_ROOT/"
mkdir "$TEST_ROOT/test"
cp "$ROOT/test/upgrade.tftest.hcl" "$TEST_ROOT/test/"
terraform -chdir="$TEST_ROOT" init -backend=false -input=false -lockfile=readonly -no-color
terraform -chdir="$TEST_ROOT" test -test-directory=test -filter=test/upgrade.tftest.hcl -no-color
