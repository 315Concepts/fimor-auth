#! /bin/bash

#####
# We do this to load Docker Compose environment variables into a static config system
#####

# Copy the template over
cp /app/config-template.json /config.json

# Inject mail ui url
export WWW_PUBLIC_URL="${MAIL_SUBDOMAIN}.${SERVICE_DOMAIN}"
sed -i "s/{WWW_PUBLIC_URL}/${WWW_PUBLIC_URL}/g" /config.json
# Inject mail service url
export SERVICE_PUBLIC_URL="${SLURP_SUBDOMAIN}.${SERVICE_DOMAIN}"
sed -i "s/{SERVICE_PUBLIC_URL}/${SERVICE_PUBLIC_URL}/g" /config.json
# Inject admin port
sed -i "s/{PRIVATE_HTTPS_PORT}/${PRIVATE_HTTPS_PORT}/g" /config.json

# Run mailslurper as usual
/mailslurper