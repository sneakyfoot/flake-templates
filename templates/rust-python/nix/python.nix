# Pure nix-native python env for the rust binary to embed via pyo3.
#
# Add nixpkgs deps to the `withPackages` list. For deps nixpkgs doesn't have
# (or that need pinning to an exact version like wizard's rpyc 4.1.0), define
# a buildPythonPackage and include it in the list.
{
  pkgs,
  src,
}:

let
  python = pkgs.python313;

  pythonEnv = python.withPackages (
    ps: with ps; [
      # Add deps here, e.g.: requests rich pyyaml
    ]
  );

  pythonSitePkgs = "${pythonEnv}/${python.sitePackages}";

  pythonPath = pkgs.lib.concatStringsSep ":" [
    "${src}"
    pythonSitePkgs
  ];

  pytestEnv = python.withPackages (ps: with ps; [ pytest ]);

  checks = {
    python-ruff = pkgs.runCommand "python-ruff" { nativeBuildInputs = [ pkgs.ruff ]; } ''
      cd ${src}
      export RUFF_CACHE_DIR="$TMPDIR/ruff-cache"
      ruff check --no-cache .
      ruff format --no-cache --check .
      touch $out
    '';

    python-pytest = pkgs.runCommand "python-pytest" { nativeBuildInputs = [ pytestEnv ]; } ''
      export PYTHONPATH=${src}
      cd ${src}
      if find . -type f \( -name 'test_*.py' -o -name '*_test.py' \) | grep -q .; then
        ${pytestEnv}/bin/pytest -q
      else
        echo "no python tests yet — passing trivially"
      fi
      touch $out
    '';
  };
in
{
  inherit
    python
    pythonEnv
    pythonPath
    checks
    ;

  devInputs = [
    pythonEnv
    pkgs.ruff
    pkgs.ty
  ];
}
