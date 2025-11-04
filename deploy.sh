#!/bin/bash

# LOX24 Cognito SMS Sender - Enhanced Deployment Script v2.1 (FIXED)
# This script automates the deployment with extensive checks and debugging

# Removed 'set -e' to prevent silent failures - using explicit error handling instead

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Debug mode (set DEBUG=true for verbose output)
DEBUG=${DEBUG:-false}

# Log file
LOG_FILE="/tmp/lox24-deploy-$(date +%Y%m%d-%H%M%S).log"

# Function to log messages
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >> "$LOG_FILE"
}

# Function to print debug info
debug() {
    if [ "$DEBUG" = "true" ]; then
        echo -e "${BLUE}[DEBUG] $1${NC}"
        log "DEBUG: $1"
    fi
}

# Function to print step header
step_header() {
    echo ""
    echo -e "${GREEN}═══════════════════════════════════════════════════${NC}"
    echo -e "${GREEN}  $1${NC}"
    echo -e "${GREEN}═══════════════════════════════════════════════════${NC}"
    log "STEP: $1"
}

# Function to check AWS command success
check_aws_command() {
    local cmd="$1"
    local description="$2"

    debug "Running: $cmd"

    if output=$(eval "$cmd" 2>&1); then
        local exit_code=$?
        if [ $exit_code -eq 0 ]; then
            debug "Success: $description"
            echo "$output"
            return 0
        else
            echo -e "${RED}✗ Failed: $description${NC}" >&2
            echo -e "${RED}Exit code: $exit_code${NC}" >&2
            echo -e "${RED}Error output:${NC}" >&2
            echo "$output" >&2
            log "Failed: $description - Exit code: $exit_code - Output: $output"
            return $exit_code
        fi
    else
        local exit_code=$?
        echo -e "${RED}✗ Failed: $description${NC}" >&2
        echo -e "${RED}Exit code: $exit_code${NC}" >&2
        echo -e "${RED}Error output:${NC}" >&2
        echo "$output" >&2
        log "Failed: $description - Exit code: $exit_code - Output: $output"
        return $exit_code
    fi
}

echo -e "${GREEN}╔════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║  LOX24 Custom SMS Sender for AWS Cognito          ║${NC}"
echo -e "${GREEN}║  Enhanced Deployment Script v2.1 (FIXED)          ║${NC}"
echo -e "${GREEN}╚════════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "${CYAN}Log file: $LOG_FILE${NC}"
echo ""

log "=== Deployment started ==="

# ═══════════════════════════════════════════════════
# PRE-FLIGHT CHECKS
# ═══════════════════════════════════════════════════

step_header "Step 1/8: Pre-flight Checks"

echo -n "Checking AWS CLI... "
if ! command -v aws &> /dev/null; then
    echo -e "${RED}✗ Not installed${NC}"
    echo "Please install AWS CLI: https://aws.amazon.com/cli/"
    exit 1
fi
AWS_CLI_VERSION=$(aws --version 2>&1 | head -n1 | cut -d' ' -f1)
echo -e "${GREEN}✓ $AWS_CLI_VERSION${NC}"
log "AWS CLI: $AWS_CLI_VERSION"

echo -n "Checking Node.js... "
if ! command -v node &> /dev/null; then
    echo -e "${RED}✗ Not installed${NC}"
    echo "Please install Node.js: https://nodejs.org/"
    exit 1
fi
NODE_VERSION=$(node --version)
echo -e "${GREEN}✓ $NODE_VERSION${NC}"
log "Node.js: $NODE_VERSION"

echo -n "Checking NPM... "
if ! command -v npm &> /dev/null; then
    echo -e "${RED}✗ Not installed${NC}"
    exit 1
fi
NPM_VERSION=$(npm --version)
echo -e "${GREEN}✓ v$NPM_VERSION${NC}"
log "NPM: v$NPM_VERSION"

echo -n "Checking AWS credentials... "
if ! AWS_IDENTITY=$(aws sts get-caller-identity 2>&1); then
    echo -e "${RED}✗ Not configured${NC}"
    echo "Please configure AWS CLI: aws configure"
    exit 1
fi
AWS_ACCOUNT=$(echo "$AWS_IDENTITY" | grep -o '"Account": "[^"]*' | cut -d'"' -f4)
AWS_USER_ARN=$(echo "$AWS_IDENTITY" | grep -o '"Arn": "[^"]*' | cut -d'"' -f4)
echo -e "${GREEN}✓ Authenticated${NC}"
debug "Account: $AWS_ACCOUNT"
debug "User: $AWS_USER_ARN"
log "AWS Account: $AWS_ACCOUNT"
log "AWS User: $AWS_USER_ARN"

# Get default AWS region
AWS_REGION=$(aws configure get region 2>/dev/null || echo "")
if [ -z "$AWS_REGION" ]; then
    AWS_REGION="eu-central-1"
    echo ""
    echo -e "${YELLOW}No default AWS region configured. Using: $AWS_REGION${NC}"
    read -p "Press Enter to continue or type a different region: " custom_region
    if [ -n "$custom_region" ]; then
        AWS_REGION="$custom_region"
    fi
fi
echo -e "${CYAN}Using AWS Region: $AWS_REGION${NC}"

# ═══════════════════════════════════════════════════
# GENERATE IAM POLICY FOR DEPLOYMENT
# ═══════════════════════════════════════════════════

echo ""
echo -e "${YELLOW}═══════════════════════════════════════════════════${NC}"
echo -e "${YELLOW}  IMPORTANT: IAM Policy Setup Required${NC}"
echo -e "${YELLOW}═══════════════════════════════════════════════════${NC}"
echo ""
echo "This script needs specific IAM permissions to deploy the Lambda function."
echo "For security, we recommend creating a temporary policy restricted to your IP."
echo ""

