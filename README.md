# LOX24 Cognito SMS Sender Deployment

## Files Overview

### Deployment Scripts
- **deploy-fixed.sh** - Main deployment script (fixed version)
- **generate-policy.sh** - Standalone IAM policy generator

### JSON Templates
All JSON policies are stored in separate files for easy editing and version control:

- **iam-deployment-policy-template.json** - IAM policy template for deployment permissions
- **lambda-env-template.json** - Lambda environment variables template
- **kms-decrypt-policy-template.json** - KMS decrypt policy template

### Documentation
- **QUICKSTART.md** - Quick start guide with troubleshooting

## Why JSON Templates Are Separate

✅ **Easy to edit** - Modify policies without touching bash code
✅ **Version control** - Track policy changes separately
✅ **Reusable** - Use same templates across multiple deployments
✅ **Validation** - Can validate JSON syntax independently
✅ **Security** - Review policies without bash complexity

## Usage

### Basic Deployment
```bash
./deploy-fixed.sh
```

### Generate Policy Only
```bash
./generate-policy.sh
```

### Customize Templates
Edit the JSON templates before running scripts:

1. Edit `iam-deployment-policy-template.json` to adjust deployment permissions
2. Edit `lambda-env-template.json` to see environment variable structure
3. Edit `kms-decrypt-policy-template.json` to modify KMS permissions

The scripts will automatically use the external JSON files if they exist in the same directory, otherwise they fall back to embedded templates.

## Template Placeholders

Templates use placeholders that get replaced during execution:

- `{{AWS_ACCOUNT}}` - Your AWS account ID
- `{{IP_CONDITION}}` - Optional IP restriction clause
- `YOUR_*` - Values you provide during deployment

## Quick Fix for Current KMS Error

Since you already have the deployment running but KMS decrypt is failing:

```bash
# 1. Create the KMS policy from template
cat > kms-policy.json <<EOF
{
    "Version": "2012-10-17",
    "Statement": [{
        "Effect": "Allow",
        "Action": ["kms:Decrypt", "kms:DescribeKey"],
        "Resource": "arn:aws:kms:eu-central-1:230134100954:key/f556911d-43b2-46e1-b2de-ad29d4e8ab07"
    }]
}
EOF

# 2. Apply it
aws iam put-role-policy \
  --role-name LOX24-Cognito-SMS-Lambda-Role \
  --policy-name LOX24-KMS-Decrypt-Policy \
  --policy-document file://kms-policy.json

# 3. Wait for propagation
sleep 30

# 4. Test SMS again
aws cognito-idp admin-reset-user-password \
  --user-pool-id eu-central-1_EZUSKNkVn \
  --username test-1761888351 \
  --region eu-central-1
```

## Security Notes

- IAM deployment policy is IP-restricted by default
- Remove the temporary deployment policy after use
- Lambda role only has access to the specific KMS key
- All policies follow least-privilege principle
