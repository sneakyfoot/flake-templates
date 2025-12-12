{
  description = "Rust dev template";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs?ref=nixos-unstable";
  };

  outputs = { self, nixpkgs }:
    let
      system = "x86_64-linux";
      pkgs = import nixpkgs { inherit system; };

      rust-package = pkgs.rustPlatform.buildRustPackage {
        pname = "rust-package";
        version = "0.1.0";
        src = pkgs.lib.cleanSource ./.;
        cargoLock = {
          lockFile = ./Cargo.lock;
        };
      };
    in {
      packages.${system} = {
        default = rust-package;
        rp = rust-package;
      };

      apps.${system}.default = {
        type = "app";
        program = "${rust-package}/bin/rp";
      };

      devShells.${system}.default = pkgs.mkShell {
        packages = with pkgs; [
          rustc
          cargo
          rust-analyzer
          rustfmt
          pkg-config
        ];
        inputsFrom = [ rust-package ];
      };
    };
}