# Get user's public IP
echo -n "Detecting your public IP address... "
DETECTED_IP=$(curl -s https://api.ipify.org 2>/dev/null || curl -s https://ifconfig.me 2>/dev/null || echo "")

if [ -n "$DETECTED_IP" ]; then
    echo -e "${GREEN}$DETECTED_IP${NC}"
else
    echo -e "${YELLOW}Unable to detect${NC}"
fi

echo ""
echo "IP Restriction Options:"
echo "────────────────────────────────────"
if [ -n "$DETECTED_IP" ]; then
    echo "  [1] Restrict to detected IP: $DETECTED_IP (Recommended)"
else
    echo "  [1] Enter custom IP address"
fi
echo "  [2] No IP restriction (Less secure)"
echo ""
read -p "Select option [1-2]: " ip_option

case $ip_option in
    1)
        if [ -n "$DETECTED_IP" ]; then
            USER_PUBLIC_IP="$DETECTED_IP"
        else
            read -p "Enter IP address: " USER_PUBLIC_IP
            if [ -z "$USER_PUBLIC_IP" ]; then
                echo -e "${RED}No IP provided. Exiting.${NC}"
                exit 1
            fi
        fi
        ;;
    2)
        USER_PUBLIC_IP=""
        ;;
    *)
        echo -e "${RED}Invalid option. Exiting.${NC}"
        exit 1
        ;;
esac

# Generate policy
POLICY_NAME="LOX24-Deployment-Policy-$(date +%s)"
POLICY_DIR="./policies"
mkdir -p "$POLICY_DIR"
POLICY_FILE="$POLICY_DIR/$POLICY_NAME.json"

# Create policy template file
POLICY_TEMPLATE="$POLICY_DIR/temp-policy-template.json"

# Check if external template exists
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
EXTERNAL_TEMPLATE="$SCRIPT_DIR/iam-deployment-policy-template.json"

if [ -f "$EXTERNAL_TEMPLATE" ]; then
    echo "Using policy template: $EXTERNAL_TEMPLATE"
    cp "$EXTERNAL_TEMPLATE" "$POLICY_TEMPLATE"
else
    echo -e "${RED}Error: iam-deployment-policy-template.json not found!${NC}"
    echo "Please ensure the template file exists in the same directory as this script."
    exit 1
fi

if [ -n "$USER_PUBLIC_IP" ]; then
    IP_CONDITION=",
                \"Condition\": {
                    \"IpAddress\": {
                        \"aws:SourceIp\": \"$USER_PUBLIC_IP/32\"
                    }
                }"
    echo ""
    echo -e "${GREEN}✓ Policy will be restricted to IP: $USER_PUBLIC_IP${NC}"
else
    IP_CONDITION=""
    echo ""
    echo -e "${YELLOW}⚠ Policy will NOT be IP-restricted (less secure)${NC}"
fi

# Replace placeholders and create final policy
if [ -n "$IP_CONDITION" ]; then
    # Use awk for multi-line replacement
    awk -v account="$AWS_ACCOUNT" -v ip="$USER_PUBLIC_IP" '
    {
        gsub(/{{AWS_ACCOUNT}}/, account)
        if (/{{IP_CONDITION_COMMA}}/) {
            gsub(/{{IP_CONDITION_COMMA}}/, ",\n                    \"IpAddress\": {\n                        \"aws:SourceIp\": \"" ip "/32\"\n                    }")
        }
        if (/{{IP_CONDITION}}/) {
            gsub(/{{IP_CONDITION}}/, ",\n                \"Condition\": {\n                    \"IpAddress\": {\n                        \"aws:SourceIp\": \"" ip "/32\"\n                    }\n                }")
        }
        print
    }' "$POLICY_TEMPLATE" > "$POLICY_FILE"
else
    sed -e "s|{{AWS_ACCOUNT}}|$AWS_ACCOUNT|g" \
        -e "s|{{IP_CONDITION}}||g" \
        -e "s|{{IP_CONDITION_COMMA}}||g" \
        "$POLICY_TEMPLATE" > "$POLICY_FILE"
fi

rm -f "$POLICY_TEMPLATE"

echo ""
echo -e "${CYAN}Generated IAM Policy: $POLICY_FILE${NC}"
echo ""
echo -e "${YELLOW}ACTION REQUIRED:${NC}"
echo ""
echo "1. Create the policy in AWS IAM Console:"
echo "   - Go to: https://console.aws.amazon.com/iam/home#/policies"
echo "   - Click 'Create policy' → 'JSON' tab"
echo "   - Copy and paste the policy from: $POLICY_FILE"
echo "   - Name it: $POLICY_NAME"
echo ""
echo "2. Attach the policy to your IAM user:"
echo "   - Go to: https://console.aws.amazon.com/iam/home#/users"
echo "   - Select your user: $(echo "$AWS_USER_ARN" | awk -F'/' '{print $NF}')"
echo "   - Click 'Add permissions' → 'Attach policies directly'"
echo "   - Search for: $POLICY_NAME"
echo "   - Attach it"
echo ""
echo "To view the policy content, run:"
echo "  cat $POLICY_FILE"
echo ""

read -p "Press Enter when you've attached the policy to continue... "
echo ""
echo -e "${GREEN}✓ Continuing with deployment...${NC}"
log "User confirmed policy attachment: $POLICY_NAME"

# ═══════════════════════════════════════════════════
# CONFIGURATION
# ═══════════════════════════════════════════════════

step_header "Step 2/8: Configuration"

# LOX24 API Token
while true; do
    read -p "Enter your LOX24 API Token: " -s LOX24_TOKEN
    echo ""

    # Validate token format: digits:32_hex_chars
    if [[ ! "$LOX24_TOKEN" =~ ^[0-9]+:[a-f0-9]{32}$ ]]; then
        echo -e "${RED}✗ Invalid LOX24 API token format${NC}"
        echo "  Expected format: <number>:<32 hex characters>"
        echo "  Example: 12345:a1b2c3d4e5f6789012345678901234ab"
        read -p "Try again? (Y/n): " -n 1 -r
        echo ""
        if [[ $REPLY =~ ^[Nn]$ ]]; then
            exit 1
        fi
    else
        echo -e "${GREEN}✓ Token format valid${NC}"
        log "LOX24 Token validated"
        break
    fi
done

# Sender ID
read -p "Enter LOX24 Sender ID (default: LOX24): " LOX24_SENDER_ID
LOX24_SENDER_ID=${LOX24_SENDER_ID:-test}
echo -e "${GREEN}✓ Sender ID: $LOX24_SENDER_ID${NC}"

