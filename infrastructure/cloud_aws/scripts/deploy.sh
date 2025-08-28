# deploy.sh
#!/bin/bash

# Function to deploy a specific website stage
deploy_stage() {
    local website=$1
    local stage=$2
    local full_domain="${stage}.${website}"
    echo "Deploying stage '${stage}' for website '${website}' (${full_domain})"
    tofu plan -target="module.static_website[\"${full_domain}\"]"
    tofu apply -auto-approve -target="module.static_website[\"${full_domain}\"]"
}

# Function to deploy all websites in an account
deploy_account() {
    local account=$1
    echo "Deploying all websites in account ${account}"
    # This will deploy all resources in the account
    tofu plan
    tofu apply
}

# Example usage:

# 1. Deploy single stage of a website
# ./deploy.sh stage example.com dev

# 2. Deploy all stages of a website
# ./deploy.sh website example.com

# 3. Deploy everything in an account
# ./deploy.sh account account2

case $1 in
    stage)
        deploy_stage $2 $3
        ;;
    account)
        deploy_account $2
        ;;
    *)
        echo "Usage:"
        echo "  Deploy single stage: ./deploy.sh stage <website_domain> <stage_subdomain>"
        echo "  Deploy full account: ./deploy.sh account <account_name>"
        ;;
esac
