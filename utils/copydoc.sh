#!/bin/sh -e
# Copy shared documents to server implementations.
# Usage: ./copydoc.sh <server>...

DOC="./doc"

for srv in "$@"; do
    dst="$srv/doc"
    mkdir -p "$dst"

    # Remove only the obsolete flat copies owned by this script.
    for article in "$DOC"/en/*.md; do
        rm -f "$dst/$(basename "$article")"
    done
    rm -f "$dst/json-schema.html"

    for locale in en cs; do
        mkdir -p "$dst/$locale"
        cp "$DOC/$locale/"*.md "$dst/$locale/"
        ruby -rerb -ryaml -e '
            catalog = YAML.load_file(ARGV.fetch(2))
            schema_envelope = catalog.fetch(ARGV.fetch(1)).fetch("haveapi")
                .fetch("documentation").fetch("schema").fetch("envelope")
            print ERB.new(File.read(ARGV.fetch(0))).result(binding)
        ' "$DOC/json-schema.erb" "$locale" ./i18n/haveapi.yml > "$dst/$locale/json-schema.html"
    done
    cp "$DOC/"*.png "$dst/"
done
