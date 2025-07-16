#!/bin/bash

# NBA Queue Project Deployment Script
# This script deploys the NBA Queue project to a Salesforce org

echo "Starting NBA Queue Project deployment..."

# Check if SF CLI is installed
if ! command -v sf &> /dev/null; then
    echo "Error: SF CLI is not installed. Please install it first."
    exit 1
fi

# Check if org alias is provided
if [ -z "$1" ]; then
    echo "Usage: ./deploy.sh <org-alias>"
    echo "Example: ./deploy.sh myorg"
    exit 1
fi

ORG_ALIAS=$1

echo "Deploying to org: $ORG_ALIAS"

# Deploy the source
echo "Deploying source metadata..."
sf project deploy start --source-dir force-app --target-org $ORG_ALIAS

if [ $? -eq 0 ]; then
    echo "✅ Deployment successful!"
    echo ""
    echo "Next steps:"
    echo "1. Assign NBA Queue permissions to users"
    echo "2. Add the NBA Queue Widget to Lightning pages"
    echo "3. Configure your external system integration"
    echo "4. Test the REST endpoint: /services/apexrest/nba-queue/"
    echo ""
    echo "Integration endpoint: https://<your-domain>.salesforce.com/services/apexrest/nba-queue/"
else
    echo "❌ Deployment failed. Please check the errors above."
    exit 1
fi