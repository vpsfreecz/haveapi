let
  pkgs = import <nixpkgs> {};
  stdenv = pkgs.stdenv;

in stdenv.mkDerivation rec {
  name = "haveapi";

  buildInputs = with pkgs; [
    git
    gnumake
    nodejs
    ruby
  ];

  shellHook = ''
    export GEM_HOME=$(pwd)/.gems
    export PATH="$GEM_HOME/bin:$PATH"
    gem install bundler
  '';
}
