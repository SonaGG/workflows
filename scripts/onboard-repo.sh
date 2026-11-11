#!/usr/bin/env bash
set -euo pipefail

REPO="${1:?usage: $0 <owner/repo>}"
CLIENT_ID="${ARTIFACT_SIGNING_CLIENT_ID:?ARTIFACT_SIGNING_CLIENT_ID is not set}"
ENV_NAME=code-signing
TAG_PATTERN='v*'
WORKFLOW_REF='SonaGG/workflows/.github/workflows/sign-windows.yml@refs/heads/main'

echo "==> [$REPO] environment '$ENV_NAME'"
gh api -X PUT "repos/$REPO/environments/$ENV_NAME" --input - <<JSON >/dev/null
{ "deployment_branch_policy": { "protected_branches": false, "custom_branch_policies": true } }
JSON
existing=$(gh api "repos/$REPO/environments/$ENV_NAME/deployment-branch-policies" \
  --jq ".branch_policies[] | select(.type==\"tag\" and .name==\"$TAG_PATTERN\") | .id")
if [ -z "$existing" ]; then
  gh api -X POST "repos/$REPO/environments/$ENV_NAME/deployment-branch-policies" \
    -f name="$TAG_PATTERN" -f type=tag >/dev/null
fi
gh api "repos/$REPO/environments/$ENV_NAME/deployment-branch-policies" \
  --jq '.branch_policies[] | "    allowed: \(.type) \(.name)"'

echo "==> [$REPO] tag ruleset"
if ! gh api "repos/$REPO/rulesets" --jq '.[].name' | grep -qx 'Protect release tags'; then
  gh api -X POST "repos/$REPO/rulesets" --input - <<JSON >/dev/null
{
  "name": "Protect release tags",
  "target": "tag",
  "enforcement": "active",
  "conditions": { "ref_name": { "include": ["refs/tags/$TAG_PATTERN"], "exclude": [] } },
  "rules": [ { "type": "creation" }, { "type": "update" }, { "type": "deletion" } ],
  "bypass_actors": [ { "actor_id": 5, "actor_type": "RepositoryRole", "bypass_mode": "always" } ]
}
JSON
fi

echo "==> [$REPO] OIDC subject template"
gh api -X PUT "repos/$REPO/actions/oidc/customization/sub" --input - <<'JSON' >/dev/null
{ "use_default": false, "include_claim_keys": ["repo", "context", "job_workflow_ref"] }
JSON

PREFIX=$(gh api "repos/$REPO/actions/oidc/customization/sub" --jq ".sub_claim_prefix // \"repo:$REPO\"")
SUBJECT="$PREFIX:environment:$ENV_NAME:job_workflow_ref:$WORKFLOW_REF"
FIC_NAME="gh-$(echo "$REPO" | tr '/A-Z' '-a-z' | tr -cd 'a-z0-9-')-$ENV_NAME"
echo "==> federated credential '$FIC_NAME'"
echo "    subject: $SUBJECT"
if az ad app federated-credential show --id "$CLIENT_ID" --federated-credential-id "$FIC_NAME" >/dev/null 2>&1; then
  az ad app federated-credential update --id "$CLIENT_ID" --federated-credential-id "$FIC_NAME" \
    --parameters "{\"subject\":\"$SUBJECT\"}" >/dev/null
  echo "    (updated)"
else
  tmp=$(mktemp)
  cat >"$tmp" <<JSON
{
  "name": "$FIC_NAME",
  "issuer": "https://token.actions.githubusercontent.com",
  "subject": "$SUBJECT",
  "audiences": ["api://AzureADTokenExchange"]
}
JSON
  az ad app federated-credential create --id "$CLIENT_ID" --parameters "@$tmp" >/dev/null
  rm -f "$tmp"
fi
