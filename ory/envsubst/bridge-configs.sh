#! /bin/bash

set -eu

echo "Starting configuration bridge..."

echo "Working on KRATOS..."
envsubst < /opt/envsubst/kratos/kratos-template.yml > /opt/envsubst/kratos/kratos.yml
envsubst < /opt/envsubst/pg/kratos.sqlt > /opt/envsubst/pg/kratos.sql
echo "Working on HYDRA..."
envsubst < /opt/envsubst/hydra/hydra-template.yml > /opt/envsubst/hydra/hydra.yml
envsubst < /opt/envsubst/pg/hydra.sqlt > /opt/envsubst/pg/hydra.sql

echo "Done."