#!/bin/sh
# Assemble the deployable folder. dist/ is not tracked - it is just
# dead-aisle.html renamed plus a copy of assets/.
set -e
cd "$(dirname "$0")"
rm -rf dist
mkdir -p dist
cp dead-aisle.html dist/index.html
cp -R assets dist/assets
cp deploy/README.txt dist/README.txt 2>/dev/null || true
echo "dist/ ready ($(du -sh dist | cut -f1))"
