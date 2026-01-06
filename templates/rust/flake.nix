{
  description = "Rust dev template";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs?ref=nixos-unstable";
  };

  outputs =
    { self, nixpkgs }:
    let
      systems = [
        "x86_64-linux"
        "aarch64-darwin"
      ];
      forSystems = f: nixpkgs.lib.genAttrs systems (system: f system);
      mkPkgs = system: import nixpkgs { inherit system; };

      mkRustPackage =
        pkgs:
        pkgs.rustPlatform.buildRustPackage {
          pname = "rust-package";
          version = "0.1.0";
          src = pkgs.lib.cleanSource ./.;
          cargoLock = {
            lockFile = ./Cargo.lock;
          };
        };
    in
    {
      packages = forSystems (
        system:
        let
          pkgs = mkPkgs system;
          rust-package = mkRustPackage pkgs;
        in
        {
          default = rust-package;
          rp = rust-package;
        }
      );

      apps = forSystems (
        system:
        let
          pkgs = mkPkgs system;
          rust-package = mkRustPackage pkgs;
        in
        {
          default = {
            type = "app";
            program = "${rust-package}/bin/rp";
          };
        }
      );

      devShells = forSystems (
        system:
        let
          pkgs = mkPkgs system;
          rust-package = mkRustPackage pkgs;
        in
        {
          default = pkgs.mkShell {
            packages = with pkgs; [
              rustc
              cargo
              rust-analyzer
              rustfmt
              pkg-config
            ];
            inputsFrom = [ rust-package ];
          };
        }
      );
    };
}
