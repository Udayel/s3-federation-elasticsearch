#!/bin/bash
###############################################################################
# Federated identity setup for ES|QL Data Federation (Elastic Cloud Hosted).
#
# Creates (or reuses) the IAM OIDC identity provider for your Elastic issuer,
# an IAM role that only your deployment can assume via
# sts:AssumeRoleWithWebIdentity, and a least-privilege read policy on the
# bucket prefix. No static AWS credentials are created.
#
# Get <JWT_ISSUER_URL> and <JWT_SUBJECT> from Kibana:
#   Data management > ES|QL Data Federation > Connect data source > Amazon S3
#   > Authentication: Federated Identity > Setup method: Manual
# The subject looks like  deployment:<deployment-id>
#
# Alternative: choose "CloudFormation" in the same flyout to have Elastic's
# template create the provider and role, then attach the policy from
# iam/s3-federation-policy-template.json to that role.
#
# Reference: https://www.elastic.co/docs/reference/query-languages/esql/esql-data-federation-federated-identity
###############################################################################
set -euo pipefail
source "$(dirname "$0")/lib.sh"

usage() {
  cat <<EOF
Usage: bash iam/setup-federated-identity.sh <BUCKET> <JWT_ISSUER_URL> <JWT_SUBJECT> [PREFIX] [ROLE_NAME] [JWT_AUDIENCE]

  BUCKET          S3 bucket holding the data
  JWT_ISSUER_URL  Issuer URL shown in Kibana (https://...)
  JWT_SUBJECT     Subject shown in Kibana, e.g. deployment:abc123
  PREFIX          Key prefix to grant read access to (default: business-data)
  ROLE_NAME       IAM role name (default: elastic-esql-federation-role)
  JWT_AUDIENCE    Token audience (default: sts.amazonaws.com; must match the
                  data source's jwt_audience)

Example:
  bash iam/setup-federated-identity.sh my-s3-federation-bucket \\
    https://<issuer-host>/<path> deployment:abc123
EOF
}

if [ $# -lt 3 ]; then usage; exit 1; fi

BUCKET="$1"
ISSUER_URL="${2%/}"
SUBJECT="$3"
PREFIX="${4:-business-data}"
ROLE_NAME="${5:-elastic-esql-federation-role}"
AUDIENCE="${6:-sts.amazonaws.com}"
POLICY_NAME="elastic-s3-federation-read-${BUCKET}"

case "$ISSUER_URL" in
  https://*) ;;
  *) print_error "JWT_ISSUER_URL must start with https://"; exit 1 ;;
esac
ISSUER_HOST_PATH="${ISSUER_URL#https://}"

print_header "ES|QL Data Federation: federated identity setup"
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
PROVIDER_ARN="arn:aws:iam::${ACCOUNT_ID}:oidc-provider/${ISSUER_HOST_PATH}"

cat <<EOF

  Account:   $ACCOUNT_ID
  Bucket:    s3://$BUCKET/$PREFIX/
  Issuer:    $ISSUER_URL
  Subject:   $SUBJECT
  Audience:  $AUDIENCE
  Role:      $ROLE_NAME
  Policy:    $POLICY_NAME

EOF

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

# 1. OIDC identity provider (one per issuer per account; reuse if present)
if aws iam get-open-id-connect-provider --open-id-connect-provider-arn "$PROVIDER_ARN" >/dev/null 2>&1; then
  print_step "Reusing existing OIDC provider: $PROVIDER_ARN"
  if ! aws iam get-open-id-connect-provider --open-id-connect-provider-arn "$PROVIDER_ARN" \
       --query 'ClientIDList' --output text | tr '\t' '\n' | grep -qx "$AUDIENCE"; then
    aws iam add-client-id-to-open-id-connect-provider \
      --open-id-connect-provider-arn "$PROVIDER_ARN" --client-id "$AUDIENCE"
    print_step "Added audience $AUDIENCE to provider"
  fi
else
  aws iam create-open-id-connect-provider --url "$ISSUER_URL" --client-id-list "$AUDIENCE" >/dev/null
  print_step "Created OIDC provider: $PROVIDER_ARN"
fi

# 2. Role trusted only by your deployment's tokens
render_template "$IAM_DIR/trust-policy-template.json" \
  "OIDC_PROVIDER_ARN=$PROVIDER_ARN" "ISSUER_HOST_PATH=$ISSUER_HOST_PATH" \
  "JWT_AUDIENCE=$AUDIENCE" "JWT_SUBJECT=$SUBJECT" > "$WORK/trust-policy.json"

if aws iam get-role --role-name "$ROLE_NAME" >/dev/null 2>&1; then
  aws iam update-assume-role-policy --role-name "$ROLE_NAME" \
    --policy-document "file://$WORK/trust-policy.json"
  print_step "Role existed; trust policy updated: $ROLE_NAME"
else
  aws iam create-role --role-name "$ROLE_NAME" \
    --assume-role-policy-document "file://$WORK/trust-policy.json" \
    --description "Assumed by Elastic Cloud for ES|QL Data Federation" >/dev/null
  print_step "Role created: $ROLE_NAME"
fi

# 3. Least-privilege read policy on the bucket prefix
render_template "$IAM_DIR/s3-federation-policy-template.json" \
  "S3_BUCKET_NAME=$BUCKET" "S3_PREFIX=$PREFIX" > "$WORK/policy.json"
POLICY_ARN=$(ensure_policy "$POLICY_NAME" "$WORK/policy.json" "$ACCOUNT_ID")
aws iam attach-role-policy --role-name "$ROLE_NAME" --policy-arn "$POLICY_ARN"
print_step "Policy attached to role"

ROLE_ARN=$(aws iam get-role --role-name "$ROLE_NAME" --query 'Role.Arn' --output text)

echo ""
print_header "Done"
cat <<EOF

Role ARN (paste into Kibana's "Role ARN" field, or use in the request below):
  $ROLE_ARN

Kibana Dev Tools:
  PUT /_query/data_source/s3_federation
  {
    "type": "s3",
    "settings": {
      "auth": "federated_identity",
      "role_arn": "$ROLE_ARN",
      "jwt_audience": "$AUDIENCE"
    }
  }

Next: register the datasets with elastic/02-datasets.console
EOF
