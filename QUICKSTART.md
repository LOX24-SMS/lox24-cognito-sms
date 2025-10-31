# LOX24 Cognito SMS Sender - Quick Start Guide

## Prerequisites
- AWS CLI configured
- Node.js (v18+) and npm installed
- LOX24 API token
- Required files: `deploy-fixed.sh`, `iam-deployment-policy-template.json`

## Deployment Steps

### Step 1: Run Deployment Script

```bash
./deploy-fixed.sh
```

### Step 2: Choose IP Restriction

When prompted, select:
```
IP Restriction Options:
────────────────────────────────────
  [1] Restrict to detected IP: X.X.X.X (Recommended)
  [2] No IP restriction (Less secure)

Select option [1-2]:
```

**Choose Option 1** for security (recommended)

### Step 3: Attach IAM Policy

The script generates a policy file in `./policies/` directory.

**Via AWS Console:**
1. Go to: https://console.aws.amazon.com/iam/home#/policies
2. Click "Create policy" → "JSON" tab
3. Copy contents from the generated policy file
4. Name it: `LOX24-Deployment-Policy-TIMESTAMP`
5. Attach to your IAM user

**Or via AWS CLI:**
```bash
# Set variables from script output
POLICY_FILE="./policies/LOX24-Deployment-Policy-TIMESTAMP.json"
POLICY_NAME="LOX24-Deployment-Policy-TIMESTAMP"

# Create policy
POLICY_ARN=$(aws iam create-policy \
  --policy-name $POLICY_NAME \
  --policy-document file://$POLICY_FILE \
  --query 'Policy.Arn' --output text)

# Attach to your user
aws iam attach-user-policy \
  --user-name YOUR_USERNAME \
  --policy-arn $POLICY_ARN
```

Press Enter in the script to continue after attaching the policy.

### Step 4: Script Completes Automatically

The script will:
1. ✅ Install dependencies
2. ✅ Create deployment package
3. ✅ Deploy Lambda function
4. ✅ Configure environment variables
5. ✅ Add KMS decrypt permissions (waits 15s for propagation)
6. ✅ Configure Cognito User Pool
7. ✅ Offer to send test SMS

### Step 5: Clean Up IAM Policy (Important!)

After successful deployment, remove the temporary policy:

**Via AWS Console:**
1. Go to IAM → Policies
2. Search for: `LOX24-Deployment-Policy-*`
3. Detach it from your user
4. Delete the policy

**Via AWS CLI:**
```bash
# Find policy
POLICY_ARN=$(aws iam list-policies \
  --query "Policies[?contains(PolicyName, 'LOX24-Deployment-Policy')].Arn" \
  --output text)

# Detach
aws iam detach-user-policy \
  --user-name YOUR_USERNAME \
  --policy-arn $POLICY_ARN

# Delete
aws iam delete-policy --policy-arn $POLICY_ARN
```

## Security Features

### IP Restriction (Recommended)
When you choose Option 1, all AWS API calls are restricted to your IP:
```json
{
    "Condition": {
        "IpAddress": {
            "aws:SourceIp": "YOUR_IP/32"
        }
    }
}
```

### Secure iam:PassRole
The policy restricts PassRole to Lambda service only:
```json
{
    "Action": "iam:PassRole",
    "Condition": {
        "StringEquals": {
            "iam:PassedToService": "lambda.amazonaws.com"
        }
    }
}
```

This prevents the AWS warning: "Using iam:PassRole with wildcards"

## Troubleshooting

### KMS Decrypt Errors
```
AccessDeniedException: not authorized to perform: kms:Decrypt
```

**Solution:** IAM policies take 15-30 seconds to propagate. The script waits 15 seconds automatically, but if you still get errors:

```bash
# Wait additional time
sleep 30

# Retry test
aws cognito-idp admin-reset-user-password \
  --user-pool-id YOUR_POOL_ID \
  --username test-user \
  --region YOUR_REGION
```

### Manual KMS Permission Fix
If automatic KMS permission addition failed:

