#!/bin/sh -e
# Copy shared documents to server implementations
# Usage: ./copydoc.sh <server>...

DOC="./doc"

for srv in $@ ; do
    dst="$srv/doc"
    [ ! -d "$dst" ] && mkdir "$dst"
    erb "$DOC"/json-schema.erb > "$dst"/json-schema.html
    cp "$DOC"/*.md "$DOC"/*.png "$dst/"
done
