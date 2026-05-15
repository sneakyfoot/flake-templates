{
  description = "Master template — python ± rust accelerator. impure-uv default.";

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
      appName = "hello-world";
      entrypoint = "hello-world"; # console_scripts name in pyproject.toml
      moduleName = "hello_world"; # `python -m <moduleName>` fallback
      defaultRepo = "ghcr.io/USER/${appName}";

      # "uv"  — impure uv-managed deps (default; ML-friendly, latest PyPI)
      # "nix" — pure nixpkgs deps via withPackages (deterministic, no network)
      pythonMode = "uv";

      # uv mode: portable cpython spec uv will install.
      pythonSpec = "3.13";

      # nix mode: nixpkgs python attr + dep selector + module location.
      pythonAttr = pkgs: pkgs.python313;
      pythonNixDeps =
        ps: with ps; [
          # Add nixpkgs deps here, e.g.: requests rich pyyaml
        ];
      # Subpath under the flake root that contains the importable modules.
      # `./src` matches the src layout this template ships with. Use `./.`
      # for flat layouts (modules at the repo root).
      pythonSrcDir = ./src;

      # Set to `{ name = "..."; src = ./native/<name>; }` to enable a sidecar
      # rust crate built alongside the python bundle. Output goes to bin/<name>.
      # null disables — no Cargo.toml needed at the repo root.
      rustAccelerator = null;
      # rustAccelerator = { name = "${appName}-fast"; src = ./native/${appName}-fast; };

      # ─── Boilerplate below ─────────────────────────────
      systems = [
        "x86_64-linux"
        "aarch64-darwin"
      ];
      forAllSystems = f: lib.genAttrs systems (system: f system);

      perSystem =
        system:
        let
          pkgs = import nixpkgs {
            inherit system;
            config.allowUnfree = true;
          };
          isLinux = pkgs.stdenv.isLinux;
          craneLib = crane.mkLib pkgs;

          pythonUv = import ./nix/python-uv.nix {
            inherit
              pkgs
              lib
              appName
              entrypoint
              pythonSpec
              ;
            src = ./.;
          };

          pythonNix = import ./nix/python-nix.nix {
            inherit
              pkgs
              lib
              appName
              entrypoint
              moduleName
              pythonSrcDir
              ;
            python = pythonAttr pkgs;
            depsFn = pythonNixDeps;
            src = ./.;
          };

          py = if pythonMode == "uv" then pythonUv else pythonNix;

          rust =
            if rustAccelerator == null then
              null
            else
              import ./nix/rust.nix {
                inherit pkgs craneLib;
                inherit (rustAccelerator) name src;
              };

          image = import ./nix/image.nix {
            inherit
              pkgs
              lib
              appName
              defaultRepo
              ;
            cli = py.cli;
            extraBin = if rust == null then [ ] else [ rust.package ];
            needsNixLd = pythonMode == "uv";
          };
        in
        {
          inherit
            pkgs
            isLinux
            py
            rust
            image
            ;
        };

    in
    {

      devShells = forAllSystems (
        system:
        let
          s = perSystem system;
        in
        {
          default = s.pkgs.mkShell {
            packages =
              s.py.devInputs
              ++ lib.optionals (s.rust != null) s.rust.devInputs
              ++ (with s.pkgs; [
                git
                nixfmt
                nixd
              ]);
            inherit (s.py) env;
            shellHook = s.py.shellHook;
          };
        }
      );

      packages = forAllSystems (
        system:
        let
          s = perSystem system;
        in
        s.py.packages
        // lib.optionalAttrs (s.rust != null) { ${rustAccelerator.name} = s.rust.package; }
        // lib.optionalAttrs s.isLinux {
          image = s.image.image;
          push-image = s.image.pushApp;
        }
        // {
          ${appName} = s.py.cli;
          default = s.py.cli;
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
            program = "${s.py.cli}/bin/${entrypoint}";
          };
          default = {
            type = "app";
            program = "${s.py.cli}/bin/${entrypoint}";
          };
        }
        // lib.optionalAttrs (s.rust != null) {
          ${rustAccelerator.name} = {
            type = "app";
            program = "${s.rust.package}/bin/${rustAccelerator.name}";
          };
        }
        // lib.optionalAttrs s.isLinux {
          push-image = {
            type = "app";
            program = "${s.image.pushApp}/bin/${appName}-push";
          };
        }
      );

      checks = forAllSystems (
        system:
        let
          s = perSystem system;
        in
        s.py.checks // lib.optionalAttrs (s.rust != null) s.rust.checks
      );
    };
}
