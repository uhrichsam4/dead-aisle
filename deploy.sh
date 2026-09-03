#!/bin/sh
# Publish the built game. The source repo (uhrichsam4/dead-aisle) is PRIVATE,
# and GitHub Pages does not serve private repos on the free plan, so the
# playable build lives in its own public repo: uhrichsam4/dead-aisle-play,
# served at https://uhrichsam4.github.io/dead-aisle-play/
set -e
cd "$(dirname "$0")"
sh build.sh
rm -rf /tmp/play && mkdir -p /tmp/play && cp -R dist/. /tmp/play/
cd /tmp/play
git init -q -b main
git add -A
git -c user.email=ajoksmith176@gmail.com -c user.name=sam commit -q -m "Deploy $(date '+%Y-%m-%d %H:%M')"
git push -q --force https://github.com/uhrichsam4/dead-aisle-play.git main
cd / && rm -rf /tmp/play
echo "deployed -> https://uhrichsam4.github.io/dead-aisle-play/"
