#!/bin/bash

###############################################################################
# S3 Bucket Creation Script for S3 Federation
# Creates bucket with proper configuration for Elasticsearch access
###############################################################################

set -e

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

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
  if [ $# -lt 1 ]; then
    print_error "Missing bucket name"
    echo ""
    echo "Usage: bash scripts/create-s3-bucket.sh <BUCKET_NAME> [AWS_REGION]"
    echo ""
    echo "Example:"
    echo "  bash scripts/create-s3-bucket.sh my-s3-federation-bucket us-west-2"
    echo ""
    exit 1
  fi

  BUCKET_NAME=$1
  AWS_REGION=${2:-us-west-2}

  print_header "Creating S3 Bucket for S3 Federation"

  echo ""
  echo "Configuration:"
  echo "  Bucket Name: $BUCKET_NAME"
  echo "  Region: $AWS_REGION"
  echo ""

  # Check if bucket exists
  if aws s3api head-bucket --bucket "$BUCKET_NAME" 2>/dev/null; then
    print_step "Bucket already exists"
  else
    print_step "Creating bucket..."
    if [ "$AWS_REGION" = "us-east-1" ]; then
      aws s3 mb "s3://$BUCKET_NAME"
    else
      aws s3 mb "s3://$BUCKET_NAME" --region "$AWS_REGION"
    fi
    print_step "Bucket created: $BUCKET_NAME"
  fi

  # Enable versioning
  print_step "Enabling versioning..."
  aws s3api put-bucket-versioning \
    --bucket "$BUCKET_NAME" \
    --versioning-configuration Status=Enabled
  print_step "Versioning enabled"

  # Enable encryption
  print_step "Enabling encryption..."
  aws s3api put-bucket-encryption \
    --bucket "$BUCKET_NAME" \
    --server-side-encryption-configuration '{
      "Rules": [
        {
          "ApplyServerSideEncryptionByDefault": {
            "SSEAlgorithm": "AES256"
          }
        }
      ]
    }' 2>/dev/null || print_step "Encryption already configured"
  print_step "Encryption enabled"

  # Block public access
  print_step "Blocking public access..."
  aws s3api put-public-access-block \
    --bucket "$BUCKET_NAME" \
    --public-access-block-configuration \
    "BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true"
  print_step "Public access blocked"

  echo ""
  print_header "Next Steps"
  echo ""
  echo "1. Upload the Parquet sample data:"
  echo "   python3 scripts/upload-parquet.py $BUCKET_NAME --region $AWS_REGION"
  echo ""
  echo "2. Set up IAM (pick one):"
  echo "   bash iam/setup-federated-identity.sh $BUCKET_NAME <JWT_ISSUER_URL> <JWT_SUBJECT>   # Elastic Cloud Hosted"
  echo "   bash iam/setup-static-credentials.sh $BUCKET_NAME business-data                    # self-managed / ECE / ECK"
  echo ""
}

main "$@"
