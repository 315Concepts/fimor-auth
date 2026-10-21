#! /bin/bash

BASE_DIR="$(dirname "$0")/../../../"
cd "${BASE_DIR}"

set -a
[ -f ".env.local" ] && source ".env.local"
source ".env"
set +a

# Allow the user to update post-logout-redirects on existing clients
HYDRA_URL="${SERVICE_DOMAIN}:${PRIVATE_HTTPS_PORT}${HYDRA_ADMIN_PATH}"
HYDRA_CLIENT_ID=${HYDRA_CLIENT_ID:-${CONSENT_CLIENT_ID}} # Set an explicit ID or default to debug

curl -X PATCH "https://${HYDRA_URL}/admin/clients/${HYDRA_CLIENT_ID}" \
     -H "Content-Type: application/json" \
     -d "@ory/hydra/utils/ClientLogoutUriPayload.json"