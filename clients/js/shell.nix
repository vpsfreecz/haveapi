let
  pkgs = import <nixpkgs> {};
  stdenv = pkgs.stdenv;

in stdenv.mkDerivation rec {
  name = "haveapi-client-js";

  buildInputs = with pkgs; [
    nodejs
  ];
}
