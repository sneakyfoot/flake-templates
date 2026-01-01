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

      # This is the importable module name for the fallback `python -m ...`
      moduleName = "my_app";
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

              # Optional: keep a runnable wrapper inside the bundle for testing
              mkdir -p "$out/bin"
              if [ -x "$out/venv/bin/${entrypoint}" ]; then
                makeWrapper "$out/venv/bin/${entrypoint}" "$out/bin/${entrypoint}"
              else
                makeWrapper "$out/venv/bin/python" "$out/bin/${entrypoint}" \
                  --add-flags "-m ${moduleName}"
              fi
            '';
          };

          # Thin package: installs only bin/my-app, points at the bundle.
          cli = pkgs.stdenvNoCC.mkDerivation {
            pname = appName;
            version = "0.1.0";

            dontUnpack = true;
            nativeBuildInputs = [ pkgs.makeWrapper ];

            installPhase = ''
              set -euo pipefail
              mkdir -p "$out/bin"

              # Prefer uv-generated console script
              if [ -x "${uvBundle}/venv/bin/${entrypoint}" ]; then
                makeWrapper "${uvBundle}/venv/bin/${entrypoint}" "$out/bin/${entrypoint}"
              else
                # Fallback: run module
                makeWrapper "${uvBundle}/venv/bin/python" "$out/bin/${entrypoint}" \
                  --add-flags "-m ${moduleName}"
              fi
            '';
          };
        in
        {
          uv-bundle = uvBundle;
          ${appName} = cli;
          default = cli;
        }
      );

      apps = forAllSystems (
        system:
        let
          cli = self.packages.${system}.${appName};
        in
        {
          ${appName} = {
            type = "app";
            program = "${cli}/bin/${entrypoint}";
          };
          default = {
            type = "app";
            program = "${cli}/bin/${entrypoint}";
          };
        }
      );
    };
}
