#!/bin/bash

# Create temp file with metadata
cat > metadata.txt << 'METADATA'

Metadata:
  AWS::ServerlessRepo::Application:
    Name: lox24-cognito-sms
    Description: 5-minute AWS Cognito SMS integration with LOX24 SMS Gateway
    Author: LOX24 SMS
    SpdxLicenseId: MIT
    LicenseUrl: https://raw.githubusercontent.com/LOX24-SMS/lox24-cognito-sms/main/LICENSE
    ReadmeUrl: https://raw.githubusercontent.com/LOX24-SMS/lox24-cognito-sms/main/README.md
    Labels: ['cognito', 'sms', 'authentication', 'mfa']
    HomePageUrl: https://github.com/LOX24-SMS/lox24-cognito-sms
    SemanticVersion: 1.0.0
    SourceCodeUrl: https://github.com/LOX24-SMS/lox24-cognito-sms
METADATA

# Insert metadata after Transform line - use packaged.yaml as input
awk '/^Transform:/ {print; system("cat metadata.txt"); next} 1' packaged.yaml > packaged-final.yaml
rm metadata.txt

echo "✅ Metadata added to packaged-final.yaml"
echo "📦 Using S3 URI from latest package:"
grep "CodeUri:" packaged-final.yaml
