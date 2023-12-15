let
  pkgs = import <nixpkgs> {};
  stdenv = pkgs.stdenv;

in stdenv.mkDerivation rec {
  name = "haveapi-client";

  buildInputs = with pkgs;[
    ruby_3_1
    git
    openssl
  ];

  shellHook = ''
    export GEM_HOME=$(pwd)/../../.gems
    export PATH="$GEM_HOME/bin:$PATH"
    gem install bundler
    bundle install
  '';
}
