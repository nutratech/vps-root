#!/usr/bin/env bash

# This script is invoked by Certbot upon successful certificate renewal.
# It computes the DANE/TLSA "3 1 1" record from the new certificate
# and updates the specific DNS record in Cloudflare via the API.

# Load credentials
ENV_FILE="/etc/letsencrypt/cloudflare_tlsa.env"
if [ ! -f "$ENV_FILE" ]; then
    echo "TLSA script: missing credentials file at $ENV_FILE"
    exit 0
fi
source "$ENV_FILE"

# Make sure we have our variables
if [ -z "$CF_API_TOKEN" ] || [ -z "$CF_ZONE_ID" ] || [ -z "$CF_RECORD_ID" ]; then
    echo "TLSA script: missing required variables in $ENV_FILE"
    exit 1
fi

# Certbot passes the renewed domains in the RENEWED_DOMAINS env var.
# E.g. RENEWED_DOMAINS="nutra.tk mail.nutra.tk"
# Check if the domain we care about was renewed.
if [[ ! "$RENEWED_DOMAINS" =~ "nutra.tk" ]]; then
    # Not our domain, skip
    exit 0
fi

# The full path to the lineage is passed in RENEWED_LINEAGE
# E.g. RENEWED_LINEAGE="/etc/letsencrypt/live/nutra.tk"
CERT_FILE="${RENEWED_LINEAGE}/cert.pem"

if [ ! -f "$CERT_FILE" ]; then
    echo "TLSA script: missing cert file $CERT_FILE"
    exit 1
fi

# Calculate the SPKI SHA-256 hash (3 1 1 configuration)
# 1. Extract the public key (SPKI) from the certificate
# 2. Convert from PEM to DER format
# 3. Calculate SHA-256 hash
TLSA_HASH=$(openssl x509 -in "$CERT_FILE" -noout -pubkey |
    openssl pkey -pubin -outform DER |
    openssl dgst -sha256 -binary |
    hexdump -v -e '/1 "%02x"')

if [ -z "$TLSA_HASH" ]; then
    echo "TLSA script: failed to compute TLSA hash"
    exit 1
fi

echo "Computed new TLSA Hash: $TLSA_HASH"

# Cloudflare API payload for TLSA record
PAYLOAD=$(
    cat <<EOF
{
  "data": {
    "usage": 3,
    "selector": 1,
    "matching_type": 1,
    "certificate": "${TLSA_HASH}"
  }
}
EOF
)

# Update the record in Cloudflare
RESPONSE=$(curl -s -X PATCH "https://api.cloudflare.com/client/v4/zones/$CF_ZONE_ID/dns_records/$CF_RECORD_ID" \
    -H "Authorization: Bearer $CF_API_TOKEN" \
    -H "Content-Type: application/json" \
    -d "$PAYLOAD")

# Check if successful
if echo "$RESPONSE" | grep -q '"success":true'; then
    echo "TLSA script: successfully updated Cloudflare TLSA record for _25._tcp.mail.nutra.tk"
    exit 0
else
    echo "TLSA script: failed to update Cloudflare DNS record"
    echo "$RESPONSE"
    exit 1
fi
