#!/usr/bin/env bash
# One-shot pre-flight checks for the cloudflare_workers_app_template.
#
# Runs (in order):
#   1. tofu fmt -check        -- formatting
#   2. tofu validate           -- syntax + basic schema
#   3. tflint (if installed)   -- provider-aware static analysis (resource names, deprecated args)
#   4. tofu test               -- native plan-mode tests under tests/
#
# Exits non-zero on the first failure. Designed for CI as well as local use.
# Requires: tofu. Optional: tflint. No CF credentials needed.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

echo "==> tofu fmt -check"
tofu fmt -check -recursive

echo "==> tofu init -backend=false"
# -backend=false: don't try to reach S3 just to lint. We're not applying.
tofu init -backend=false -input=false >/dev/null

echo "==> tofu validate"
tofu validate

if command -v tflint >/dev/null 2>&1; then
  echo "==> tflint --init"
  tflint --init >/dev/null
  echo "==> tflint"
  tflint
else
  echo "==> tflint not installed -- skipping (install with: brew install tflint)"
fi

echo "==> tofu test"
tofu test

echo ""
echo "All pre-flight checks passed."
