let
  pkgs = import <nixpkgs> {};
  stdenv = pkgs.stdenv;

in stdenv.mkDerivation rec {
  name = "haveapi-example-servers-ruby";

  buildInputs = with pkgs; [
    git
    ruby
    sqlite
  ];

  shellHook = ''
    export GEM_HOME=$(pwd)/../../../../.gems
    export PATH="$GEM_HOME/bin:$PATH"
    gem install bundler
    bundle install
  '';
}
