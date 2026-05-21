{
  description = "Development shells for HaveAPI";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

  outputs = { nixpkgs, ... }:
    let
      systems = [
        "x86_64-linux"
        "aarch64-linux"
      ];

      forAllSystems = nixpkgs.lib.genAttrs systems;
    in
    {
      devShells = forAllSystems (system:
        let
          pkgs = import nixpkgs { inherit system; };

          promptHook = label: ''
            export HAVEAPI_DEV_SHELL="${label}"
            _haveapi_prompt="[${label}]"

            case "''${PS1:-}" in
              *"''${_haveapi_prompt}"*) ;;
              *)
                if [ -n "''${ZSH_VERSION:-}" ]; then
                  PS1="%F{cyan}''${_haveapi_prompt}%f ''${PS1:-}"
                elif [ -n "''${BASH_VERSION:-}" ]; then
                  PS1="\[\033[36m\]''${_haveapi_prompt}\[\033[0m\] ''${PS1:-}"
                else
                  PS1="''${_haveapi_prompt} ''${PS1:-}"
                fi
                export PS1
                ;;
            esac

            unset _haveapi_prompt
          '';

          repoRootHook = ''
            HAVEAPI_REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
            export HAVEAPI_REPO_ROOT
          '';

          rubyShell =
            {
              name,
              label,
              componentDir,
              gemHome,
              ruby ? pkgs.ruby_3_3,
              packages ? [ ],
              pathSuffix ? "bin",
              installBundler ? "gem install bundler",
              bundleInstall ? "bundle install",
              afterInstall ? "",
            }:
            pkgs.mkShell {
              inherit name;

              packages = [
                ruby
                pkgs.git
                pkgs.openssl
              ] ++ packages;

              shellHook = ''
                ${promptHook label}
                ${repoRootHook}
                export GEM_HOME="${gemHome}"
                export BUNDLE_GEMFILE="$HAVEAPI_REPO_ROOT/${componentDir}/Gemfile"
                export PATH="$GEM_HOME/${pathSuffix}:$PATH"
                (cd "$HAVEAPI_REPO_ROOT/${componentDir}" && ${installBundler} && ${bundleInstall})
                ${afterInstall}
              '';
            };
        in
        {
          default = pkgs.mkShell {
            name = "haveapi";

            packages = with pkgs; [
              git
              gnumake
              nodejs
              php83
              php83Packages.composer
              php83Packages.php-cs-fixer
              ruby_3_3
            ];

            shellHook = ''
              ${promptHook "haveapi"}
              ${repoRootHook}
              export GEM_HOME="$HAVEAPI_REPO_ROOT/.gems"
              export PATH="$GEM_HOME/bin:$PATH"
              export RUBOCOP_CACHE_ROOT="$HAVEAPI_REPO_ROOT/.rubocop_cache"
              gem install --no-document bundler

              # Purity disabled because of prism gem, which has a native extension.
              # The extension has its header files in .gems, which gets stripped by
              # the cc wrapper in Nix. Without NIX_ENFORCE_PURITY=0, we get a
              # prism.h not found error.
              (cd "$HAVEAPI_REPO_ROOT" && NIX_ENFORCE_PURITY=0 bundle install)
            '';
          };

          server-ruby = rubyShell {
            name = "haveapi";
            label = "haveapi:server-ruby";
            componentDir = "servers/ruby";
            gemHome = "$HAVEAPI_REPO_ROOT/.gems";
          };

          client-ruby = rubyShell {
            name = "haveapi-client";
            label = "haveapi:client-ruby";
            componentDir = "clients/ruby";
            gemHome = "$HAVEAPI_REPO_ROOT/.gems";
          };

          client-js = pkgs.mkShell {
            name = "haveapi-client-js";

            packages = [
              pkgs.nodejs
            ];

            shellHook = ''
              ${promptHook "haveapi:client-js"}
              ${repoRootHook}
            '';
          };

          client-go = rubyShell {
            name = "haveapi-go-client";
            label = "haveapi:client-go";
            componentDir = "clients/go";
            gemHome = "$HAVEAPI_REPO_ROOT/clients/go/.gems";
            packages = [
              pkgs.go
              pkgs.gotools
            ];
            bundleInstall = "bundler install";
            afterInstall = "export RUBYOPT=-rbundler/setup";
          };

          example-ruby-activerecord-auth = rubyShell {
            name = "haveapi-example-servers-ruby";
            label = "haveapi:example-ruby-activerecord-auth";
            componentDir = "examples/servers/ruby/activerecord_auth";
            gemHome = "$HAVEAPI_REPO_ROOT/.gems";
            packages = [
              pkgs.sqlite
            ];
          };
        });
    };
}
