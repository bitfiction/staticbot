# setup-prerequisites.sh
#!/bin/bash

set -euo pipefail

# Configuration (can be moved to a config file)
BASE_STATE_BUCKET_NAME="terraform-state"
DYNAMODB_TABLE="terraform-state-locks"
TERRAFORM_ROLE_NAME="terraform-role"
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

create_state_bucket() {
    local business=$1
    local account_id=$2
    local bucket_name="${business}-${BASE_STATE_BUCKET_NAME}"
    
    if aws s3api head-bucket --bucket "$bucket_name" 2>/dev/null; then
        log_warn "State bucket ${bucket_name} already exists"
        return
    fi
    
    log_info "Creating state bucket: ${bucket_name}"
    
    # Create bucket
    aws s3api create-bucket \
        --bucket "$bucket_name" \
        --region "$AWS_REGION" \
        --create-bucket-configuration LocationConstraint="$AWS_REGION"

    # Enable versioning
    aws s3api put-bucket-versioning \
        --bucket "$bucket_name" \
        --versioning-configuration Status=Enabled

    # Enable encryption
    aws s3api put-bucket-encryption \
        --bucket "$bucket_name" \
        --server-side-encryption-configuration '{
            "Rules": [
                {
                    "ApplyServerSideEncryptionByDefault": {
                        "SSEAlgorithm": "AES256"
                    }
                }
            ]
        }'

    # Block public access
    aws s3api put-public-access-block \
        --bucket "$bucket_name" \
        --public-access-block-configuration '{
            "BlockPublicAcls": true,
            "IgnorePublicAcls": true,
            "BlockPublicPolicy": true,
            "RestrictPublicBuckets": true
        }'
}

create_dynamodb_table() {
    local business=$1
    local table_name="${business}-${DYNAMODB_TABLE}"
    
    if aws dynamodb describe-table --table-name "$table_name" 2>/dev/null; then
        log_warn "DynamoDB table ${table_name} already exists"
        return
    fi
    
    log_info "Creating DynamoDB table: ${table_name}"
    
    aws dynamodb create-table \
        --table-name "$table_name" \
        --attribute-definitions AttributeName=LockID,AttributeType=S \
        --key-schema AttributeName=LockID,KeyType=HASH \
        --billing-mode PAY_PER_REQUEST \
        --region "$AWS_REGION"
        
    aws dynamodb wait table-exists --table-name "$table_name"
}

create_terraform_role() {
    local business=$1
    local account_id=$2
    local role_name="${business}-${TERRAFORM_ROLE_NAME}"
    
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
                        "AWS": "arn:aws:iam::'$account_id':root"
                    },
                    "Action": "sts:AssumeRole"
                }
            ]
        }'

    # Create policy
    aws iam put-role-policy \
        --role-name "$role_name" \
        --policy-name "${business}TerraformPolicy" \
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
    local business=$1
    local account_id=$2

    log_info "Setting up prerequisites for ${business} business (Account: ${account_id})"
    
    check_prerequisites
    # create_state_bucket "$business" "$account_id"
    # create_dynamodb_table "$business"
    create_terraform_role "$business" "$account_id"

    log_info "Prerequisites setup complete!"
    # log_info "State bucket: ${business}-${BASE_STATE_BUCKET_NAME}"
    # log_info "DynamoDB table: ${business}-${DYNAMODB_TABLE}"
    log_info "IAM role: ${business}-${TERRAFORM_ROLE_NAME}"
}

if [ $# -ne 2 ]; then
    echo "Usage: $0 <business> <aws-account-id>"
    echo "Example: $0 prod 111111111111"
    exit 1
fi

main "$1" "$2"