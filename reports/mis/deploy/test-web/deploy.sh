#!/usr/bin/env bash
# Copy web/ to the static test site and point its API calls at the PHP shim.
#   reports/mis/deploy/test-web/deploy.sh [dest]   (default /var/www/html/algo_cloud/nellon/test-mis)
# The data comes from the koyson-mis-test service (see koyson-mis-test.service); restart it after
# Python changes. Only web files and api.php are copied: never .env or Python code.
set -euo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
web="$here/../../web"
dest="${1:-/var/www/html/algo_cloud/nellon/test-mis}"

mkdir -p "$dest/assets"
cp "$web"/assets/* "$dest/assets/"
for page in "$web"/*.html; do
  sed 's|<meta name="mis-api-base" content="api/">|<meta name="mis-api-base" content="api.php/">|' \
    "$page" > "$dest/$(basename "$page")"
done
cp "$dest/reports.html" "$dest/index.html"
cp "$here/api.php" "$dest/api.php"
echo "deployed $(git -C "$here" rev-parse --short HEAD 2>/dev/null || echo '?') to $dest"
