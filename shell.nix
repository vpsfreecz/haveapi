let
  pkgs = import <nixpkgs> {};
  stdenv = pkgs.stdenv;

in stdenv.mkDerivation rec {
  name = "haveapi";

  buildInputs = with pkgs; [
    git
    gnumake
    nodejs
    php83Packages.composer
    php83Packages.php-cs-fixer
    ruby_3_3
  ];

  shellHook = ''
    export GEM_HOME=$(pwd)/.gems
    export PATH="$GEM_HOME/bin:$PATH"
    gem install --no-document bundler

    # Purity disabled because of prism gem, which has a native extension.
    # The extension has its header files in .gems, which gets stripped but
    # cc wrapper in Nix. Without NIX_ENFORCE_PURITY=0, we get prism.h not found
    # error.
    NIX_ENFORCE_PURITY=0 bundle install
  '';
}
