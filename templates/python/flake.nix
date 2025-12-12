{
  description = "hello-uv: minimal uv + nix flake template (x86_64-linux)";

  inputs.nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";

  outputs = { self, nixpkgs }:
    let
      system = "x86_64-linux";
      pkgs = import nixpkgs { inherit system; };

      python = pkgs.python314;
      uv = pkgs.uv;

      src = pkgs.lib.cleanSource ./.;
    in
    {
      devShells.${system}.default = pkgs.mkShell {
        packages = [ python uv ];
      };

      packages.${system}.default = pkgs.writeShellApplication {
        name = "hello-uv";
        runtimeInputs = [ uv python ];
        text = ''
          set -euo pipefail
          APP="hello-uv"
          export UV_PYTHON="${python}/bin/python3.14"
          # don't let uv download/choose its own python
          export UV_NO_MANAGED_PYTHON=1
          export UV_NO_PYTHON_DOWNLOADS=1
          # system-level state/caching (provided by your NixOS tmpfiles)
          export UV_PROJECT_ENVIRONMENT="''${UV_PROJECT_ENVIRONMENT:-/var/uv/venvs/$APP}"
          export UV_CACHE_DIR="''${UV_CACHE_DIR:-/var/uv/cache}"
          mkdir -p "$UV_PROJECT_ENVIRONMENT" "$UV_CACHE_DIR"
          test -w "$UV_PROJECT_ENVIRONMENT" || {
            echo "Not writable: $UV_PROJECT_ENVIRONMENT" >&2
            echo "Fix perms via NixOS tmpfiles (/var/uv) or override UV_PROJECT_ENVIRONMENT." >&2
            exit 1
          }
          test -w "$UV_CACHE_DIR" || {
            echo "Not writable: $UV_CACHE_DIR" >&2
            echo "Fix perms via NixOS tmpfiles (/var/uv) or override UV_CACHE_DIR." >&2
            exit 1
          }
          cd ${src}
          # converge venv to uv.lock (installs + removes), but never edits the lock
          uv sync --frozen --no-dev
          # run the actual console script (from [project.scripts])
          uv run --frozen --no-dev --no-sync hello-uv "$@"
        '';

      };

      apps.${system}.default = {
        type = "app";
        program = "${self.packages.${system}.default}/bin/hello-uv";
      };
    };
}