```bash
cat > kms-policy.json <<EOF
{
    "Version": "2012-10-17",
    "Statement": [{
        "Effect": "Allow",
        "Action": ["kms:Decrypt", "kms:DescribeKey"],
        "Resource": "YOUR_KMS_KEY_ARN"
    }]
}
EOF

aws iam put-role-policy \
  --role-name LOX24-Cognito-SMS-Lambda-Role \
  --policy-name LOX24-KMS-Decrypt-Policy \
  --policy-document file://kms-policy.json
```

### Test SMS Not Working

**Check Lambda logs:**
```bash
aws logs tail /aws/lambda/lox24-cognito-sms-sender --follow --region YOUR_REGION
```

**Verify Cognito configuration:**
```bash
aws cognito-idp describe-user-pool \
  --user-pool-id YOUR_POOL_ID \
  --query 'UserPool.LambdaConfig' \
  --region YOUR_REGION
```

**Common issues:**
- KMS permissions not propagated yet → Wait 30s, retry
- Lambda invoke permission missing → Script adds this automatically
- Wrong KMS key ARN in Cognito config → Check and update

### Policy Attachment Errors

**"Policy with name already exists"**
- Use a different policy name or delete the existing one first

**"User not authorized to perform iam:CreatePolicy"**
- You need admin permissions to create IAM policies
- Ask your AWS administrator to create the policy for you

### Deployment Package Too Large

If `npm install` creates a large package:

```bash
# Use production only
npm install --production

# Remove dev dependencies
npm prune --production

# Check size
du -sh node_modules/
```

The limit is 250 MB unzipped.

## Manual Test SMS

If automated test fails, test manually:

```bash
# Create test user
aws cognito-idp admin-create-user \
  --user-pool-id YOUR_POOL_ID \
  --username testuser \
  --user-attributes Name=phone_number,Value=+1234567890 Name=phone_number_verified,Value=true \
  --message-action SUPPRESS \
  --region YOUR_REGION

# Set password
aws cognito-idp admin-set-user-password \
  --user-pool-id YOUR_POOL_ID \
  --username testuser \
  --password TempPass123! \
  --permanent \
  --region YOUR_REGION

# Trigger SMS
aws cognito-idp admin-reset-user-password \
  --user-pool-id YOUR_POOL_ID \
  --username testuser \
  --region YOUR_REGION

# Clean up
aws cognito-idp admin-delete-user \
  --user-pool-id YOUR_POOL_ID \
  --username testuser \
  --region YOUR_REGION
```

## Next Steps

After successful deployment:

1. ✅ Remove temporary IAM policy
2. ✅ Test with real user sign-ups
3. ✅ Monitor Lambda logs
4. ✅ Check LOX24 dashboard for SMS delivery
5. ✅ Set up CloudWatch alarms for failures

## Monitoring

**Lambda logs:**
```bash
aws logs tail /aws/lambda/lox24-cognito-sms-sender --follow
```

**Recent errors:**
```bash
aws logs filter-log-events \
  --log-group-name /aws/lambda/lox24-cognito-sms-sender \
  --filter-pattern "ERROR" \
  --start-time $(date -u -d '1 hour ago' +%s)000
```

**LOX24 API status:**
Check your LOX24 dashboard for delivery status and any API errors.

## Support

- AWS Lambda docs: https://docs.aws.amazon.com/lambda/
- Cognito custom senders: https://docs.aws.amazon.com/cognito/latest/developerguide/user-pool-lambda-custom-sms-sender.html
- LOX24 API: Contact LOX24 support

## What Was Fixed

✅ **Environment variables** - Proper JSON file handling
✅ **KMS permissions** - Accurate detection with 15s wait
✅ **Cognito config** - Actually updates User Pool
✅ **IP restrictions** - Interactive selection with auto-detection
✅ **iam:PassRole** - Secured with `iam:PassedToService` condition
✅ **No temp files** - Clean policy generation in `./policies/`
✅ **Test SMS** - Improved flow with better error handling