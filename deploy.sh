#!/bin/bash

# LOX24 Cognito SMS Sender - Deployment Script
# This script automates the deployment of the Lambda function

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${GREEN}╔════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║  LOX24 Custom SMS Sender for AWS Cognito           ║${NC}"
echo -e "${GREEN}║  Deployment Script                                 ║${NC}"
echo -e "${GREEN}╚════════════════════════════════════════════════════╝${NC}"
echo ""

# Check if AWS CLI is installed
if ! command -v aws &> /dev/null; then
    echo -e "${RED}Error: AWS CLI is not installed${NC}"
    echo "Please install AWS CLI: https://aws.amazon.com/cli/"
    exit 1
fi

# Check if Node.js is installed
if ! command -v node &> /dev/null; then
    echo -e "${RED}Error: Node.js is not installed${NC}"
    echo "Please install Node.js: https://nodejs.org/"
    exit 1
fi

echo -e "${YELLOW}This script will:${NC}"
echo "  1. Install NPM dependencies"
echo "  2. Create deployment package"
echo "  3. Create/update Lambda function"
echo "  4. Configure environment variables"
echo ""

# Prompt for required information
read -p "Enter your LOX24 API Token: " -s LOX24_TOKEN
echo ""
read -p "Enter your LOX24 Sender ID: " LOX24_SENDER_ID
read -p "Enter AWS Region (default: eu-central-1): " AWS_REGION
AWS_REGION=${AWS_REGION:-eu-central-1}
read -p "Enter KMS Key ID: " KMS_KEY_ID
read -p "Enter KMS Key ARN: " KMS_KEY_ARN
read -p "Enter Lambda Function Name (default: lox24-cognito-sms-sender): " FUNCTION_NAME
FUNCTION_NAME=${FUNCTION_NAME:-lox24-cognito-sms-sender}
read -p "Enter Lambda Execution Role ARN (or press Enter to create new): " ROLE_ARN

echo ""
echo -e "${GREEN}Starting deployment...${NC}"
echo ""

# Step 1: Install dependencies
echo -e "${YELLOW}[1/4] Installing NPM dependencies...${NC}"
npm install --production

if [ $? -ne 0 ]; then
    echo -e "${RED}Failed to install dependencies${NC}"
    exit 1
fi

# Step 2: Create deployment package
echo -e "${YELLOW}[2/4] Creating deployment package...${NC}"
if [ -f "lox24-cognito-sms-lambda.zip" ]; then
    rm lox24-cognito-sms-lambda.zip
fi

zip -r lox24-cognito-sms-lambda.zip . -x "*.git*" -x "node_modules/.cache/*" -x "tests/*" -x "*.sh" -x "*.yaml" -x "*.md"

if [ $? -ne 0 ]; then
    echo -e "${RED}Failed to create deployment package${NC}"
    exit 1
fi

echo -e "${GREEN}✓ Deployment package created: lox24-cognito-sms-lambda.zip${NC}"

# Step 3: Create or update Lambda function
echo -e "${YELLOW}[3/4] Deploying Lambda function...${NC}"

# Check if function exists
aws lambda get-function --function-name "$FUNCTION_NAME" --region "$AWS_REGION" &> /dev/null
FUNCTION_EXISTS=$?

if [ $FUNCTION_EXISTS -eq 0 ]; then
    # Update existing function
    echo "Updating existing Lambda function..."
    aws lambda update-function-code \
        --function-name "$FUNCTION_NAME" \
        --zip-file fileb://lox24-cognito-sms-lambda.zip \
        --region "$AWS_REGION" \
        --no-cli-pager

    if [ $? -ne 0 ]; then
        echo -e "${RED}Failed to update Lambda function${NC}"
        exit 1
    fi
    
    echo -e "${GREEN}✓ Lambda function updated${NC}"
else
    # Create new function
    if [ -z "$ROLE_ARN" ]; then
        echo -e "${RED}Error: Lambda execution role ARN is required to create new function${NC}"
        echo "Please create IAM role first or provide existing role ARN"
        exit 1
    fi
    
    echo "Creating new Lambda function..."
    aws lambda create-function \
        --function-name "$FUNCTION_NAME" \
        --runtime nodejs18.x \
        --role "$ROLE_ARN" \
        --handler index.handler \
        --zip-file fileb://lox24-cognito-sms-lambda.zip \
        --timeout 30 \
        --memory-size 256 \
        --region "$AWS_REGION" \
        --no-cli-pager

    if [ $? -ne 0 ]; then
        echo -e "${RED}Failed to create Lambda function${NC}"
        exit 1
    fi
    
    echo -e "${GREEN}✓ Lambda function created${NC}"
fi

# Step 4: Update environment variables
echo -e "${YELLOW}[4/4] Configuring environment variables...${NC}"

aws lambda update-function-configuration \
    --function-name "$FUNCTION_NAME" \
    --environment "Variables={
        LOX24_AUTH_TOKEN=$LOX24_TOKEN,
        LOX24_SENDER_ID=$LOX24_SENDER_ID,
        KMS_KEY_ID=$KMS_KEY_ID,
        KMS_KEY_ARN=$KMS_KEY_ARN,
        LOX24_API_HOST=api.lox24.eu,
        LOX24_SERVICE_CODE=direct,
        ENABLE_DEBUG_LOGGING=false
    }" \
    --region "$AWS_REGION" \
    --no-cli-pager

if [ $? -ne 0 ]; then
    echo -e "${RED}Failed to configure environment variables${NC}"
    exit 1
fi

echo -e "${GREEN}✓ Environment variables configured${NC}"

# Get function ARN
FUNCTION_ARN=$(aws lambda get-function --function-name "$FUNCTION_NAME" --region "$AWS_REGION" --query 'Configuration.FunctionArn' --output text)

echo ""
echo -e "${GREEN}╔════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║  Deployment Completed Successfully!                ║${NC}"
echo -e "${GREEN}╚════════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "${YELLOW}Function Details:${NC}"
echo "  Name: $FUNCTION_NAME"
echo "  ARN: $FUNCTION_ARN"
echo "  Region: $AWS_REGION"
echo ""
echo -e "${YELLOW}Next Steps:${NC}"
echo "  1. Go to AWS Cognito Console"
echo "  2. Select your User Pool"
echo "  3. Navigate to: User pool properties → Lambda triggers"
echo "  4. Click 'Add Lambda trigger'"
echo "  5. Select trigger type: 'Custom message'"
echo "  6. For 'Custom SMS sender', select: $FUNCTION_NAME"
echo "  7. Select KMS key ID: $KMS_KEY_ID"
echo "  8. Save changes"
echo ""
echo -e "${GREEN}Test your integration by triggering a sign-up or authentication!${NC}"
echo ""
echo -e "${YELLOW}View logs:${NC}"
echo "  aws logs tail /aws/lambda/$FUNCTION_NAME --follow --region $AWS_REGION"
echo ""
