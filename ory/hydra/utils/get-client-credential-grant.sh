#! /bin/bash

BASE_DIR="$(dirname "$0")/../../../"
cd "${BASE_DIR}"

set -a
[ -f ".env.local" ] && source ".env.local"
source ".env"
set +a

ORY_DOCKERFILE="docker-compose-ory.yaml"

HYDRA_PUBLIC_ENDPOINT="https://${SERVICE_DOMAIN}${HYDRA_PUBLIC_PATH}/"
echo "Calling endpoint: ${HYDRA_PUBLIC_ENDPOINT}" 

docker compose -f ${ORY_DOCKERFILE} exec ory-hydra \
  hydra perform client-credentials \
  --endpoint "${HYDRA_PUBLIC_ENDPOINT}" \
  --client-id "${CREDENTIAL_CLIENT_ID}" \
  --client-secret "${CREDENTIAL_CLIENT_SECRET}"