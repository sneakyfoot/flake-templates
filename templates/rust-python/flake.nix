{
  description = "rust-python template — rust binary embedding python via pyo3.";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    crane.url = "github:ipetkov/crane";
  };

  outputs =
    {
      self,
      nixpkgs,
      crane,
    }:

    let
      lib = nixpkgs.lib;

      # ─── Edit these ────────────────────────────────────
      # Top-level binary built from `crates/<appName>/`. Must match Cargo.toml.
      appName = "hello";

      systems = [
        "x86_64-linux"
        "aarch64-darwin"
      ];
      forAllSystems = f: lib.genAttrs systems (system: f system);

      perSystem =
        system:
        let
          pkgs = import nixpkgs { inherit system; };
          craneLib = crane.mkLib pkgs;

          rustSrc = craneLib.cleanCargoSource ./.;
          pythonSrc = lib.cleanSource ./python;

          python = import ./nix/python.nix {
            inherit pkgs;
            src = pythonSrc;
          };

          rust = import ./nix/rust.nix {
            inherit pkgs craneLib appName;
            src = rustSrc;
            inherit (python) python pythonPath;
          };

          nixfmtCheck = pkgs.runCommand "${appName}-nixfmt" { nativeBuildInputs = [ pkgs.nixfmt ]; } ''
            find ${self} -name '*.nix' | xargs nixfmt --check
            touch $out
          '';
        in
        {
          inherit
            pkgs
            python
            rust
            nixfmtCheck
            ;
        };
    in
    {
      packages = forAllSystems (
        system:
        let
          s = perSystem system;
        in
        s.rust.packages
        // {
          "python-env" = s.python.pythonEnv;
          default = s.rust.packages.${appName};
        }
      );

      apps = forAllSystems (
        system:
        let
          s = perSystem system;
        in
        {
          ${appName} = {
            type = "app";
            program = "${s.rust.packages.${appName}}/bin/${appName}";
          };
          default = {
            type = "app";
            program = "${s.rust.packages.${appName}}/bin/${appName}";
          };
        }
      );

      checks = forAllSystems (
        system:
        let
          s = perSystem system;
        in
        s.rust.checks // s.python.checks // { nixfmt = s.nixfmtCheck; }
      );

      devShells = forAllSystems (
        system:
        let
          s = perSystem system;
        in
        {
          default = s.pkgs.mkShell {
            packages =
              s.rust.devInputs
              ++ s.python.devInputs
              ++ (with s.pkgs; [
                nixd
                nixfmt
              ]);
            env = {
              PYTHONPATH = s.python.pythonPath;
              RUST_LOG = "info";
            }
            // s.rust.pyo3Env;
          };
        }
      );
    };
}