# List available KMS keys
echo ""
echo "Fetching available KMS keys..."
if KMS_KEYS=$(aws kms list-keys --region "$AWS_REGION" 2>&1); then
    KEY_IDS=()
    KEY_ARNS=()
    KEY_DESCRIPTIONS=()
    KEY_MANAGERS=()

    echo ""
    echo "Available KMS Keys:"
    echo "─────────────────────────────────────────────────────────"

    counter=1
    while IFS= read -r key_id; do
        # Get key metadata
        key_metadata=$(aws kms describe-key --key-id "$key_id" --region "$AWS_REGION" 2>/dev/null)

        if [ -n "$key_metadata" ]; then
            key_arn=$(echo "$key_metadata" | grep -o '"Arn": "[^"]*' | cut -d'"' -f4)
            key_description=$(echo "$key_metadata" | grep -o '"Description": "[^"]*' | cut -d'"' -f4 | head -1)
            key_manager=$(echo "$key_metadata" | grep -o '"KeyManager": "[^"]*' | cut -d'"' -f4)
            key_state=$(echo "$key_metadata" | grep -o '"KeyState": "[^"]*' | cut -d'"' -f4)

            # Only show enabled keys
            if [ "$key_state" = "Enabled" ]; then
                KEY_IDS+=("$key_id")
                KEY_ARNS+=("$key_arn")
                KEY_MANAGERS+=("$key_manager")

                if [ -z "$key_description" ] || [ "$key_description" = "Default master key that protects my Cognito user pool data" ]; then
                    display_desc="$key_id"
                else
                    display_desc="$key_description"
                fi

                KEY_DESCRIPTIONS+=("$display_desc")

                echo -e "${GREEN}[$counter]${NC} $display_desc"
                echo "    Key ID: $key_id"
                echo "    Manager: $key_manager"
                echo ""

                ((counter++))
            fi
        fi
    done < <(echo "$KMS_KEYS" | grep -o '"KeyId": "[^"]*' | cut -d'"' -f4)

    if [ ${#KEY_IDS[@]} -eq 0 ]; then
        echo -e "${YELLOW}No enabled KMS keys found${NC}"
        read -p "Enter KMS Key ID manually: " KMS_KEY_ID
        read -p "Enter KMS Key ARN manually: " KMS_KEY_ARN
    else
        echo "─────────────────────────────────────────────────────────"
        echo "Enter key number to select, or 'n' to create a new key"
        read -p "Your choice: " key_choice

        if [ "$key_choice" = "n" ] || [ "$key_choice" = "N" ]; then
            echo ""
            echo "Creating new KMS key for Cognito..."

            new_key=$(aws kms create-key \
                --description "LOX24 Cognito SMS Sender encryption key" \
                --region "$AWS_REGION" \
                --output json 2>&1)

            if [ $? -eq 0 ]; then
                KMS_KEY_ID=$(echo "$new_key" | awk -F'"' '/"KeyId":/ {print $4; exit}')
                KMS_KEY_ARN=$(echo "$new_key" | awk -F'"' '/"Arn":/ {print $4; exit}')
                echo -e "${GREEN}✓ New KMS key created${NC}"
                echo "  Key ID: $KMS_KEY_ID"
                echo "  Key ARN: $KMS_KEY_ARN"
            else
                echo -e "${RED}✗ Failed to create KMS key${NC}"
                echo "$new_key"
                exit 1
            fi
        elif [[ "$key_choice" =~ ^[0-9]+$ ]] && [ "$key_choice" -ge 1 ] && [ "$key_choice" -le ${#KEY_IDS[@]} ]; then
            idx=$((key_choice - 1))
            KMS_KEY_ID="${KEY_IDS[$idx]}"
            KMS_KEY_ARN="${KEY_ARNS[$idx]}"
            echo -e "${GREEN}✓ Selected: ${KEY_DESCRIPTIONS[$idx]}${NC}"
        else
            echo -e "${RED}Invalid selection${NC}"
            exit 1
        fi
    fi
else
    echo -e "${YELLOW}Cannot list KMS keys${NC}"
    read -p "Enter KMS Key ID: " KMS_KEY_ID
    read -p "Enter KMS Key ARN: " KMS_KEY_ARN
fi

read -p "Enter Lambda Function Name (default: lox24-cognito-sms-sender): " FUNCTION_NAME
FUNCTION_NAME=${FUNCTION_NAME:-lox24-cognito-sms-sender}

# Get Lambda execution role
ROLE_ARN=""
echo ""
echo "Checking for existing Lambda execution role..."
if IAM_ROLES_OUTPUT=$(aws iam list-roles --query 'Roles[?contains(AssumeRolePolicyDocument.Statement[0].Principal.Service, `lambda.amazonaws.com`)].RoleName' --output text 2>&1); then
    if [ -n "$IAM_ROLES_OUTPUT" ]; then
        counter=1
        ROLE_NAMES=()
        ROLE_ARNS_LIST=()

        echo ""
        echo "Available Lambda Execution Roles:"
        for role_name in $IAM_ROLES_OUTPUT; do
            role_arn=$(aws iam get-role --role-name "$role_name" --query 'Role.Arn' --output text 2>/dev/null)
            if [ -n "$role_arn" ]; then
                ROLE_NAMES+=("$role_name")
                ROLE_ARNS_LIST+=("$role_arn")
                echo "  [$counter] $role_name"
                ((counter++))
            fi
        done

        read -p "Select role [1-${#ROLE_NAMES[@]}] or Enter to create new: " role_choice
        if [[ "$role_choice" =~ ^[0-9]+$ ]] && [ "$role_choice" -ge 1 ] && [ "$role_choice" -le ${#ROLE_NAMES[@]} ]; then
            idx=$((role_choice - 1))
            ROLE_ARN="${ROLE_ARNS_LIST[$idx]}"
            echo -e "${GREEN}✓ Selected: ${ROLE_NAMES[$idx]}${NC}"
        fi
    fi
fi

# Get User Pool
USER_POOL_ID=""
echo ""
echo "Fetching Cognito User Pools..."
if USER_POOLS_OUTPUT=$(aws cognito-idp list-user-pools --max-results 60 --region "$AWS_REGION" --query 'UserPools[*].[Id,Name]' --output text 2>/dev/null); then
    if [ -z "$USER_POOLS_OUTPUT" ]; then
        echo -e "${YELLOW}No User Pools found${NC}"
        read -p "Create new User Pool? (y/N): " -n 1 -r
        echo ""
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            read -p "User Pool name (default: LOX24-SMS-UserPool): " pool_name
            pool_name=${pool_name:-LOX24-SMS-UserPool}

            echo "Creating User Pool..."
            CREATE_POOL_OUTPUT=$(aws cognito-idp create-user-pool \
                --pool-name "$pool_name" \
                --region "$AWS_REGION" \
                --sms-authentication-message "Your verification code is {####}" \
                --policies "PasswordPolicy={MinimumLength=8,RequireUppercase=true,RequireLowercase=true,RequireNumbers=true}" \
                --output json 2>&1)

            if [ $? -eq 0 ]; then
                USER_POOL_ID=$(echo "$CREATE_POOL_OUTPUT" | awk -F'"' '/"Id":/ {print $4; exit}')
                echo -e "${GREEN}✓ User Pool created: $USER_POOL_ID${NC}"
            else
                echo -e "${RED}✗ Failed to create User Pool${NC}"
                echo "$CREATE_POOL_OUTPUT"
            fi
        fi
    else
        POOL_IDS=()
        POOL_NAMES=()
        counter=1

        echo "Available User Pools:"
        while IFS=$'\t' read -r pool_id pool_name; do
            POOL_IDS+=("$pool_id")
            POOL_NAMES+=("$pool_name")
            echo "  [$counter] $pool_name ($pool_id)"
            ((counter++))
        done <<< "$USER_POOLS_OUTPUT"

        read -p "Select pool [1-${#POOL_IDS[@]}] or Enter to skip: " pool_choice
        if [[ "$pool_choice" =~ ^[0-9]+$ ]] && [ "$pool_choice" -ge 1 ] && [ "$pool_choice" -le ${#POOL_IDS[@]} ]; then
            idx=$((pool_choice - 1))
            USER_POOL_ID="${POOL_IDS[$idx]}"
            echo -e "${GREEN}✓ Selected: ${POOL_NAMES[$idx]}${NC}"
        fi
    fi
fi

echo ""
echo -e "${GREEN}Configuration Summary:${NC}"
echo "  Region:         $AWS_REGION"
echo "  Function Name:  $FUNCTION_NAME"
echo "  KMS Key ID:     $KMS_KEY_ID"
echo "  Sender ID:      $LOX24_SENDER_ID"
echo "  User Pool:      ${USER_POOL_ID:-[Not configured]}"
echo ""

# ═══════════════════════════════════════════════════
# INSTALL DEPENDENCIES
# ═══════════════════════════════════════════════════

step_header "Step 3/8: Installing Dependencies"

echo "Running npm install..."
if npm install --production --silent 2>&1 | tee -a "$LOG_FILE"; then
    echo -e "${GREEN}✓ Dependencies installed${NC}"
else
    echo -e "${RED}✗ Failed to install dependencies${NC}"
    exit 1
fi

# ═══════════════════════════════════════════════════
# CREATE DEPLOYMENT PACKAGE
# ═══════════════════════════════════════════════════

step_header "Step 4/8: Creating Deployment Package"

if [ -f "lox24-cognito-sms-lambda.zip" ]; then
    echo "Removing old deployment package..."
    rm lox24-cognito-sms-lambda.zip
fi

# Create a clean build directory
echo "Preparing package directory..."
BUILD_DIR="/tmp/lambda-build-$$"
rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"

# Copy only necessary files
echo "Copying Lambda function files..."

# Check for index file (either .mjs or .js)
HANDLER_FILE=""
if [ -f "index.mjs" ]; then
    HANDLER_FILE="index.mjs"
    HANDLER_NAME="index.handler"
elif [ -f "index.js" ]; then
    HANDLER_FILE="index.js"
    HANDLER_NAME="index.handler"
else
    echo -e "${RED}✗ Error: index.mjs or index.js not found in current directory${NC}"
    echo "Current directory: $(pwd)"
    echo "Files available:"
    ls -la
    exit 1
fi

cp "$HANDLER_FILE" "$BUILD_DIR/"
echo "  ✓ $HANDLER_FILE"

if [ -f "package.json" ]; then
    cp package.json "$BUILD_DIR/"
    echo "  ✓ package.json"
else
    echo -e "${YELLOW}  ⊘ package.json not found (optional)${NC}"
fi

if [ -f "package-lock.json" ]; then
    cp package-lock.json "$BUILD_DIR/"
    echo "  ✓ package-lock.json"
fi

# Copy any other JS/MJS files
OTHER_FILES=$(find . -maxdepth 1 \( -name "*.js" -o -name "*.mjs" \) -not -name "$HANDLER_FILE" 2>/dev/null)
if [ -n "$OTHER_FILES" ]; then
    echo "$OTHER_FILES" | while read -r file; do
        cp "$file" "$BUILD_DIR/"
        echo "  ✓ $(basename $file)"
    done
fi

# Install production dependencies in build directory
if [ -f "$BUILD_DIR/package.json" ]; then
    echo "Installing production dependencies..."
    cd "$BUILD_DIR"
    npm install --production --silent 2>&1 | tee -a "$LOG_FILE"
    NPM_EXIT=$?
    cd - > /dev/null

    if [ $NPM_EXIT -ne 0 ]; then
        echo -e "${RED}✗ npm install failed${NC}"
        rm -rf "$BUILD_DIR"
        exit 1
    fi
else
    echo "No package.json - skipping npm install"
fi

# Create ZIP from build directory
echo "Creating ZIP package..."
cd "$BUILD_DIR"
zip -r "$OLDPWD/lox24-cognito-sms-lambda.zip" . > /dev/null 2>&1
ZIP_EXIT=$?
cd - > /dev/null

# Cleanup build directory
rm -rf "$BUILD_DIR"

if [ $ZIP_EXIT -eq 0 ] && [ -f "lox24-cognito-sms-lambda.zip" ]; then
    ZIP_SIZE=$(du -h lox24-cognito-sms-lambda.zip | cut -f1)
    echo -e "${GREEN}✓ Deployment package created: $ZIP_SIZE${NC}"

    # Check size (Lambda limit is 50MB for direct upload, 250MB uncompressed)
    ZIP_SIZE_BYTES=$(stat -f%z lox24-cognito-sms-lambda.zip 2>/dev/null || stat -c%s lox24-cognito-sms-lambda.zip 2>/dev/null)
    if [ "$ZIP_SIZE_BYTES" -gt 52428800 ]; then
        echo -e "${RED}✗ Package too large: $ZIP_SIZE (limit: 50MB)${NC}"
        echo "Consider removing unnecessary dependencies or use S3 upload"
        exit 1
    fi
else
    echo -e "${RED}✗ Failed to create deployment package${NC}"
    exit 1
fi

# ═══════════════════════════════════════════════════
# DEPLOY LAMBDA FUNCTION
# ═══════════════════════════════════════════════════

step_header "Step 5/8: Deploying Lambda Function"

echo -n "Checking if Lambda function exists... "
if aws lambda get-function --function-name "$FUNCTION_NAME" --region "$AWS_REGION" &> /dev/null; then
    echo -e "${GREEN}✓ Found${NC}"
    FUNCTION_EXISTS=true
else
    echo -e "${YELLOW}⊘ Not found${NC}"
    FUNCTION_EXISTS=false
fi

if [ "$FUNCTION_EXISTS" = true ]; then
    echo "Updating existing Lambda function code..."
    UPDATE_OUTPUT=$(aws lambda update-function-code \
        --function-name "$FUNCTION_NAME" \
        --zip-file fileb://lox24-cognito-sms-lambda.zip \
        --region "$AWS_REGION" 2>&1)
    UPDATE_EXIT=$?

    if [ $UPDATE_EXIT -eq 0 ]; then
        echo -e "${GREEN}✓ Lambda function code updated${NC}"
        log "Lambda function code updated successfully"

        # Wait for code update to complete
        echo "Waiting for code update to complete (10 seconds)..."
        sleep 10

        # Update handler and runtime configuration
        echo "Updating handler and runtime configuration..."
        echo "  Runtime: nodejs22.x"
        echo "  Handler: $HANDLER_NAME"

        CONFIG_UPDATE_OUTPUT=$(aws lambda update-function-configuration \
            --function-name "$FUNCTION_NAME" \
            --runtime nodejs22.x \
            --handler "$HANDLER_NAME" \
            --region "$AWS_REGION" 2>&1)
        CONFIG_UPDATE_EXIT=$?

        if [ $CONFIG_UPDATE_EXIT -eq 0 ]; then
            echo -e "${GREEN}✓ Configuration updated${NC}"
            log "Handler and runtime updated to nodejs22.x and $HANDLER_NAME"
        else
            echo -e "${RED}✗ Configuration update failed${NC}"
            echo "Error: $CONFIG_UPDATE_OUTPUT"

            # Show current configuration
            echo ""
            echo "Checking current function configuration..."
            aws lambda get-function-configuration \
                --function-name "$FUNCTION_NAME" \
                --region "$AWS_REGION" \
                --query '{Runtime:Runtime,Handler:Handler}' \
                --output table

            echo ""
            echo -e "${YELLOW}You may need to update the configuration manually:${NC}"
            echo "aws lambda update-function-configuration \\"
            echo "  --function-name $FUNCTION_NAME \\"
            echo "  --runtime nodejs22.x \\"
            echo "  --handler $HANDLER_NAME \\"
            echo "  --region $AWS_REGION"
        fi
    else
        echo -e "${RED}✗ Failed to update Lambda function${NC}"
        echo -e "${RED}Exit code: $UPDATE_EXIT${NC}"
        echo -e "${RED}Error details:${NC}"
        echo "$UPDATE_OUTPUT"
        log "Failed to update Lambda function - Exit: $UPDATE_EXIT - Output: $UPDATE_OUTPUT"
        exit 1
    fi
else
    if [ -z "$ROLE_ARN" ]; then
        echo "Creating Lambda execution role..."
        ROLE_NAME="LOX24-Cognito-SMS-Lambda-Role"

        TRUST_POLICY='{
          "Version": "2012-10-17",
          "Statement": [
            {
              "Effect": "Allow",
              "Principal": {
                "Service": "lambda.amazonaws.com"
              },
              "Action": "sts:AssumeRole"
            }
          ]
        }'

        CREATE_ROLE_OUTPUT=$(aws iam create-role \
            --role-name "$ROLE_NAME" \
            --assume-role-policy-document "$TRUST_POLICY" \
            --description "Execution role for LOX24 Cognito SMS Sender Lambda" 2>&1)
        CREATE_ROLE_EXIT=$?

        if [ $CREATE_ROLE_EXIT -eq 0 ]; then
            ROLE_ARN=$(echo "$CREATE_ROLE_OUTPUT" | awk -F'"' '/"Arn":/ {print $4; exit}')
            echo -e "  ${GREEN}✓ IAM role created: $ROLE_NAME${NC}"

            echo "  Attaching CloudWatch Logs policy..."
            aws iam attach-role-policy \
                --role-name "$ROLE_NAME" \
                --policy-arn "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole" \
                >/dev/null 2>&1

            echo -e "  ${GREEN}✓ CloudWatch Logs policy attached${NC}"
            echo "  Waiting for role to propagate..."
            sleep 10
        else
            echo -e "  ${RED}✗ Failed to create IAM role${NC}"
            echo "  Error: $CREATE_ROLE_OUTPUT"
            exit 1
        fi
    fi

    echo "Creating new Lambda function..."
    CREATE_OUTPUT=$(aws lambda create-function \
        --function-name "$FUNCTION_NAME" \
        --runtime nodejs22.x \
        --role "$ROLE_ARN" \
        --handler "$HANDLER_NAME" \
        --zip-file fileb://lox24-cognito-sms-lambda.zip \
        --timeout 30 \
        --memory-size 256 \
        --region "$AWS_REGION" 2>&1)
    CREATE_EXIT=$?

    if [ $CREATE_EXIT -eq 0 ]; then
        echo -e "${GREEN}✓ Lambda function created${NC}"
        log "Lambda function created successfully"
    else
        echo -e "${RED}✗ Failed to create Lambda function${NC}"
        echo -e "${RED}Exit code: $CREATE_EXIT${NC}"
        echo -e "${RED}Error details:${NC}"
        echo "$CREATE_OUTPUT"
        log "Failed to create Lambda function - Exit: $CREATE_EXIT - Output: $CREATE_OUTPUT"
        exit 1
    fi
fi

# ═══════════════════════════════════════════════════
# CONFIGURE ENVIRONMENT VARIABLES (FIXED)
# ═══════════════════════════════════════════════════

step_header "Step 6/8: Configuring Environment Variables"

echo "Waiting for Lambda function to be ready..."
sleep 3

echo "Setting environment variables..."

# Create environment variables file
ENV_FILE="/tmp/lox24-lambda-env.json"
cat > "$ENV_FILE" <<EOF
{
  "Variables": {
    "LOX24_AUTH_TOKEN": "$LOX24_TOKEN",
    "LOX24_SENDER_ID": "$LOX24_SENDER_ID",
    "KMS_KEY_ID": "$KMS_KEY_ID",
    "KMS_KEY_ARN": "$KMS_KEY_ARN",
    "LOX24_API_HOST": "api.lox24.eu",
    "LOX24_SERVICE_CODE": "direct",
    "ENABLE_DEBUG_LOGGING": "false"
  }
}
EOF

ENV_UPDATE_OUTPUT=$(aws lambda update-function-configuration \
    --function-name "$FUNCTION_NAME" \
    --environment "file://$ENV_FILE" \
    --region "$AWS_REGION" 2>&1)
ENV_UPDATE_EXIT=$?

# Clean up temp file
rm -f "$ENV_FILE"

if [ $ENV_UPDATE_EXIT -eq 0 ]; then
    echo -e "${GREEN}✓ Environment variables configured${NC}"
elif echo "$ENV_UPDATE_OUTPUT" | grep -q "ResourceConflictException\|pending"; then
    echo "Lambda function is still updating. Waiting 10 seconds..."
    sleep 10

    # Retry - recreate environment file
    cat > "$ENV_FILE" <<EOF
{
  "Variables": {
    "LOX24_AUTH_TOKEN": "$LOX24_TOKEN",
    "LOX24_SENDER_ID": "$LOX24_SENDER_ID",
    "KMS_KEY_ID": "$KMS_KEY_ID",
    "KMS_KEY_ARN": "$KMS_KEY_ARN",
    "LOX24_API_HOST": "api.lox24.eu",
    "LOX24_SERVICE_CODE": "direct",
    "ENABLE_DEBUG_LOGGING": "false"
  }
}
EOF

    ENV_UPDATE_OUTPUT=$(aws lambda update-function-configuration \
        --function-name "$FUNCTION_NAME" \
        --environment "file://$ENV_FILE" \
        --region "$AWS_REGION" 2>&1)

    rm -f "$ENV_FILE"

    if [ $? -eq 0 ]; then
        echo -e "${GREEN}✓ Environment variables configured (retry succeeded)${NC}"
    else
        echo -e "${RED}✗ Failed to configure environment variables${NC}"
        echo "$ENV_UPDATE_OUTPUT"
        exit 1
    fi
else
    echo -e "${RED}✗ Failed to configure environment variables${NC}"
    echo "$ENV_UPDATE_OUTPUT"
    exit 1
fi

# ═══════════════════════════════════════════════════
# CONFIGURE IAM PERMISSIONS (FIXED)
# ═══════════════════════════════════════════════════

step_header "Step 7/8: Configuring IAM Permissions"

# Get Lambda execution role
LAMBDA_ROLE_ARN=$(aws lambda get-function \
    --function-name "$FUNCTION_NAME" \
    --region "$AWS_REGION" \
    --query 'Configuration.Role' \
    --output text 2>/dev/null)

if [ -n "$LAMBDA_ROLE_ARN" ]; then
    LAMBDA_ROLE_NAME=$(echo "$LAMBDA_ROLE_ARN" | awk -F'/' '{print $NF}')
    echo "Lambda role: $LAMBDA_ROLE_NAME"

    # FIX: Better KMS permission checking
    echo -n "Checking KMS decrypt permission... "

    # Check if the policy already exists
    HAS_KMS_DECRYPT=false
    POLICY_CHECK=$(aws iam get-role-policy \
        --role-name "$LAMBDA_ROLE_NAME" \
        --policy-name "LOX24-KMS-Decrypt-Policy" 2>&1)
    POLICY_CHECK_EXIT=$?

    if [ $POLICY_CHECK_EXIT -eq 0 ]; then
        # Policy exists, check if it has KMS decrypt
        if echo "$POLICY_CHECK" | grep -q "kms:Decrypt"; then
            HAS_KMS_DECRYPT=true
        fi
    fi

    # Also check attached policies
    if [ "$HAS_KMS_DECRYPT" = "false" ]; then
        ATTACHED_POLICIES=$(aws iam list-attached-role-policies \
            --role-name "$LAMBDA_ROLE_NAME" \
            --output text 2>/dev/null)

        for policy_arn in $(echo "$ATTACHED_POLICIES" | awk '{print $2}'); do
            if echo "$policy_arn" | grep -qi "kms"; then
                HAS_KMS_DECRYPT=true
                break
            fi
        done
    fi

    if [ "$HAS_KMS_DECRYPT" = "true" ]; then
        echo -e "${GREEN}✓${NC}"
    else
        echo -e "${YELLOW}✗ (missing)${NC}"
        echo "Adding KMS decrypt permission to Lambda role..."

        # Create KMS policy file
        KMS_POLICY_FILE="/tmp/lox24-kms-policy.json"
        cat > "$KMS_POLICY_FILE" <<EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": [
                "kms:Decrypt",
                "kms:DescribeKey",
                "kms:CreateGrant"
            ],
            "Resource": "$KMS_KEY_ARN"
        }
    ]
}
EOF

        PUT_POLICY_OUTPUT=$(aws iam put-role-policy \
            --role-name "$LAMBDA_ROLE_NAME" \
            --policy-name "LOX24-KMS-Decrypt-Policy" \
            --policy-document "file://$KMS_POLICY_FILE" 2>&1)
        PUT_POLICY_EXIT=$?

        rm -f "$KMS_POLICY_FILE"

        if [ $PUT_POLICY_EXIT -eq 0 ]; then
            echo -e "  ${GREEN}✓ KMS decrypt permission added${NC}"

            # Create flag file to warn about IAM propagation delay
            touch /tmp/lox24-kms-just-added

            # Wait for IAM to propagate (important!)
            echo "  Waiting for IAM policy to propagate (15 seconds)..."
            sleep 15

            # Verify the policy was actually added
            echo -n "  Verifying policy... "
            VERIFY_OUTPUT=$(aws iam get-role-policy \
                --role-name "$LAMBDA_ROLE_NAME" \
                --policy-name "LOX24-KMS-Decrypt-Policy" 2>&1)

            if [ $? -eq 0 ] && echo "$VERIFY_OUTPUT" | grep -q "kms:Decrypt"; then
                echo -e "${GREEN}✓${NC}"
            else
                echo -e "${YELLOW}? (verification failed)${NC}"
                echo ""
                echo -e "  ${YELLOW}Policy was added but verification failed.${NC}"
                echo "  If SMS sending fails, wait a few minutes and try again."
            fi
        else
            echo -e "  ${RED}✗ Failed to add KMS permission${NC}"
            echo "  Error: $PUT_POLICY_OUTPUT"
            echo ""
            echo -e "  ${YELLOW}Add this permission manually:${NC}"
            echo "  1. Go to IAM Console → Roles → $LAMBDA_ROLE_NAME"
            echo "  2. Add inline policy: LOX24-KMS-Decrypt-Policy"
            echo "  3. Actions: kms:Decrypt, kms:DescribeKey"
            echo "  4. Resource: $KMS_KEY_ARN"
        fi
    fi
else
    echo -e "${YELLOW}Could not determine Lambda role${NC}"
fi

# ═══════════════════════════════════════════════════
# COGNITO INTEGRATION (FIXED)
# ═══════════════════════════════════════════════════

step_header "Step 8/8: Cognito Integration"

if [ -n "$USER_POOL_ID" ]; then
    echo "Configuring Cognito User Pool: $USER_POOL_ID"

    # Add Lambda permission for Cognito to invoke
    echo -n "Adding Lambda invoke permission... "
    PERM_OUTPUT=$(aws lambda add-permission \
        --function-name "$FUNCTION_NAME" \
        --statement-id CognitoInvokeSMS \
        --action lambda:InvokeFunction \
        --principal cognito-idp.amazonaws.com \
        --source-arn "arn:aws:cognito-idp:$AWS_REGION:$AWS_ACCOUNT:userpool/$USER_POOL_ID" \
        --region "$AWS_REGION" 2>&1)
    PERM_EXIT=$?

    if [ $PERM_EXIT -eq 0 ]; then
        echo -e "${GREEN}✓${NC}"
    elif echo "$PERM_OUTPUT" | grep -q "ResourceConflictException"; then
        echo -e "${GREEN}✓ (already exists)${NC}"
    else
        echo -e "${RED}✗${NC}"
        echo "Error: $PERM_OUTPUT"
    fi

    # Update User Pool to use custom SMS sender
    echo -n "Configuring User Pool custom SMS sender... "

    # Get Lambda ARN
    FUNCTION_ARN=$(aws lambda get-function \
        --function-name "$FUNCTION_NAME" \
        --region "$AWS_REGION" \
        --query 'Configuration.FunctionArn' \
        --output text 2>/dev/null)

    UPDATE_POOL_OUTPUT=$(aws cognito-idp update-user-pool \
        --user-pool-id "$USER_POOL_ID" \
        --region "$AWS_REGION" \
        --lambda-config "CustomSMSSender={LambdaVersion=V1_0,LambdaArn=$FUNCTION_ARN},KMSKeyID=$KMS_KEY_ARN" 2>&1)
    UPDATE_POOL_EXIT=$?

    if [ $UPDATE_POOL_EXIT -eq 0 ]; then
        echo -e "${GREEN}✓${NC}"
        echo -e "${GREEN}✓ Cognito configured successfully${NC}"

        # Check if we just added KMS permissions
        if [ -f /tmp/lox24-kms-just-added ]; then
            echo ""
            echo -e "${YELLOW}⚠ Note: KMS permissions were just added.${NC}"
            echo "  IAM policies can take 15-30 seconds to fully propagate."
            echo "  If the test SMS fails with KMS errors, wait a moment and try again."
            rm -f /tmp/lox24-kms-just-added
        fi

        # Offer to test
        echo ""
        read -p "Would you like to send a test SMS? (y/N): " -n 1 -r
        echo ""

        if [[ $REPLY =~ ^[Yy]$ ]]; then
            echo ""
            read -p "Enter phone number (with country code, e.g., +49123456789): " test_phone

            if [[ "$test_phone" =~ ^\+[0-9]{10,15}$ ]]; then
                echo "Sending test SMS to $test_phone..."

                TEST_USERNAME="test-$(date +%s)"

                # Create test user
                echo -n "Creating test user... "
                CREATE_USER_OUTPUT=$(aws cognito-idp admin-create-user \
                    --user-pool-id "$USER_POOL_ID" \
                    --username "$TEST_USERNAME" \
                    --user-attributes Name=phone_number,Value="$test_phone" \
                    --message-action SUPPRESS \
                    --region "$AWS_REGION" 2>&1)
                CREATE_USER_EXIT=$?

                if [ $CREATE_USER_EXIT -ne 0 ]; then
                    echo -e "${RED}✗${NC}"
                    echo "Error creating user: $CREATE_USER_OUTPUT"
                else
                    echo -e "${GREEN}✓${NC}"

                    # Mark phone as verified
                    echo -n "Verifying phone number... "
                    aws cognito-idp admin-update-user-attributes \
                        --user-pool-id "$USER_POOL_ID" \
                        --username "$TEST_USERNAME" \
                        --user-attributes Name=phone_number_verified,Value=true \
                        --region "$AWS_REGION" >/dev/null 2>&1
                    echo -e "${GREEN}✓${NC}"

                    # Set password
                    echo -n "Setting password... "
                    aws cognito-idp admin-set-user-password \
                        --user-pool-id "$USER_POOL_ID" \
                        --username "$TEST_USERNAME" \
                        --password "TempPass123!" \
                        --permanent \
                        --region "$AWS_REGION" >/dev/null 2>&1
                    echo -e "${GREEN}✓${NC}"

                    # Trigger SMS via password reset
                    echo "Triggering SMS via password reset..."
                    RESET_OUTPUT=$(aws cognito-idp admin-reset-user-password \
                        --user-pool-id "$USER_POOL_ID" \
                        --username "$TEST_USERNAME" \
                        --region "$AWS_REGION" 2>&1)
                    RESET_EXIT=$?

                    if [ $RESET_EXIT -eq 0 ]; then
                        echo -e "${GREEN}✓ Test SMS sent successfully!${NC}"
                        echo "Check your phone for the verification code."
                    else
                        echo -e "${RED}✗ Failed to send test SMS${NC}"
                        echo "Error: $RESET_OUTPUT"
                    fi

                    # Cleanup
                    echo ""
                    read -p "Delete test user? (Y/n): " -n 1 -r
                    echo ""
                    if [[ ! $REPLY =~ ^[Nn]$ ]]; then
                        aws cognito-idp admin-delete-user \
                            --user-pool-id "$USER_POOL_ID" \
                            --username "$TEST_USERNAME" \
                            --region "$AWS_REGION" >/dev/null 2>&1
                        echo "✓ Test user deleted"
                    fi
                fi
            else
                echo -e "${RED}Invalid phone number format${NC}"
            fi
        fi
    else
        echo -e "${RED}✗${NC}"
        echo "Error: $UPDATE_POOL_OUTPUT"
        echo ""
        echo "You may need to configure the User Pool manually."
        echo ""
        echo "Manual configuration command:"
        echo "aws cognito-idp update-user-pool \\"
        echo "  --user-pool-id $USER_POOL_ID \\"
        echo "  --region $AWS_REGION \\"
        echo "  --lambda-config \"CustomSMSSender={LambdaVersion=V1_0,LambdaArn=$FUNCTION_ARN},KMSKeyID=$KMS_KEY_ARN\""
    fi
else
    echo "User Pool ID not provided - skipping Cognito configuration"
    echo ""
    echo "To configure manually, use these commands:"
    echo ""
    echo "# Add Lambda permission:"
    echo "aws lambda add-permission \\"
    echo "  --function-name $FUNCTION_NAME \\"
    echo "  --statement-id CognitoInvokeSMS \\"
    echo "  --action lambda:InvokeFunction \\"
    echo "  --principal cognito-idp.amazonaws.com \\"
    echo "  --source-arn arn:aws:cognito-idp:$AWS_REGION:$AWS_ACCOUNT:userpool/YOUR_USER_POOL_ID \\"
    echo "  --region $AWS_REGION"
    echo ""
    echo "# Update User Pool:"
    echo "aws cognito-idp update-user-pool \\"
    echo "  --user-pool-id YOUR_USER_POOL_ID \\"
    echo "  --lambda-config \"CustomSMSSender={LambdaVersion=V1_0,LambdaArn=YOUR_LAMBDA_ARN},KMSKeyID=$KMS_KEY_ID\" \\"
    echo "  --region $AWS_REGION"
fi

echo ""
echo -e "${GREEN}═══════════════════════════════════════════════════${NC}"
echo -e "${GREEN}  🎉 Deployment Complete!${NC}"
echo -e "${GREEN}═══════════════════════════════════════════════════${NC}"
echo ""
echo -e "${CYAN}Next Steps:${NC}"
echo "  1. Monitor logs: aws logs tail /aws/lambda/$FUNCTION_NAME --follow --region $AWS_REGION"
echo "  2. Check LOX24 dashboard for SMS delivery status"
if [ -n "$USER_POOL_ID" ]; then
    echo "  3. Test with real sign-up or MFA authentication"
else
    echo "  3. Configure Cognito User Pool (see commands above)"
fi
echo ""
echo -e "${CYAN}Log file: $LOG_FILE${NC}"
echo ""

# Cleanup instructions
if [ -n "$POLICY_NAME" ] && [ -n "$POLICY_FILE" ]; then
    echo -e "${YELLOW}═══════════════════════════════════════════════════${NC}"
    echo -e "${YELLOW}  IMPORTANT: Clean Up Temporary IAM Policy${NC}"
    echo -e "${YELLOW}═══════════════════════════════════════════════════${NC}"
    echo ""
    echo "For security, remove the temporary deployment policy:"
    echo ""
    echo "1. Go to IAM Console → Policies:"
    echo "   https://console.aws.amazon.com/iam/home#/policies"
    echo ""
    echo "2. Search for and delete: $POLICY_NAME"
    echo ""
    echo "3. Go to your IAM user and detach the policy:"
    echo "   https://console.aws.amazon.com/iam/home#/users"
    echo ""
    echo "Or use AWS CLI:"
    echo "  # Get the policy ARN"
    echo "  POLICY_ARN=\$(aws iam list-policies --query \"Policies[?PolicyName=='$POLICY_NAME'].Arn\" --output text)"
    echo ""
    echo "  # Detach from your user"
    echo "  aws iam detach-user-policy --user-name \$(aws sts get-caller-identity --query 'Arn' --output text | awk -F'/' '{print \$NF}') --policy-arn \$POLICY_ARN"
    echo ""
    echo "  # Delete the policy"
    echo "  aws iam delete-policy --policy-arn \$POLICY_ARN"
    echo ""
    echo "Policy file saved at: $POLICY_FILE"
    echo ""
fi

log "=== Deployment completed successfully ==="