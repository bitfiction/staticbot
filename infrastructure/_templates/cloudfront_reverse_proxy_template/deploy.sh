#!/usr/bin/env bash
#
# Interactive deployment script for the CloudFront Reverse Proxy template.
# Prompts for required values and generates a terraform.tfvars file,
# then runs tofu/terraform init + plan + apply.
#
# Prerequisites:
#   - AWS CLI configured (aws sts get-caller-identity should work)
#   - OpenTofu (tofu) or Terraform (terraform) installed
#
# Usage:
#   chmod +x deploy.sh
#   ./deploy.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TFVARS_FILE="$SCRIPT_DIR/terraform.tfvars"

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

TF_CMD=""
detect_tf() {
  if command -v tofu &>/dev/null; then
    TF_CMD="tofu"
  elif command -v terraform &>/dev/null; then
    TF_CMD="terraform"
  else
    echo "Error: Neither 'tofu' nor 'terraform' found in PATH."
    echo "Install OpenTofu: https://opentofu.org/docs/intro/install/"
    echo "Install Terraform: https://developer.hashicorp.com/terraform/install"
    exit 1
  fi
  echo "Using: $TF_CMD ($(${TF_CMD} version | head -1))"
}

prompt() {
  local var_name="$1" prompt_text="$2" default="${3:-}"
  local value
  if [ -n "$default" ]; then
    read -rp "$prompt_text [$default]: " value
    value="${value:-$default}"
  else
    read -rp "$prompt_text: " value
  fi
  eval "$var_name=\"\$value\""
}

prompt_yn() {
  local var_name="$1" prompt_text="$2" default="${3:-n}"
  local value
  read -rp "$prompt_text [y/n] ($default): " value
  value="${value:-$default}"
  if [[ "$value" =~ ^[Yy] ]]; then
    eval "$var_name=true"
  else
    eval "$var_name=false"
  fi
}

# ---------------------------------------------------------------------------
# Collect inputs
# ---------------------------------------------------------------------------

echo ""
echo "============================================================"
echo "  CloudFront Reverse Proxy — Interactive Setup"
echo "============================================================"
echo ""
echo "This script will create a CloudFront distribution that"
echo "proxies requests to PostHog (or any HTTP origin)."
echo ""
echo "Docs: https://posthog.com/docs/advanced/proxy/cloudfront"
echo ""

detect_tf
echo ""

# Check AWS credentials
echo "Checking AWS credentials..."
if ! aws sts get-caller-identity &>/dev/null; then
  echo "Error: AWS credentials not configured. Run 'aws configure' first."
  exit 1
fi
AWS_ACCOUNT=$(aws sts get-caller-identity --query Account --output text)
echo "AWS Account: $AWS_ACCOUNT"
echo ""

# --- Project name ---
prompt PROJECT_NAME "Project name (used for resource naming)" "posthog-proxy"

# --- Origin ---
echo ""
echo "--- Origin Configuration ---"
echo "  1) PostHog US  (us.i.posthog.com)"
echo "  2) PostHog EU  (eu.i.posthog.com)"
echo "  3) Custom origin"
prompt ORIGIN_CHOICE "Choose origin [1/2/3]" "1"

POSTHOG_REGION="us"
API_ORIGIN=""
ASSETS_ORIGIN=""

case "$ORIGIN_CHOICE" in
  2)
    POSTHOG_REGION="eu"
    ;;
  3)
    prompt API_ORIGIN "API origin domain (e.g. api.example.com)" ""
    prompt ASSETS_ORIGIN "Assets origin domain (e.g. assets.example.com)" ""
    ;;
  *)
    POSTHOG_REGION="us"
    ;;
esac

# --- Custom domain ---
echo ""
echo "--- Custom Domain (optional) ---"
echo "Leave empty to use the default *.cloudfront.net URL."
echo "If set, must be a subdomain (e.g. e.example.com), NOT a root domain."
echo ""
prompt CUSTOM_DOMAIN "Custom domain" ""

HOSTED_ZONE_ID=""
USE_EXISTING_HZ="false"
USE_EXISTING_HZ_ID=""
USE_EXISTING_CERT="false"
USE_EXISTING_CERT_DOMAIN=""

