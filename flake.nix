{
  description = "Terraform rules for Bazel - rules_tf2";

  inputs = {
    nixpkgs.url = "https://flakehub.com/f/NixOS/nixpkgs/0";
    nixpkgs-unstable.url = "https://flakehub.com/f/NixOS/nixpkgs/0.1";
    flake-utils.url = "https://flakehub.com/f/numtide/flake-utils/0.1.102.tar.gz";
  };

  outputs = { nixpkgs, nixpkgs-unstable, flake-utils, ... }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = import nixpkgs {
          inherit system;
          config.allowUnfree = true;
        };
        
        unstablePkgs = import nixpkgs-unstable {
          inherit system;
          config.allowUnfree = true;
        };
      in
      {
        devShells.default = pkgs.mkShell {
          buildInputs = with pkgs; [
            # Bazel
            bazel_7
            bazelisk
            buildifier
            bazel-gazelle
            
            # Go toolchain
            go_1_23
            
            # Terraform tools
            terraform
            terraform-docs
            tflint
            
            # Development tools
            git
            gnupg
            jq
            ripgrep
            tree
            
            # Python for scripts
            python3
            
            # Documentation tools
            mdbook
          ];

          shellHook = ''
            echo "rules_tf2 development environment"
            echo "Bazel version: $(bazel --version)"
            echo "Go version: $(go version)"
            echo "Terraform version: $(terraform --version | head -n1)"
          '';
        };
      }
    );
}