# setup-prerequisites.sh
#!/bin/bash

set -euo pipefail

# Configuration (can be moved to a config file)
BASE_STATE_BUCKET_NAME="tf-state"
DYNAMODB_TABLE="tf-state-locks"
TERRAFORM_ROLE_NAME="tf-role"
AWS_REGION="eu-central-1"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log_info() { echo -e "${GREEN}INFO: $1${NC}"; }
log_warn() { echo -e "${YELLOW}WARN: $1${NC}"; }
log_error() { echo -e "${RED}ERROR: $1${NC}"; }

check_prerequisites() {
    if ! command -v aws &> /dev/null; then
        log_error "AWS CLI is not installed"
        exit 1
    fi
    
    if ! aws sts get-caller-identity &> /dev/null; then
        log_error "AWS credentials not configured"
        exit 1
    fi
}

create_terraform_role() {
    local account_name=$1
    local account_id=$2
    local trusted_account_id=$3
    local role_name="${account_name}-${TERRAFORM_ROLE_NAME}"
    
    if aws iam get-role --role-name "$role_name" 2>/dev/null; then
        log_warn "IAM role ${role_name} already exists"
        return
    fi
    
    log_info "Creating IAM role: ${role_name}"
    
    # Create role
    aws iam create-role \
        --role-name "$role_name" \
        --assume-role-policy-document '{
            "Version": "2012-10-17",
            "Statement": [
                {
                    "Effect": "Allow",
                    "Principal": {
                        "AWS": "arn:aws:iam::'${trusted_account_id}':root"
                    },
                    "Action": "sts:AssumeRole"
                }
            ]
        }'

    # Create policy
    aws iam put-role-policy \
        --role-name "$role_name" \
        --policy-name "${account_name}TerraformPolicy" \
        --policy-document '{
            "Version": "2012-10-17",
            "Statement": [
                {
                    "Effect": "Allow",
                    "Action": [
                        "s3:*",
                        "cloudfront:*",
                        "route53:*",
                        "acm:*",
                        "iam:*",
                        "dynamodb:*"
                    ],
                    "Resource": "*"
                }
            ]
        }'
}

main() {
    local account_name=$1
    local account_id=$2
    local trusted_account_id=$3

    log_info "Setting up prerequisites for ${account_name} in target account ${account_id}"
    log_info "The role will trust the management account: ${trusted_account_id}"
    
    check_prerequisites
    create_terraform_role "$account_name" "$account_id" "$trusted_account_id"

    log_info "Prerequisites setup complete!"
    log_info "IAM role created: ${account_name}-${TERRAFORM_ROLE_NAME} in account ${account_id}"
}

if [ $# -ne 3 ]; then
    echo "Usage: $0 <account_name> <target_aws_account_id> <trusted_management_account_id>"
    echo "Example: $0 myclient 111122223333 999988887777"
    exit 1
fi

main "$1" "$2" "$3"
