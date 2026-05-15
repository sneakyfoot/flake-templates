# Pure nix-native python — deps from nixpkgs via python.withPackages.
#
# When you need a package nixpkgs doesn't have (or at a different version):
# define a custom buildPythonPackage and pass it via depsFn.
#
#   pythonNixDeps = ps: with ps; [ requests rich ] ++ [ myCustomPkg ];
#
# See wizard/nix/python.nix or oom/main/pkg/pipeline/houdini/houdini-pipeline.nix
# for examples of hand-built buildPythonPackage derivations.
{
  pkgs,
  lib,
  appName,
  entrypoint,
  moduleName,
  python,
  depsFn,
  src,
  pythonSrcDir,
}:

let
  pythonEnv = python.withPackages depsFn;
  pythonSitePkgs = "${pythonEnv}/${python.sitePackages}";
  pythonPath = lib.concatStringsSep ":" [
    "${pythonSrcDir}"
    pythonSitePkgs
  ];

  cli = pkgs.stdenvNoCC.mkDerivation {
    pname = appName;
    version = "0.1.0";
    dontUnpack = true;
    nativeBuildInputs = [ pkgs.makeWrapper ];
    installPhase = ''
      set -euo pipefail
      mkdir -p "$out/bin"
      # Prefer a console_scripts entry if pyproject.toml defined one and the
      # project is in PYTHONPATH; fall back to `python -m <moduleName>`.
      makeWrapper "${pythonEnv}/bin/python" "$out/bin/${entrypoint}" \
        --prefix PYTHONPATH : "${pythonPath}" \
        --add-flags "-m ${moduleName}"
    '';
  };

  ruffCheck = pkgs.runCommand "${appName}-ruff" { nativeBuildInputs = [ pkgs.ruff ]; } ''
    cd ${src}
    export RUFF_CACHE_DIR="$TMPDIR/ruff-cache"
    ruff check src
    ruff format --check src
    touch $out
  '';

  pytestCheck =
    pkgs.runCommand "${appName}-pytest"
      { nativeBuildInputs = [ (python.withPackages (ps: (depsFn ps) ++ [ ps.pytest ])) ]; }
      ''
        cd ${src}
        export PYTHONPATH="${src}/src"
        if find . -path ./.git -prune -o -type f \( -name 'test_*.py' -o -name '*_test.py' \) -print | grep -q .; then
          pytest -q
        else
          echo "no python tests yet — passing trivially"
        fi
        touch $out
      '';

in
{
  inherit cli pythonEnv pythonPath;

  packages = {
    "python-env" = pythonEnv;
  };

  checks = {
    ruff = ruffCheck;
    pytest = pytestCheck;
  };

  devInputs = [
    pythonEnv
    pkgs.ruff
    pkgs.ty
  ];

  env = {
    PYTHONPATH = pythonPath;
  };
  shellHook = "";
}
