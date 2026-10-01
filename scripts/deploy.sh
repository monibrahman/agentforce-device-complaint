#!/usr/bin/env bash
# Deploys the backend, creates the agent user, and publishes the agent.
# Usage: ./scripts/deploy.sh [org-alias]    (default alias: complaints)
set -euo pipefail

ORG="${1:-complaints}"
BUNDLE="MedTech_Complaint_Agent"
AGENT_FILE="force-app/main/default/aiAuthoringBundles/$BUNDLE/$BUNDLE.agent"
PLACEHOLDER="__AGENT_USER_PLACEHOLDER__"

cd "$(dirname "$0")/.."

echo "==> 1/6 Deploying backend: Case fields, queue, remote site, Apex, permission set"
sf project deploy start --target-org "$ORG" \
  --source-dir force-app/main/default/objects \
  --source-dir force-app/main/default/queues \
  --source-dir force-app/main/default/remoteSiteSettings \
  --source-dir force-app/main/default/classes \
  --source-dir force-app/main/default/permissionsets

echo "==> 2/6 Running Apex tests"
sf apex run test --target-org "$ORG" --test-level RunLocalTests --code-coverage --result-format human --wait 10

echo "==> 3/6 Giving you (the admin) access to the complaint fields"
sf org assign permset --target-org "$ORG" --name Complaint_Agent_Access || echo "   (already assigned)"

echo "==> 4/6 Creating the agent user the service agent runs as"
AGENT_USER="${AGENT_USER:-}"
if [[ -z "$AGENT_USER" ]]; then
  AGENT_USER=$(sf org create agent-user --target-org "$ORG" --json | python3 -c 'import sys,json; print(json.load(sys.stdin)["result"]["username"])')
fi
# Guard: a service agent must never run as a human admin. Confirm the user has the Einstein Agent User profile.
PROFILE=$(sf data query --target-org "$ORG" --json --query "SELECT Profile.Name FROM User WHERE Username = '$AGENT_USER'" \
  | python3 -c 'import sys,json; r=json.load(sys.stdin)["result"]["records"]; print(r[0]["Profile"]["Name"] if r else "")')
if [[ "$PROFILE" != "Einstein Agent User" ]]; then
  echo "ERROR: '$AGENT_USER' has profile '$PROFILE', not 'Einstein Agent User'." >&2
  echo "A service agent must run as a dedicated agent user, never as an admin." >&2
  exit 1
fi
echo "   Agent user: $AGENT_USER   (re-run with AGENT_USER=$AGENT_USER to reuse it)"
sf org assign permset --target-org "$ORG" --name Complaint_Agent_Access --on-behalf-of "$AGENT_USER" || echo "   (already assigned)"

echo "==> 5/6 Validating and publishing the agent"
# The agent user is org-specific, so it never gets committed. Swap it in, then restore.
cp "$AGENT_FILE" "$AGENT_FILE.bak"
trap 'mv "$AGENT_FILE.bak" "$AGENT_FILE"' EXIT
sed -i.tmp "s/$PLACEHOLDER/$AGENT_USER/" "$AGENT_FILE" && rm -f "$AGENT_FILE.tmp"
sf agent validate authoring-bundle --target-org "$ORG" --api-name "$BUNDLE"
sf agent publish authoring-bundle --target-org "$ORG" --api-name "$BUNDLE" --skip-retrieve

echo "==> 6/6 Activating the agent"
# --json makes activate pick the latest version instead of prompting (the prompt hangs a script).
sf agent activate --target-org "$ORG" --api-name "$BUNDLE" --json

echo
echo "Done. Try it:"
echo "  sf agent preview --target-org $ORG --api-name $BUNDLE"
