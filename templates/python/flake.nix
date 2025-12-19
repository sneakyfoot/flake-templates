{
  description = "notebook: a lightweight command line notebook helper";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";

    pyproject-nix = {
      url = "github:pyproject-nix/pyproject.nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    uv2nix = {
      url = "github:pyproject-nix/uv2nix";
      inputs.pyproject-nix.follows = "pyproject-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    pyproject-build-systems = {
      url = "github:pyproject-nix/build-system-pkgs";
      inputs.pyproject-nix.follows = "pyproject-nix";
      inputs.uv2nix.follows = "uv2nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    {
      nixpkgs,
      pyproject-nix,
      uv2nix,
      pyproject-build-systems,
      ...
    }:
    let
      inherit (nixpkgs) lib;
      forAllSystems = lib.genAttrs lib.systems.flakeExposed;

      workspace = uv2nix.lib.workspace.loadWorkspace { workspaceRoot = ./.; };

      overlay = workspace.mkPyprojectOverlay {
        sourcePreference = "wheel";
      };

      pythonSets = forAllSystems (
        system:
        let
          pkgs = nixpkgs.legacyPackages.${system};
          python = lib.head (pyproject-nix.lib.util.filterPythonInterpreters {
            inherit (workspace) requires-python;
            inherit (pkgs) pythonInterpreters;
          });
        in
        (pkgs.callPackage pyproject-nix.build.packages {
          inherit python;
        }).overrideScope
          (
            lib.composeManyExtensions [
              pyproject-build-systems.overlays.wheel
              overlay
            ]
          )
      );

    in
    {
      packages = forAllSystems (
        system:
        let
          pythonSet = pythonSets.${system};
          pkgs = nixpkgs.legacyPackages.${system};
          inherit (pkgs.callPackages pyproject-nix.build.util { }) mkApplication;
          notebookApp = mkApplication {
            venv = pythonSet.mkVirtualEnv "application-env" workspace.deps.default;
            package = pythonSet.notebook;
          };
        in
        {
          default = notebookApp;
          notebook = notebookApp;
          notebookPackage = pythonSet.notebook;
        }
      );

      devShells = forAllSystems (
        system:
        let
          pkgs = nixpkgs.legacyPackages.${system};
          uvDevShell = pkgs.mkShell {
            packages = [
              pkgs.uv
              pkgs.stdenv.cc
              pkgs.openssl
              pkgs.zlib
            ];
            shellHook = ''
              unset PYTHONPATH
              export UV_PYTHON_PREFERENCE=only-managed
              export UV_PYTHON_DOWNLOADS=automatic
            '';
          };
        in
        {
          default = uvDevShell;
          uvDev = uvDevShell;
        }
      );
    };
}
