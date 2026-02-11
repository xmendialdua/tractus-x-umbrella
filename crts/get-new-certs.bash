#!/bin/bash

# Print a warning about disabling Kubernetes ingress
echo "Warning: Kubernetes ingress must be disabled to avoid conflicts with Certbot's standalone server."

# Disable Kubernetes ingress
echo "Disabling Kubernetes ingress..."
microk8s disable ingress

# Ensure ingress is disabled before proceeding
if [ $? -ne 0 ]; then
    echo "Failed to disable Kubernetes ingress. Exiting."
    exit 1
fi

# Check if a subdomain argument is provided
if [ -z "$1" ]; then
    echo "Usage: $0 <subdomain>"
    exit 1
fi

SUBDOMAIN=$1
DOMAIN="dataspace-ikerlan.es"
FULL_DOMAIN="${SUBDOMAIN}.${DOMAIN}"

# Run certbot to create certificates for the given subdomain
sudo certbot certonly --standalone -d "$FULL_DOMAIN"

# Check if certbot succeeded
if [ $? -eq 0 ]; then
    echo "Certificate successfully created for $FULL_DOMAIN"
else
    echo "Failed to create certificate for $FULL_DOMAIN"
    exit 1
fi

# Define the destination directory
DEST_DIR="./${SUBDOMAIN}"

# Create the destination directory if it doesn't exist
mkdir -p "$DEST_DIR"

# Copy the certificate and key files to the destination directory
sudo cp "/etc/letsencrypt/live/${FULL_DOMAIN}/fullchain.pem" "$DEST_DIR/"
sudo cp "/etc/letsencrypt/live/${FULL_DOMAIN}/privkey.pem" "$DEST_DIR/"

# Set appropriate permissions for the copied files
sudo chmod 777 "$DEST_DIR/fullchain.pem" "$DEST_DIR/privkey.pem"

echo "Certificates copied to $DEST_DIR"

# Disable Kubernetes ingress
echo "Enabling Kubernetes ingress..."
microk8s enable ingress
