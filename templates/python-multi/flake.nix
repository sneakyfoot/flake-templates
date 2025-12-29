{
  description = "uv-managed Python template (dev + nix build), with NixOS GPU /run/opengl-driver shim";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  };

  outputs =
    { self, nixpkgs }:

    let
      lib = nixpkgs.lib;

      systems = [
        "x86_64-linux"
        "aarch64-darwin"
      ];

      forAllSystems = f: lib.genAttrs systems (system: f system);

      pythonSpec = "3.14";

      appName = "my-app";
      entrypoint = "my-app";
    in
    {
      devShells = forAllSystems (
        system:
        let
          pkgs = import nixpkgs { inherit system; };

          toolchain = [
            pkgs.uv
            pkgs.ruff
            pkgs.cacert
            pkgs.makeWrapper
            pkgs.ty
            pkgs.zlib
            pkgs.openssl
            pkgs.stdenv.cc
          ];

        in
        {
          default = pkgs.mkShell {
            packages = toolchain;
            env = {
              UV_MANAGED_PYTHON = "1";
              UV_PROJECT_ENVIRONMENT = ".venv";
            };
            shellHook = '''';
          };
        }
      );

      packages = forAllSystems (
        system:
        let
          pkgs = import nixpkgs { inherit system; };

          toolchain = [
            pkgs.uv
            pkgs.ruff
            pkgs.cacert
            pkgs.makeWrapper
            pkgs.ty
            pkgs.zlib
            pkgs.openssl
            pkgs.stdenv.cc
          ];

          uvBundle = pkgs.stdenvNoCC.mkDerivation {
            pname = "${appName}-uv-bundle";
            version = "0.1.0";
            src = self;

            # Build with: --option sandbox relaxed
            __noChroot = true;
            allowSubstitutes = true;
            dontFixup = true;

            nativeBuildInputs = toolchain;

            installPhase = ''
              set -euo pipefail

              export HOME="$TMPDIR/home"
              mkdir -p "$HOME"

              export UV_CACHE_DIR="$TMPDIR/uv-cache"

              export UV_MANAGED_PYTHON=1

              export UV_PYTHON_INSTALL_DIR="$out/python"
              export UV_PROJECT_ENVIRONMENT="$out/venv"

              uv python install ${pythonSpec}
              uv venv --python ${pythonSpec}
              uv sync --frozen --no-dev --no-editable

              mkdir -p "$out/bin"
            '';
          };
        in
        {
          ${appName} = uvBundle;
          default = uvBundle;
        }
      );

      apps = forAllSystems (
        system:
        let
          uvBundle = self.packages.${system}.${appName};
        in
        {
          default = {
            type = "app";
            program = "${uvBundle}/bin/${entrypoint}";
          };
        }
      );
    };
}
