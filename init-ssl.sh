#!/bin/bash
# =============================================================================
# Helper script to initialize SSL certificates for Nginx
# =============================================================================

set -e

SSL_DIR="./ssl"
mkdir -p "$SSL_DIR"
mkdir -p "./certbot/www"

if [ "$1" = "letsencrypt" ]; then
    DOMAIN=$2
    EMAIL=$3

    if [ -z "$DOMAIN" ] || [ -z "$EMAIL" ]; then
        echo "Usage: ./init-ssl.sh letsencrypt <your-domain.com> <your-email@example.com>"
        exit 1
    fi

    echo "🔐 Obtaining Let's Encrypt SSL certificate for $DOMAIN..."
    sudo certbot certonly --webroot -w ./certbot/www -d "$DOMAIN" --email "$EMAIL" --agree-tos --non-interactive

    echo "📋 Copying certificates to $SSL_DIR..."
    sudo cp "/etc/letsencrypt/live/$DOMAIN/fullchain.pem" "$SSL_DIR/fullchain.pem"
    sudo cp "/etc/letsencrypt/live/$DOMAIN/privkey.pem" "$SSL_DIR/privkey.pem"
    sudo chmod 644 "$SSL_DIR"/*.pem
    echo "✅ Let's Encrypt SSL successfully configured!"
else
    echo "🔑 Generating self-signed SSL certificate for development/testing..."
    openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
        -keyout "$SSL_DIR/privkey.pem" \
        -out "$SSL_DIR/fullchain.pem" \
        -subj "/C=US/ST=State/L=City/O=Organization/CN=localhost"
    echo "✅ Self-signed SSL certificate created in $SSL_DIR"
fi
