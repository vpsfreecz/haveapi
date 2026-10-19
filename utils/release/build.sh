#!/usr/bin/env bash
set -euo pipefail

if [[ ${HAVEAPI_DEV_SHELL:-} != haveapi ]]; then
  echo 'Run make release in the top-level nix develop shell.' >&2
  exit 1
fi

ruby utils/release/cli.rb check-clean
make doc
mkdir -p dist
if [[ -n $(find dist -mindepth 1 -maxdepth 1 -print -quit) ]]; then
  echo 'dist must be empty; move the previous release artifacts aside first.' >&2
  exit 1
fi

version=$(cat VERSION)
for component in clients/ruby servers/ruby clients/go; do
  (cd "$component" && bundle exec rake build)
done
cp "clients/ruby/pkg/haveapi-client-$version.gem" dist/
cp "servers/ruby/pkg/haveapi-$version.gem" dist/
cp "clients/go/pkg/haveapi-go-client-$version.gem" dist/

(cd clients/js && ./node_modules/.bin/gulp)
(cd clients/js && npm pack --ignore-scripts --pack-destination ../../dist)
cp clients/js/dist/haveapi-client.js dist/
git archive --format=tar --output="dist/haveapi-client-php-$version.tar" HEAD:clients/php
(cd clients/python && uv build --out-dir ../../dist)
ruby utils/release/cli.rb manifest dist
