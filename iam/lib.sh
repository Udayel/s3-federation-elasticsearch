#!/bin/bash
# Shared helpers for the IAM setup scripts. Source this file; don't run it.

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

print_header() {
  echo -e "${GREEN}════════════════════════════════════════════════════════════${NC}"
  echo -e "${GREEN}$1${NC}"
  echo -e "${GREEN}════════════════════════════════════════════════════════════${NC}"
}
print_step()  { echo -e "${YELLOW}✓ $1${NC}"; }
print_error() { echo -e "${RED}✗ $1${NC}" >&2; }

IAM_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# render_template <template-file> VAR=value ...
# Replaces each ${VAR} placeholder in the template and prints the result.
render_template() {
  local out
  out="$(cat "$1")"; shift
  local kv key val
  for kv in "$@"; do
    key="${kv%%=*}"; val="${kv#*=}"
    out="${out//\$\{$key\}/$val}"
  done
  printf '%s\n' "$out"
}

# ensure_policy <policy-name> <policy-document-file> <account-id>
# Creates the managed policy, or, if it already exists, publishes the document
# as the new default version so stale (broader) permissions don't linger.
# Prints the policy ARN.
ensure_policy() {
  local name="$1" doc="$2" account="$3"
  local arn="arn:aws:iam::${account}:policy/${name}"
  if aws iam get-policy --policy-arn "$arn" >/dev/null 2>&1; then
    # IAM keeps at most 5 versions; drop the oldest non-default one if needed.
    local versions
    versions=$(aws iam list-policy-versions --policy-arn "$arn" \
      --query 'Versions[?IsDefaultVersion==`false`].VersionId' --output text)
    if [ "$(echo "$versions" | wc -w)" -ge 4 ]; then
      aws iam delete-policy-version --policy-arn "$arn" \
        --version-id "$(echo "$versions" | tr '\t' '\n' | sort -V | head -1)"
    fi
    aws iam create-policy-version --policy-arn "$arn" \
      --policy-document "file://${doc}" --set-as-default >/dev/null
    print_step "Policy already existed; published current document as default version" >&2
  else
    aws iam create-policy --policy-name "$name" \
      --policy-document "file://${doc}" \
      --description "Read-only S3 access for Elasticsearch ES|QL Data Federation" >/dev/null
    print_step "Policy created: $name" >&2
  fi
  echo "$arn"
}