if [ -n "$CUSTOM_DOMAIN" ]; then
  # Validate not a root domain (must have at least 2 dots, or 3 for two-part TLDs)
  DOT_COUNT=$(echo "$CUSTOM_DOMAIN" | tr -cd '.' | wc -c | tr -d ' ')
  if [ "$DOT_COUNT" -lt 2 ]; then
    echo ""
    echo "WARNING: '$CUSTOM_DOMAIN' looks like a root domain."
    echo "Deploying a proxy on a root domain will overwrite existing DNS records."
    echo "Use a subdomain instead, e.g. e.$CUSTOM_DOMAIN"
    echo ""
    prompt CUSTOM_DOMAIN "Enter a subdomain" "e.$CUSTOM_DOMAIN"
  fi

  # Extract parent domain for hosted zone lookup
  PARENT_DOMAIN=$(echo "$CUSTOM_DOMAIN" | cut -d. -f2-)

  echo ""
  echo "--- DNS & Certificate ---"
  prompt_yn USE_EXISTING_HZ "Do you have an existing Route53 hosted zone for '$PARENT_DOMAIN'?" "y"

  if [ "$USE_EXISTING_HZ" = "true" ]; then
    echo ""
    echo "Looking up hosted zone for '$PARENT_DOMAIN'..."
    HZ_ID=$(aws route53 list-hosted-zones-by-name --dns-name "$PARENT_DOMAIN" --max-items 1 \
      --query "HostedZones[?Name=='${PARENT_DOMAIN}.'].Id" --output text 2>/dev/null | sed 's|/hostedzone/||' || true)
    if [ -n "$HZ_ID" ] && [ "$HZ_ID" != "None" ]; then
      echo "Found hosted zone: $HZ_ID"
      USE_EXISTING_HZ_ID="$HZ_ID"
    else
      echo "Could not find hosted zone automatically."
      prompt USE_EXISTING_HZ_ID "Enter the hosted zone ID manually" ""
    fi
  else
    prompt HOSTED_ZONE_ID "Enter the Route53 Hosted Zone ID for '$PARENT_DOMAIN'" ""
  fi

  echo ""
  prompt_yn USE_EXISTING_CERT "Do you have an existing ACM certificate that covers '$CUSTOM_DOMAIN'?" "n"
  if [ "$USE_EXISTING_CERT" = "true" ]; then
    prompt USE_EXISTING_CERT_DOMAIN "Certificate domain to look up (e.g. '*.${PARENT_DOMAIN}' or '${PARENT_DOMAIN}')" "*.${PARENT_DOMAIN}"
  fi
fi

# --- Price class ---
echo ""
echo "--- CloudFront Price Class ---"
echo "  PriceClass_100 = US, Canada, Europe (cheapest)"
echo "  PriceClass_200 = + Asia, Middle East, Africa"
echo "  PriceClass_All = All edge locations"
prompt PRICE_CLASS "Price class" "PriceClass_100"

# ---------------------------------------------------------------------------
# Generate terraform.tfvars
# ---------------------------------------------------------------------------

echo ""
echo "--- Generating terraform.tfvars ---"

cat > "$TFVARS_FILE" <<EOF
project_name = "${PROJECT_NAME}"

# Origin
posthog_region       = "${POSTHOG_REGION}"
api_origin_domain    = "${API_ORIGIN}"
assets_origin_domain = "${ASSETS_ORIGIN}"

# Custom domain
custom_domain  = "${CUSTOM_DOMAIN}"
hosted_zone_id = "${HOSTED_ZONE_ID}"

# Reuse existing resources
use_existing_hosted_zone        = "${USE_EXISTING_HZ}"
use_existing_hosted_zone_id     = "${USE_EXISTING_HZ_ID}"
use_existing_certificate        = "${USE_EXISTING_CERT}"
use_existing_certificate_domain = "${USE_EXISTING_CERT_DOMAIN}"

# Distribution settings
price_class = "${PRICE_CLASS}"

common_tags = {
  Project   = "${PROJECT_NAME}"
  ManagedBy = "Terraform"
}
EOF

echo "Written to: $TFVARS_FILE"
echo ""

# ---------------------------------------------------------------------------
# Show summary and confirm
# ---------------------------------------------------------------------------

echo "============================================================"
echo "  Deployment Summary"
echo "============================================================"
echo ""
echo "  Project:       $PROJECT_NAME"
echo "  AWS Account:   $AWS_ACCOUNT"
if [ "$ORIGIN_CHOICE" = "3" ]; then
  echo "  API Origin:    $API_ORIGIN"
  echo "  Assets Origin: $ASSETS_ORIGIN"
else
  echo "  PostHog:       $POSTHOG_REGION"
fi
if [ -n "$CUSTOM_DOMAIN" ]; then
  echo "  Domain:        $CUSTOM_DOMAIN"
  echo "  Existing HZ:   $USE_EXISTING_HZ (${USE_EXISTING_HZ_ID:-n/a})"
  echo "  Existing Cert: $USE_EXISTING_CERT (${USE_EXISTING_CERT_DOMAIN:-n/a})"
else
  echo "  Domain:        (auto — *.cloudfront.net)"
fi
echo "  Price Class:   $PRICE_CLASS"
echo ""

prompt_yn PROCEED "Proceed with deployment?" "y"
if [ "$PROCEED" != "true" ]; then
  echo "Aborted. Your terraform.tfvars has been saved — you can run '$TF_CMD apply' manually."
  exit 0
fi

# ---------------------------------------------------------------------------
# Deploy
# ---------------------------------------------------------------------------

cd "$SCRIPT_DIR"

# Remove S3 backend for local use — init with local state
echo ""
echo "--- Initializing (local state) ---"
$TF_CMD init -backend=false

echo ""
echo "--- Planning ---"
$TF_CMD plan -out=tfplan

echo ""
prompt_yn APPLY "Apply this plan?" "y"
if [ "$APPLY" != "true" ]; then
  echo "Plan saved to 'tfplan'. Run '$TF_CMD apply tfplan' when ready."
  exit 0
fi

echo ""
echo "--- Applying ---"
$TF_CMD apply tfplan

echo ""
echo "============================================================"
echo "  Deployment Complete"
echo "============================================================"
echo ""
$TF_CMD output
echo ""
echo "Next step: Update your PostHog SDK initialization:"
echo ""
PROXY_URL=$($TF_CMD output -raw proxy_url 2>/dev/null || echo "https://<your-cloudfront-domain>")
echo "  posthog.init('phc_your_project_token', {"
echo "    api_host: '${PROXY_URL}',"
echo "    ui_host: 'https://${POSTHOG_REGION}.posthog.com'"
echo "  })"
echo ""
