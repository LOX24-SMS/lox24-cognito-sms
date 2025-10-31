#!/bin/bash

# LOX24 IAM Policy Generator
# Generates a secure IAM policy for deployment, optionally restricted to your IP

set -e

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

echo -e "${GREEN}╔════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║  LOX24 Deployment IAM Policy Generator            ║${NC}"
echo -e "${GREEN}╚════════════════════════════════════════════════════╝${NC}"
echo ""

# Get AWS Account ID
echo -n "Getting AWS Account ID... "
if ! AWS_IDENTITY=$(aws sts get-caller-identity 2>&1); then
    echo -e "${RED}✗ AWS credentials not configured${NC}"
    exit 1
fi
AWS_ACCOUNT=$(echo "$AWS_IDENTITY" | grep -o '"Account": "[^"]*' | cut -d'"' -f4)
AWS_USER=$(echo "$AWS_IDENTITY" | grep -o '"Arn": "[^"]*' | cut -d'"' -f4 | awk -F'/' '{print $NF}')
echo -e "${GREEN}$AWS_ACCOUNT${NC}"
echo "Current user: ${CYAN}$AWS_USER${NC}"
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

# Policy name
POLICY_NAME="LOX24-Deployment-Policy-$(date +%s)"
POLICY_FILE="$POLICY_NAME.json"

# Check if external template exists
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
EXTERNAL_TEMPLATE="$SCRIPT_DIR/iam-deployment-policy-template.json"

if [ ! -f "$EXTERNAL_TEMPLATE" ]; then
    echo -e "${RED}Error: iam-deployment-policy-template.json not found!${NC}"
    echo "Please ensure the template file exists in the same directory as this script."
    exit 1
fi

POLICY_TEMPLATE="temp-policy-template.json"
echo "Using policy template: $EXTERNAL_TEMPLATE"
cp "$EXTERNAL_TEMPLATE" "$POLICY_TEMPLATE"

echo ""
if [ -n "$USER_PUBLIC_IP" ]; then
    IP_CONDITION=",
                \"Condition\": {
                    \"IpAddress\": {
                        \"aws:SourceIp\": \"$USER_PUBLIC_IP/32\"
                    }
                }"
    echo -e "${GREEN}✓ Policy will be restricted to IP: $USER_PUBLIC_IP${NC}"
else
    IP_CONDITION=""
    echo -e "${YELLOW}⚠ Policy will NOT be IP-restricted${NC}"
fi

echo ""
echo "Generating policy: $POLICY_FILE"

# Replace placeholders and create final policy
if [ -n "$USER_PUBLIC_IP" ]; then
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

echo -e "${GREEN}✓ Policy generated: $POLICY_FILE${NC}"
echo ""
echo -e "${CYAN}═══════════════════════════════════════════════════${NC}"
echo -e "${CYAN}  How to Use This Policy${NC}"
echo -e "${CYAN}═══════════════════════════════════════════════════${NC}"
echo ""
echo "Option 1: AWS Console (Recommended)"
echo "────────────────────────────────────"
echo "1. Open IAM Policies: https://console.aws.amazon.com/iam/home#/policies"
echo "2. Click 'Create policy' → 'JSON' tab"
echo "3. Copy contents from: $POLICY_FILE"
echo "4. Name it: $POLICY_NAME"
echo "5. Attach to user: $AWS_USER"
echo ""
echo "Option 2: AWS CLI"
echo "────────────────────────────────────"
echo "  # Create the policy"
echo "  POLICY_ARN=\$(aws iam create-policy \\"
echo "    --policy-name $POLICY_NAME \\"
echo "    --policy-document file://$POLICY_FILE \\"
echo "    --query 'Policy.Arn' --output text)"
echo ""
echo "  # Attach to your user"
echo "  aws iam attach-user-policy \\"
echo "    --user-name $AWS_USER \\"
echo "    --policy-arn \$POLICY_ARN"
echo ""
echo -e "${YELLOW}After deployment, remember to detach and delete this policy!${NC}"
echo ""