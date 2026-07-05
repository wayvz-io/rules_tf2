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

        # Bazel 9 from nixpkgs-unstable (matches .bazelversion / CI).
        bazel_9 = pkgs-unstable.bazel_9;

      in
      {
        devShells.default =
          with pkgs;
          mkShell {
            name = "rules_tf2-dev";

            packages = [
              # Builds run via the rules_tf2-dev container (see tools/dev/bazel),
              # not this bazel — it's kept only for shell completion and as a
              # non-RBE fallback. buildifier/gazelle/ibazel remain host-side
              # conveniences.
              bazel_9
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

              # Development tools
              git
              gnupg
              jq
              ripgrep
              tree
            ];

            shellHook = ''
              # Ensure Go bin directory is in PATH first
              export PATH="$PATH:$(go env GOPATH)/bin"

              # Enable Bazel tab completion
              if [ -n "$BASH" ]; then
                # For Bash shell
                source ${bazel_9}/share/bash-completion/completions/bazel.bash
              elif [ -n "$ZSH_VERSION" ]; then
                # For Zsh shell - use native Zsh completion
                fpath=(${bazel_9}/share/zsh/site-functions $fpath)
                autoload -U compinit && compinit
                # Force reload of bazel completion
                autoload -U _bazel
              fi

              echo "rules_tf2 development environment"
              echo "Go version: $(go version)"
              echo "Note: 'bazel' runs in the rules_tf2-dev container (podman); see tools/dev/bazel"
              echo "Note: Terraform tools are managed by Bazel (terraform, tflint, terraform-docs)"

              # Don't mess with library paths - let providers use system libraries
              # The Terraform providers are standard Linux binaries that should work
              # with the host system's libraries
            '';
          };
      }
    );
}
