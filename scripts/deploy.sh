# deploy.sh
#!/bin/bash

# Function to deploy a specific website stage
deploy_stage() {
    local website=$1
    local stage=$2
    echo "Deploying ${website} - ${stage}"
    tofu plan -target="module.static_website[\"${website}-${stage}\"]"
    tofu apply -target="module.static_website[\"${website}-${stage}\"]"
}

# Function to deploy all stages of a website
deploy_website() {
    local website=$1
    echo "Deploying all stages of ${website}"
    tofu plan -target="module.static_website[\"${website}-*\"]"
    tofu apply -target="module.static_website[\"${website}-*\"]"
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
    website)
        deploy_website $2
        ;;
    account)
        deploy_account $2
        ;;
    *)
        echo "Usage:"
        echo "  Deploy single stage: ./deploy.sh stage <website> <stage>"
        echo "  Deploy full website: ./deploy.sh website <website>"
        echo "  Deploy full account: ./deploy.sh account <account>"
        ;;
esac