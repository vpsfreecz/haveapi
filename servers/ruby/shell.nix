let
  pkgs = import <nixpkgs> {};
  stdenv = pkgs.stdenv;

in stdenv.mkDerivation rec {
  name = "haveapi";

  buildInputs = with pkgs;[
    ruby
    git
    openssl
  ];

  shellHook = ''
    export GEM_HOME=$(pwd)/../../.gems
    export PATH="$GEM_HOME/.gems/bin:$PATH"
    gem install bundler
    bundle install
  '';
}
