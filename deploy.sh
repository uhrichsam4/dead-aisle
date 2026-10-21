#!/bin/sh
# Publish the built game to this repo's gh-pages branch, which GitHub Pages
# serves at https://uhrichsam4.github.io/dead-aisle/
# Each deploy is a plain commit on top of gh-pages (no force-push), so an
# older build can be brought back by reverting there.
set -e
cd "$(dirname "$0")"
sh build.sh
touch dist/.nojekyll   # serve the files as-is, skip GitHub's Jekyll pass
rm -rf /tmp/dead-aisle-pages
# Clone only the branch's file list, not its ~70 MB of files. With no checkout
# the index starts empty, so after `git add -A` it holds exactly dist/ - any
# file dist/ no longer has is deleted by the commit.
git clone -q --depth 1 --filter=blob:none --no-checkout -b gh-pages \
  https://github.com/uhrichsam4/dead-aisle.git /tmp/dead-aisle-pages
cp -R dist/. /tmp/dead-aisle-pages/
cd /tmp/dead-aisle-pages
git add -A
if git diff --cached --quiet --no-renames; then
  echo "gh-pages already has this build - nothing to deploy"
else
  git -c user.email=ajoksmith176@gmail.com -c user.name=sam commit -q -m "Deploy $(date '+%Y-%m-%d %H:%M')"
  git push -q origin gh-pages
  echo "deployed -> https://uhrichsam4.github.io/dead-aisle/"
fi
cd / && rm -rf /tmp/dead-aisle-pages
