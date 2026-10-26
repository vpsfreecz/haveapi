let
  pkgs = import (builtins.fetchTree {
    type = "github";
    owner = "NixOS";
    repo = "nixpkgs";
    rev = "02c087f3fe673c9e317f206a627cb6b910336dbe";
    narHash = "sha256-IoNisKcGbUjdd45qCqywGMCYmZ5EnkxezvLII0FWwNA=";
  }) { };
in
pkgs.mkShell {
  name = "haveapi-benchmarks";
  packages = with pkgs; [ ruby_3_4 git gnumake pkg-config openssl libffi ];
  LD_LIBRARY_PATH = pkgs.lib.makeLibraryPath [ pkgs.stdenv.cc.cc.lib ];
  shellHook = ''
    for name in ''${!BUNDLE@}; do unset "$name"; done
    unset RUBYOPT RUBYLIB RUBYGEMS_GEMDEPS
    export GEM_HOME="''${HAVEAPI_BENCHMARK_GEM_HOME:-${toString ./.}/.gems}"
    export GEM_PATH="$GEM_HOME:${pkgs.ruby_3_4}/lib/ruby/gems/3.4.0"
    export PATH="$GEM_HOME/bin:$PATH"
  '';
}
