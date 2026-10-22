#!/usr/bin/env bash
# Copy web/ to the production site and point its API calls at the PHP shim.
#   reports/mis/deploy/zoho-koyson/deploy.sh [dest]
# Data comes from koyson-mis-zoho (port 8767). That service checks the Zoho web-tab JWT.
# Restart it after Python changes. Only web files and api.php are copied.
set -euo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
web="$here/../../web"
dest="${1:-/var/www/html/algo_cloud/nellon/zoho-koyson}"

mkdir -p "$dest/assets"
cp "$web"/assets/* "$dest/assets/"
for page in "$web"/*.html; do
  sed 's|<meta name="mis-api-base" content="api/">|<meta name="mis-api-base" content="api.php/">|' \
    "$page" > "$dest/$(basename "$page")"
done
cp "$dest/reports.html" "$dest/index.html"
cp "$here/api.php" "$dest/api.php"
echo "deployed $(git -C "$here" rev-parse --short HEAD 2>/dev/null || echo '?') to $dest"
