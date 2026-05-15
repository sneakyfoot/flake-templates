# Impure uv-managed python — two-stage build.
#
# uvDeps  (stage 1) : src = pyproject.toml + uv.lock only
#                     -> $out/python (interpreter) + $out/cache (wheel cache)
#                     Comment edits in src don't invalidate this.
#
# uvBundle (stage 2): src = full repo
#                     -> $out/venv  (project venv built fresh against stage-1 cache)
#                     Stage 1 referenced via store path; uv runs --offline.
#
# Critical gotcha: $UV_CACHE_DIR must be writable in stage 2 — uv mutates cache
# metadata even with --offline. cp the cache to scratch + chmod u+w.
{
  pkgs,
  lib,
  appName,
  entrypoint,
  pythonSpec,
  src,
}:

let
  isLinux = pkgs.stdenv.isLinux;
  gpuLibPath = "/run/opengl-driver/lib:/run/opengl-driver-32/lib";

  # Toolchain for both stages. nix-ld libs covered separately as NIX_LD_LIBRARY_PATH.
  toolchain = with pkgs; [
    uv
    ruff
    ty
    cacert
    makeWrapper
    stdenv.cc
    zlib
    openssl
  ];

  # nix-ld attrs must be on the derivation (not Config.Env) so they reach the
  # builder env. The container's runtime env doesn't propagate into nix builds.
  nixLdAttrs = {
    NIX_LD = pkgs.stdenv.cc.bintools.dynamicLinker;
    NIX_LD_LIBRARY_PATH = lib.makeLibraryPath (
      with pkgs;
      [
        stdenv.cc.cc.lib
        glibc
        zlib
        openssl
        bzip2
        xz
        libffi
        libxml2
        zstd
        ncurses
        readline
        sqlite
        expat
        gmp
        mpfr
        icu
        krb5
        curl
        libuuid
      ]
    );
  };

  uvDeps = pkgs.stdenvNoCC.mkDerivation (
    nixLdAttrs
    // {
      pname = "${appName}-uv-deps";
      version = "0.1.0";
      src = lib.fileset.toSource {
        root = src;
        fileset = lib.fileset.unions [
          (src + "/pyproject.toml")
          (src + "/uv.lock")
        ];
      };
      __noChroot = true;
      allowSubstitutes = true;
      dontFixup = true;
      nativeBuildInputs = toolchain;
      installPhase = ''
        set -euo pipefail
        export HOME="$TMPDIR/home"
        mkdir -p "$HOME"
        export UV_CACHE_DIR="$out/cache"
        export UV_PYTHON_INSTALL_DIR="$out/python"
        export UV_MANAGED_PYTHON=1
        uv python install ${pythonSpec}
        UV_PROJECT_ENVIRONMENT="$TMPDIR/scratch-venv" \
          uv sync --frozen --no-dev --no-editable --no-install-project
      '';
    }
  );

  uvBundle = pkgs.stdenvNoCC.mkDerivation (
    nixLdAttrs
    // {
      pname = "${appName}-uv-bundle";
      version = "0.1.0";
      inherit src;
      __noChroot = true;
      allowSubstitutes = true;
      dontFixup = true;
      nativeBuildInputs = toolchain;
      installPhase = ''
        set -euo pipefail
        export HOME="$TMPDIR/home"
        mkdir -p "$HOME"
        # uv mutates cache metadata even in --offline mode; copy to writable scratch.
        cp -r ${uvDeps}/cache "$TMPDIR/uv-cache"
        chmod -R u+w "$TMPDIR/uv-cache"
        export UV_CACHE_DIR="$TMPDIR/uv-cache"
        export UV_PYTHON_INSTALL_DIR="${uvDeps}/python"
        export UV_PROJECT_ENVIRONMENT="$out/venv"
        export UV_MANAGED_PYTHON=1
        uv venv --python ${pythonSpec}
        uv sync --frozen --no-dev --no-editable --offline
      '';
    }
  );

  cli = pkgs.stdenvNoCC.mkDerivation {
    pname = appName;
    version = "0.1.0";
    dontUnpack = true;
    nativeBuildInputs = [ pkgs.makeWrapper ];
    installPhase = ''
      set -euo pipefail
      mkdir -p "$out/bin"
      makeWrapper "${uvBundle}/venv/bin/${entrypoint}" "$out/bin/${entrypoint}" \
        --run 'if [ -d /run/opengl-driver/lib ]; then export LD_LIBRARY_PATH="${gpuLibPath}:''${LD_LIBRARY_PATH:-}"; fi'
    '';
  };

  ruffCheck = pkgs.runCommand "${appName}-ruff" { nativeBuildInputs = [ pkgs.ruff ]; } ''
    cd ${src}
    export RUFF_CACHE_DIR="$TMPDIR/ruff-cache"
    ruff check src
    ruff format --check src
    touch $out
  '';

in
{
  inherit cli;

  packages = {
    "uv-deps" = uvDeps;
    "uv-bundle" = uvBundle;
  };

  checks = {
    ruff = ruffCheck;
  };

  devInputs = toolchain;
  env = {
    UV_MANAGED_PYTHON = "1";
    UV_PROJECT_ENVIRONMENT = ".venv";
  };
  shellHook = ''
    set -euo pipefail
    ${lib.optionalString isLinux ''
      if [ -d /run/opengl-driver/lib ]; then
        export LD_LIBRARY_PATH="${gpuLibPath}:''${LD_LIBRARY_PATH:-}"
      fi
    ''}
  '';
}
