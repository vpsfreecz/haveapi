let
  pkgs = import <nixpkgs> {};
  stdenv = pkgs.stdenv;

in stdenv.mkDerivation rec {
  name = "haveapi-go-client";

  buildInputs = with pkgs;[
    git
    go
    gotools
    openssl
    ruby
  ];

  shellHook = ''
    export GEM_HOME=$(pwd)/.gems
    export PATH="$GEM_HOME/.gems/bin:$PATH"
    gem install bundler
    bundler install
    #export RUBYOPT=-rbundler/setup
  '';
}
