{
  description = "uv-managed Python template (dev + nix build), with NixOS GPU /run/opengl-driver shim";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  };

  outputs = { self, nixpkgs }:

  let

    system = "x86_64-linux";
    pkgs = import nixpkgs { inherit system; };

    pythonSpec = "3.14";

    appName = "my-app";
    entrypoint = "my-app";

    toolchain =
      [ pkgs.uv pkgs.ruff pkgs.cacert pkgs.makeWrapper pkgs.ty pkgs.zlib pkgs.openssl pkgs.stdenv.cc ];

    # GPU shim (NixOS)
    gpuLibPath = "/run/opengl-driver/lib:/run/opengl-driver-32/lib";

    uvBundle = pkgs.stdenvNoCC.mkDerivation {
      pname = "${appName}-uv-bundle";
      version = "0.1.0";
      src = self;

      # Build with: --option sandbox relaxed
      __noChroot = true;
      preferLocalBuild = true;
      allowSubstitutes = false;
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

        # Main wrapper with GPU shim.
        if [ -x "$out/venv/bin/${entrypoint}" ]; then
          makeWrapper "$out/venv/bin/${entrypoint}" "$out/bin/${entrypoint}" \
            --set PYTHONNOUSERSITE 1 \
            --prefix LD_LIBRARY_PATH : "${gpuLibPath}"
        else
          echo "ERROR: expected entrypoint missing: $out/venv/bin/${entrypoint}" >&2
          echo "Hint: set entrypoint=... to match your [project.scripts] name." >&2
          exit 1
        fi
      '';
    };

  in {

    devShells.${system}.default = pkgs.mkShell {
      packages = toolchain;
      env = {
        UV_MANAGED_PYTHON = "1";
        UV_PYTHON_INSTALL_DIR = ".uv-python";
        UV_PROJECT_ENVIRONMENT = ".venv";
      };
      shellHook = ''
        export LD_LIBRARY_PATH="${gpuLibPath}:''${LD_LIBRARY_PATH:-}"
      '';
    };

    packages.${system} = {
      ${appName} = uvBundle;
      default = uvBundle;
    };

    apps.${system}.default = {
      type = "app";
      program = "${uvBundle}/bin/${entrypoint}";
    };

  };
}

