#!/bin/bash
TOKEN=$1
echo "Download cloudflared for Mac..."
curl -L https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-darwin-amd64.tgz -o cf.tgz
tar -xzf cf.tgz
sudo mv cloudflared /usr/local/bin/
sudo cloudflared service install $TOKEN