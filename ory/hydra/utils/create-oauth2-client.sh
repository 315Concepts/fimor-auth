#! /bin/bash

BASE_DIR="$(dirname "$0")/../../../"
cd "${BASE_DIR}"

set -a
[ -f ".env.local" ] && source ".env.local"
source ".env"
set +a

ORY_DOCKERFILE="docker-compose-ory.yaml"

HYDRA_ADMIN_ENDPOINT="https://${SERVICE_DOMAIN}:${PRIVATE_HTTPS_PORT}${HYDRA_ADMIN_PATH}/"
CLIENT_CALLBACK_URI="https://${CONSENT_SUBDOMAIN}.${SERVICE_DOMAIN}/callback"

echo "Calling endpoint: ${HYDRA_ADMIN_ENDPOINT}" 
HYDRA_CLIENT=$(docker compose -f "${ORY_DOCKERFILE}" exec ory-hydra \
    hydra create client \
    --endpoint ${HYDRA_ADMIN_ENDPOINT} \
    --grant-type authorization_code,refresh_token \
    --response-type code,id_token \
    --format json \
    --scope openid --scope offline --scope email --scope profile \
    --redirect-uri ${CLIENT_CALLBACK_URI})

HYDRA_CLIENT_ID=$(echo $HYDRA_CLIENT | jq -r '.client_id')
HYDRA_CLIENT_SECRET=$(echo $HYDRA_CLIENT | jq -r '.client_secret')

echo
echo "METHOD: OAUTH2"
echo "CLIENT: $HYDRA_CLIENT"
echo "CLIENT ID: $HYDRA_CLIENT_ID"
echo "CLIENT SECRET: $HYDRA_CLIENT_SECRET"
echo