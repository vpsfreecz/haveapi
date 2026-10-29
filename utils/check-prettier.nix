{ pkgs
, packageJson ? ../clients/js/package.json
, formatter ? ../clients/typescript/lib/haveapi/typescript_client/formatter.rb
}:

let
  package = builtins.fromJSON (builtins.readFile packageJson);
  version = package.devDependencies.prettier or
    (throw "Prettier parity requires an exact npm development dependency");
in
assert pkgs.lib.assertMsg
  (builtins.isString version && builtins.match "[0-9]+\\.[0-9]+\\.[0-9]+" version != null)
  "Prettier parity requires an exact npm version (X.Y.Z)";
assert pkgs.lib.assertMsg (version == pkgs.prettier.version)
  "npm Prettier ${version} differs from Nix Prettier ${pkgs.prettier.version}";
pkgs.runCommand "prettier-parity" { } ''
  actual="$(${pkgs.prettier}/bin/prettier --version)"
  generator="$(${pkgs.ruby}/bin/ruby -e '
    module HaveAPI; module TypeScriptClient; end; end
    require ARGV.fetch(0)
    puts HaveAPI::TypeScriptClient::Formatter::VERSION
  ' ${formatter})"
  if [ "$actual" != "${version}" ] || [ "$generator" != "${version}" ]; then
    echo "Prettier versions differ: npm ${version}, executable $actual, generator $generator" >&2
    exit 1
  fi
  touch "$out"
''
