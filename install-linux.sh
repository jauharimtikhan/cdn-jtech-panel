#!/bin/bash
TOKEN=$1
if [ -z "$TOKEN" ]; then echo "Token mana Bre?"; exit 1; fi

ARCH=$(uname -m)
URL="https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64"
[[ "$ARCH" == "aarch64" ]] && URL="https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-arm64"

echo "Download cloudflared linux..."
curl -L $URL -o /usr/local/bin/cloudflared
chmod +x /usr/local/bin/cloudflared

echo "Install service..."
cloudflared service install $TOKEN