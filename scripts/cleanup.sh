#!/bin/bash
###############################################################################
# Remove the AWS resources created by this repo.
#
# Deletes: every object version and delete marker in the bucket (the bucket is
# versioned, so `aws s3 rb` alone fails), the bucket, the read policy, the IAM
# role from setup-federated-identity.sh, and the IAM user and access keys from
# setup-static-credentials.sh. Resources that don't exist are skipped.
#
# The OIDC identity provider is NOT deleted: one provider per issuer is shared
# by every role trusting your Elastic deployment. Delete it yourself with
# `aws iam delete-open-id-connect-provider` if nothing else uses it.
#
# Remove the Elastic side first with elastic/04-cleanup.console.
###############################################################################
set -euo pipefail
source "$(dirname "$0")/../iam/lib.sh"

if [ $# -lt 1 ]; then
  echo "Usage: bash scripts/cleanup.sh <BUCKET> [ROLE_NAME] [USER_NAME]"
  exit 1
fi

BUCKET="$1"
ROLE_NAME="${2:-elastic-esql-federation-role}"
USER_NAME="${3:-elasticsearch-s3-federation}"
POLICY_NAME="elastic-s3-federation-read-${BUCKET}"
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
POLICY_ARN="arn:aws:iam::${ACCOUNT_ID}:policy/${POLICY_NAME}"

print_header "Cleanup"
cat <<EOF

This permanently deletes, in account $ACCOUNT_ID:
  - bucket s3://$BUCKET and ALL object versions in it
  - IAM policy $POLICY_NAME
  - IAM role   $ROLE_NAME (if present)
  - IAM user   $USER_NAME and its access keys (if present)

EOF
read -r -p "Type the bucket name to confirm: " CONFIRM
if [ "$CONFIRM" != "$BUCKET" ]; then
  print_error "Confirmation did not match; nothing deleted."
  exit 1
fi

# --- Bucket: delete all versions and delete markers, then the bucket -------
if aws s3api head-bucket --bucket "$BUCKET" 2>/dev/null; then
  while :; do
    BATCH=$(aws s3api list-object-versions --bucket "$BUCKET" --max-items 1000 \
      --query '{Objects: [Versions, DeleteMarkers][][].{Key: Key, VersionId: VersionId}}' \
      --output json)
    if [ "$(echo "$BATCH" | grep -c '"Key"')" -eq 0 ]; then break; fi
    aws s3api delete-objects --bucket "$BUCKET" --delete "$BATCH" >/dev/null
  done
  aws s3api delete-bucket --bucket "$BUCKET"
  print_step "Bucket deleted: $BUCKET"
else
  print_step "Bucket not found, skipping: $BUCKET"
fi

# --- Role -------------------------------------------------------------------
if aws iam get-role --role-name "$ROLE_NAME" >/dev/null 2>&1; then
  aws iam detach-role-policy --role-name "$ROLE_NAME" --policy-arn "$POLICY_ARN" 2>/dev/null || true
  aws iam delete-role --role-name "$ROLE_NAME"
  print_step "Role deleted: $ROLE_NAME"
fi

# --- User and access keys ---------------------------------------------------
if aws iam get-user --user-name "$USER_NAME" >/dev/null 2>&1; then
  for KEY in $(aws iam list-access-keys --user-name "$USER_NAME" \
                 --query 'AccessKeyMetadata[].AccessKeyId' --output text); do
    aws iam delete-access-key --user-name "$USER_NAME" --access-key-id "$KEY"
  done
  aws iam detach-user-policy --user-name "$USER_NAME" --policy-arn "$POLICY_ARN" 2>/dev/null || true
  aws iam delete-user --user-name "$USER_NAME"
  print_step "User and access keys deleted: $USER_NAME"
fi

# --- Policy (all non-default versions first) --------------------------------
if aws iam get-policy --policy-arn "$POLICY_ARN" >/dev/null 2>&1; then
  for V in $(aws iam list-policy-versions --policy-arn "$POLICY_ARN" \
               --query 'Versions[?IsDefaultVersion==`false`].VersionId' --output text); do
    aws iam delete-policy-version --policy-arn "$POLICY_ARN" --version-id "$V"
  done
  aws iam delete-policy --policy-arn "$POLICY_ARN"
  print_step "Policy deleted: $POLICY_NAME"
fi

print_header "Cleanup complete"
