{ pkgs, pyproject ? ../clients/python/pyproject.toml }:

let
  project = builtins.fromTOML (builtins.readFile pyproject);
  requirements = project.dependency-groups.dev or [ ];
  ruffRequirements = builtins.filter (requirement:
    builtins.isString requirement
    && builtins.match "[[:space:]]*[Rr][Uu][Ff][Ff]([^A-Za-z0-9._-].*)?" requirement != null
  ) requirements;
  exactPin =
    if builtins.length ruffRequirements != 1 then
      throw "Python Ruff parity requires exactly one Ruff dev requirement"
    else
      builtins.match
        "[[:space:]]*[Rr][Uu][Ff][Ff][[:space:]]*==[[:space:]]*([0-9]+\\.[0-9]+\\.[0-9]+)[[:space:]]*"
        (builtins.head ruffRequirements);
  version =
    if exactPin == null then
      throw "Python Ruff parity requires an exact Ruff dev pin (ruff==X.Y.Z)"
    else
      builtins.head exactPin;
in
assert pkgs.lib.assertMsg (version == pkgs.ruff.version)
  "Python Ruff pin ${version} differs from Nix Ruff ${pkgs.ruff.version}";
pkgs.runCommand "python-ruff-parity" { } ''
  actual="$(${pkgs.ruff}/bin/ruff --version)"
  if [ "$actual" != "ruff ${version}" ]; then
    echo "Python Ruff pin ${version} differs from executable $actual" >&2
    exit 1
  fi
  touch "$out"
''
