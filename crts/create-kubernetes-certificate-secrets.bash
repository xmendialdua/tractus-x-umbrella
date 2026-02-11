#!/bin/bash

# Default namespace
NAMESPACE="umbrella"

# Allow user to specify namespace as an argument
if [ "$1" ]; then
    NAMESPACE="$1"
fi

# Base directory containing subfolders with certificates
BASE_DIR=$(dirname "$0")

# Iterate through subfolders in the base directory
echo "Creating Kubernetes secrets for certificates in '$BASE_DIR'..."
for DIR in "$BASE_DIR"/*/; do
    # Get the folder name (used as the secret name)
    SECRET_NAME=$(basename "$DIR")

    # Paths to the certificate and key files
    CERT_FILE="$DIR/fullchain.pem"
    KEY_FILE="$DIR/privkey.pem"

    # Check if both files exist
    if [[ -f "$CERT_FILE" && -f "$KEY_FILE" ]]; then
        echo "Creating secret '$SECRET_NAME' in namespace '$NAMESPACE'..."
        kubectl create secret tls "$SECRET_NAME" \
            --cert="$CERT_FILE" \
            --key="$KEY_FILE" \
            --namespace="$NAMESPACE"
    else
        echo "Skipping '$SECRET_NAME': Missing fullchain.pem or privkey.pem"
    fi
done