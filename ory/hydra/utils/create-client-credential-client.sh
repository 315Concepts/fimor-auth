#! /bin/bash

BASE_DIR="$(dirname "$0")/../../../"
cd "${BASE_DIR}"

set -a
[ -f ".env.local" ] && source ".env.local"
source ".env"
set +a

ORY_DOCKERFILE="docker-compose-ory.yaml"

HYDRA_ADMIN_ENDPOINT="https://${SERVICE_DOMAIN}:${PRIVATE_HTTPS_PORT}${HYDRA_ADMIN_PATH}/"
echo "Calling endpoint: ${HYDRA_ADMIN_ENDPOINT}" 

HYDRA_CLIENT=$(docker compose -f "${ORY_DOCKERFILE}" exec ory-hydra \
    hydra create client \
    --endpoint "${HYDRA_ADMIN_ENDPOINT}" \
    --format json \
    --grant-type client_credentials)
HYDRA_CLIENT_ID=$(echo $HYDRA_CLIENT | jq -r '.client_id')
HYDRA_CLIENT_SECRET=$(echo $HYDRA_CLIENT | jq -r '.client_secret')

echo
echo "METHOD: CLIENT CREDENTIAL"
echo "CLIENT: $HYDRA_CLIENT"
echo "CLIENT ID: $HYDRA_CLIENT_ID"
echo "CLIENT SECRET: $HYDRA_CLIENT_SECRET"
echo