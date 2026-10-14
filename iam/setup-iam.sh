#!/bin/bash

###############################################################################
# IAM Setup Script for S3 Federation ES|SQL
# Uses parameterized templates - no hardcoded account IDs or bucket names
###############################################################################

set -e

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

# Configuration (change these values)
POLICY_NAME="elastic-s3-federation-policy"
ROLE_NAME="elastic-s3-federation-role"
USER_NAME="elasticsearch-s3-federation"
S3_BUCKET_NAME=""  # Will be set from parameter
S3_PREFIX="business-data"  # Change if needed
AWS_ACCOUNT_ID=""  # Will be auto-detected

# ============================================================================
# FUNCTIONS
# ============================================================================

print_header() {
  echo -e "${GREEN}════════════════════════════════════════════════════════════${NC}"
  echo -e "${GREEN}$1${NC}"
  echo -e "${GREEN}════════════════════════════════════════════════════════════${NC}"
}

print_step() {
  echo -e "${YELLOW}✓ $1${NC}"
}

print_error() {
  echo -e "${RED}✗ $1${NC}"
}

# ============================================================================
# MAIN
# ============================================================================

main() {
  print_header "S3 Federation IAM Setup"

  # Check parameters
  if [ $# -lt 1 ]; then
    print_error "Missing parameters"
    echo ""
    echo "Usage: bash setup-iam.sh <S3_BUCKET_NAME> [S3_PREFIX] [USER_NAME]"
    echo ""
    echo "Example:"
    echo "  bash setup-iam.sh my-data-bucket business-data elasticsearch-user"
    echo ""
    exit 1
  fi

  S3_BUCKET_NAME=$1
  S3_PREFIX=${2:-business-data}
  USER_NAME=${3:-elasticsearch-s3-federation}

  # Get Account ID
  print_step "Getting AWS Account ID..."
  AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
  print_step "Account ID: $AWS_ACCOUNT_ID"

  echo ""
  echo "Configuration:"
  echo "  Account ID: $AWS_ACCOUNT_ID"
  echo "  Bucket: $S3_BUCKET_NAME"
  echo "  Prefix: $S3_PREFIX"
  echo "  User: $USER_NAME"
  echo "  Policy Name: $POLICY_NAME"
  echo "  Role Name: $ROLE_NAME"
  echo ""

  # Create policy from template
  print_step "Creating IAM policy from template..."

  cat > /tmp/policy.json << EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "S3BucketListAccess",
      "Effect": "Allow",
      "Action": [
        "s3:ListBucket",
        "s3:GetBucketLocation",
        "s3:ListBucketVersions"
      ],
      "Resource": "arn:aws:s3:::$S3_BUCKET_NAME"
    },
    {
      "Sid": "S3ObjectReadAccess",
      "Effect": "Allow",
      "Action": [
        "s3:GetObject",
        "s3:GetObjectVersion"
      ],
      "Resource": "arn:aws:s3:::$S3_BUCKET_NAME/$S3_PREFIX/*"
    },
    {
      "Sid": "CloudWatchLogs",
      "Effect": "Allow",
      "Action": [
        "logs:CreateLogGroup",
        "logs:CreateLogStream",
        "logs:PutLogEvents"
      ],
      "Resource": "arn:aws:logs:*:*:*"
    }
  ]
}
EOF

  if aws iam get-policy --policy-arn "arn:aws:iam::$AWS_ACCOUNT_ID:policy/$POLICY_NAME" 2>/dev/null; then
    print_step "Policy already exists"
  else
    aws iam create-policy \
      --policy-name "$POLICY_NAME" \
      --policy-document file:///tmp/policy.json \
      --description "S3 Federation policy for Elasticsearch" > /dev/null
    print_step "Policy created: $POLICY_NAME"
  fi

  # Create role from template
  print_step "Creating IAM role from template..."

  cat > /tmp/trust-policy.json << EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "AWS": "arn:aws:iam::$AWS_ACCOUNT_ID:root"
      },
      "Action": "sts:AssumeRole"
    },
    {
      "Effect": "Allow",
      "Principal": {
        "Service": "ec2.amazonaws.com"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
EOF

  if aws iam get-role --role-name "$ROLE_NAME" 2>/dev/null; then
    print_step "Role already exists"
  else
    aws iam create-role \
      --role-name "$ROLE_NAME" \
      --assume-role-policy-document file:///tmp/trust-policy.json \
      --description "S3 Federation role for Elasticsearch" > /dev/null
    print_step "Role created: $ROLE_NAME"
  fi

  # Attach policy to role
  print_step "Attaching policy to role..."
  aws iam attach-role-policy \
    --role-name "$ROLE_NAME" \
    --policy-arn "arn:aws:iam::$AWS_ACCOUNT_ID:policy/$POLICY_NAME"
  print_step "Policy attached"

  # Create/update user
  print_step "Setting up user: $USER_NAME..."

  if aws iam get-user --user-name "$USER_NAME" 2>/dev/null; then
    print_step "User already exists"
  else
    aws iam create-user --user-name "$USER_NAME" > /dev/null
    print_step "User created"
  fi

  # Attach policy to user
  aws iam attach-user-policy \
    --user-name "$USER_NAME" \
    --policy-arn "arn:aws:iam::$AWS_ACCOUNT_ID:policy/$POLICY_NAME"
  print_step "Policy attached to user"

  echo ""
  print_header "Setup Complete!"
  echo ""
  echo "Next steps:"
  echo "1. Generate access keys for the user:"
  echo "   aws iam create-access-key --user-name $USER_NAME"
  echo ""
  echo "2. Use the credentials in Elasticsearch:"
  echo "   Bucket: $S3_BUCKET_NAME"
  echo "   Prefix: $S3_PREFIX"
  echo "   Region: (your AWS region)"
  echo ""
  echo "3. Test S3 access:"
  echo "   aws s3 ls s3://$S3_BUCKET_NAME/$S3_PREFIX/"
  echo ""
}

main "$@"
