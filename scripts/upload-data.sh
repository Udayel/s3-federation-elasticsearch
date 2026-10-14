#!/bin/bash

###############################################################################
# Upload Data Files to S3
# Uploads CSV files and converts to Parquet format
###############################################################################

set -e

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

print_step() {
  echo -e "${YELLOW}✓ $1${NC}"
}

main() {
  if [ $# -lt 1 ]; then
    echo "Usage: bash upload-data.sh <S3_BUCKET_NAME> [AWS_REGION]"
    exit 1
  fi

  BUCKET=$1
  REGION=${2:-us-east-1}
  DATA_DIR="./data"

  echo -e "${GREEN}Uploading data files to S3...${NC}"
  echo ""

  # Upload files
  for file in customers.csv sales.csv inventory.csv crm.csv; do
    if [ -f "$DATA_DIR/$file" ]; then
      print_step "Uploading $file..."
      aws s3 cp "$DATA_DIR/$file" "s3://$BUCKET/business-data/$file" --region "$REGION"
    fi
  done

  echo ""
  print_step "Upload complete!"
  echo ""
  echo "Files in S3:"
  aws s3 ls "s3://$BUCKET/business-data/" --region "$REGION"
  echo ""
  echo "Note: To use with Elasticsearch ES|SQL Federation:"
  echo "1. Convert CSV files to Parquet (use AWS Glue or local Python)"
  echo "2. Update S3 paths in Elasticsearch to use .parquet files"
  echo ""
}

main "$@"
