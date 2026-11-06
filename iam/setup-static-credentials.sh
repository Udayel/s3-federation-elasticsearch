#!/bin/bash
###############################################################################
# Static-credentials setup for ES|QL Data Federation.
#
# Creates an IAM user with a least-privilege read policy on the bucket prefix.
# Use this for self-managed, ECE, or ECK clusters, where federated identity is
# not available. On Elastic Cloud Hosted, prefer setup-federated-identity.sh so
# no long-lived keys are stored in Elastic.
#
# Reference: https://www.elastic.co/docs/reference/query-languages/esql/esql-data-federation-static-credentials
###############################################################################
set -euo pipefail
source "$(dirname "$0")/lib.sh"

if [ $# -lt 1 ]; then
  cat <<EOF
Usage: bash iam/setup-static-credentials.sh <BUCKET> [PREFIX] [USER_NAME]

  BUCKET     S3 bucket holding the data
  PREFIX     Key prefix to grant read access to (default: business-data)
  USER_NAME  IAM user name (default: elasticsearch-s3-federation)

Example:
  bash iam/setup-static-credentials.sh my-s3-federation-bucket business-data
EOF
  exit 1
fi

BUCKET="$1"
PREFIX="${2:-business-data}"
USER_NAME="${3:-elasticsearch-s3-federation}"
POLICY_NAME="elastic-s3-federation-read-${BUCKET}"

print_header "ES|QL Data Federation: static credentials setup"
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)

cat <<EOF

  Account:  $ACCOUNT_ID
  Bucket:   s3://$BUCKET/$PREFIX/
  User:     $USER_NAME
  Policy:   $POLICY_NAME

EOF

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

render_template "$IAM_DIR/s3-federation-policy-template.json" \
  "S3_BUCKET_NAME=$BUCKET" "S3_PREFIX=$PREFIX" > "$WORK/policy.json"
POLICY_ARN=$(ensure_policy "$POLICY_NAME" "$WORK/policy.json" "$ACCOUNT_ID")

if aws iam get-user --user-name "$USER_NAME" >/dev/null 2>&1; then
  print_step "User already exists: $USER_NAME"
else
  aws iam create-user --user-name "$USER_NAME" >/dev/null
  print_step "User created: $USER_NAME"
fi

aws iam attach-user-policy --user-name "$USER_NAME" --policy-arn "$POLICY_ARN"
print_step "Policy attached to user"

echo ""
print_header "Done"
cat <<EOF

Next steps:
  1. Create an access key (the secret is shown only once):
       aws iam create-access-key --user-name $USER_NAME
  2. Register the data source with elastic/01-data-source-static-credentials.console
  3. Register the datasets with elastic/02-datasets.console
EOF
