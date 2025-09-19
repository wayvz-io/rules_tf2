{
  description = "Terraform rules for Bazel - rules_tf2";

  # Flake inputs
  inputs = {
    # Latest stable Nixpkgs
    nixpkgs.url = "https://flakehub.com/f/NixOS/nixpkgs/0";
    nixpkgs-unstable.url = "https://flakehub.com/f/NixOS/nixpkgs/0.1";
    flake-compat.url = "https://flakehub.com/f/edolstra/flake-compat/1.1.0.tar.gz";
    flake-utils.url = "https://flakehub.com/f/numtide/flake-utils/0.1.102.tar.gz";
  };

  # Flake outputs
  outputs =
    {
      nixpkgs,
      nixpkgs-unstable,
      flake-utils,
      ...
    }:
    flake-utils.lib.eachDefaultSystem (
      system:
      let
        pkgs = import nixpkgs {
          inherit system;
          config.allowUnfree = true;
        };

        pkgs-unstable = import nixpkgs-unstable {
          inherit system;
          config.allowUnfree = true;
        };


      in
      {
        devShells.default =
          with pkgs;
          mkShell {
            name = "rules_tf2-dev";

            packages = [
              # Bazel 7
              bazel_7
              bazel-buildtools
              bazel-gazelle
              bazel-watcher

              # C Language
              gcc
              gnumake

              # Python
              python313
              virtualenv

              # Golang
              go_1_24
              gotools
              gopls
              go-outline
              gopkgs

              # Keep CDKTF CLI since it's not replaced by our tool system
              pkgs-unstable.nodePackages_latest.cdktf-cli

              # Development tools
              git
              gnupg
              jq
              ripgrep
              tree

              # Documentation tools
              mdbook

              # Tools for running pre-compiled binaries in Nix environment
              # Terraform providers are distributed as pre-compiled binaries
              # that expect standard FHS library locations
              patchelf
              
              # Standard libraries that providers might need
              stdenv.cc.cc.lib  # Provides libstdc++.so.6 and other C++ libs
              zlib              # Common compression library
              glibc             # Standard C library
            ];

            shellHook = ''
              # Ensure Go bin directory is in PATH first
              export PATH="$PATH:$(go env GOPATH)/bin"

              # Enable Bazel tab completion
              if [ -n "$BASH" ]; then
                # For Bash shell
                source ${bazel_7}/share/bash-completion/completions/bazel.bash
              elif [ -n "$ZSH_VERSION" ]; then
                # For Zsh shell - use native Zsh completion
                fpath=(${bazel_7}/share/zsh/site-functions $fpath)
                autoload -U compinit && compinit
                # Force reload of bazel completion
                autoload -U _bazel
              fi

              echo "rules_tf2 development environment"
              echo "Bazel version: $(bazel --version)"
              echo "Go version: $(go version)"
              echo "Note: Terraform tools are now managed by Bazel (terraform, tflint, terraform-docs)"

              # Don't mess with library paths - let providers use system libraries
              # The Terraform providers are standard Linux binaries that should work
              # with the host system's libraries
            '';
          };
      }
    );
}