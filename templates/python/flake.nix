{
  description = "uv (impure dev) + uv2nix (pure ship)";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

    pyproject-nix = {
      url = "github:pyproject-nix/pyproject.nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    uv2nix = {
      url = "github:pyproject-nix/uv2nix";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.pyproject-nix.follows = "pyproject-nix";
    };

    pyproject-build-systems = {
      url = "github:pyproject-nix/build-system-pkgs";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.pyproject-nix.follows = "pyproject-nix";
      inputs.uv2nix.follows = "uv2nix";
    };
  };

  outputs =
    { self
    , nixpkgs
    , pyproject-nix
    , uv2nix
    , pyproject-build-systems
    , ...
    }:
    let
      system = "x86_64-linux";

      pkgs = nixpkgs.legacyPackages.${system};
      lib = pkgs.lib;

      app = "my-cli";
      module = "my_package";

      workspace = uv2nix.lib.workspace.loadWorkspace { workspaceRoot = ./.; };

      overlay = workspace.mkPyprojectOverlay {
        sourcePreference = "wheel"; # or "sdist"
      };

      python = pkgs.python314;

      pythonSet =
        (pkgs.callPackage pyproject-nix.build.packages { inherit python; }).overrideScope
          (lib.composeManyExtensions [
            pyproject-build-systems.overlays.default
            overlay

            (final: prev: {
              # Put "this wheel needs extra libs" fixups here when something explodes.
              # Example:
              # psycopg2 = prev.psycopg2.overrideAttrs (old: {
              #   buildInputs = (old.buildInputs or []) ++ [ pkgs.postgresql ];
              # });
            })
          ]);

      venv = pythonSet.mkVirtualEnv "${app}-venv" workspace.deps.default;

      cli = pkgs.writeShellApplication {
        name = app;

        runtimeInputs = [ venv ];

        text = ''
          exec ${venv}/bin/python -m ${module} "$@"
        '';
      };

      nixldLibs = [
        pkgs.stdenv.cc.cc
        pkgs.zlib
        pkgs.openssl
        pkgs.libffi
        pkgs.xz
        pkgs.bzip2
      ];

    in
    {
      packages.${system} = {
        default = cli;
        venv = venv;
      };

      apps.${system}.default = {
        type = "app";
        program = "${cli}/bin/${app}";
      };

      checks.${system}.default = self.packages.${system}.default;

      devShells.${system}.default = pkgs.mkShell {
        packages = [
          pkgs.uv

          pkgs.git
          pkgs.pkg-config
          pkgs.cmake
          pkgs.gcc

          python
        ];

        env =
          {
            UV_PROJECT_ENVIRONMENT = ".venv";
            UV_CACHE_DIR = ".uv-cache";

            # Force uv to use nixpkgs Python (comment these out to let uv manage Python)
            # UV_PYTHON = "${python}/bin/python3";
            # UV_NO_MANAGED_PYTHON = "1";
          }
          // lib.optionalAttrs pkgs.stdenv.isLinux {
            NIX_LD = pkgs.stdenv.cc.bintools.dynamicLinker;
            NIX_LD_LIBRARY_PATH = lib.makeLibraryPath nixldLibs;
          };

        shellHook = ''
          unset PYTHONPATH
        '';
      };
    };
}

