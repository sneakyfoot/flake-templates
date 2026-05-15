# Crane-based rust workspace with pyo3 wiring.
#
# pyo3 is configured nix-native:
#   - PYO3_PYTHON pins the interpreter at build time so crane's deps cache
#     stays valid across host PATH variations.
#   - postFixup wraps the binary with `--prefix PYTHONPATH` so the embedded
#     interpreter finds python-side code at runtime without env scaffolding.
{
  pkgs,
  craneLib,
  appName,
  src,
  python,
  pythonPath,
}:

let
  version = "0.1.0";

  pyo3Env = {
    PYO3_PYTHON = "${python}/bin/python3";
  };

  cargoArtifacts = craneLib.buildDepsOnly (
    {
      inherit src version;
      pname = "${appName}-deps";
      nativeBuildInputs = [ python ];
      buildInputs = [ python ];
    }
    // pyo3Env
  );

  mkPackage =
    pname:
    craneLib.buildPackage (
      {
        inherit
          src
          cargoArtifacts
          pname
          version
          ;
        cargoExtraArgs = "-p ${pname}";
        doCheck = false;
        nativeBuildInputs = [
          python
          pkgs.makeWrapper
        ];
        buildInputs = [ python ];
        # --prefix (not --set) so an outer PYTHONPATH composes with the
        # template's bundled python module rather than clobbering it.
        postFixup = ''
          if [ -x "$out/bin/${pname}" ]; then
            wrapProgram "$out/bin/${pname}" \
              --prefix PYTHONPATH : "${pythonPath}"
          fi
        '';
      }
      // pyo3Env
    );

  appPkg = mkPackage appName;

  checks = {
    rust-test = craneLib.cargoTest (
      {
        inherit src cargoArtifacts version;
        pname = "${appName}-test";
        nativeBuildInputs = [ python ];
        buildInputs = [ python ];
      }
      // pyo3Env
    );

    rust-clippy = craneLib.cargoClippy (
      {
        inherit src cargoArtifacts version;
        pname = "${appName}-clippy";
        cargoClippyExtraArgs = "--all-targets -- -D warnings";
        nativeBuildInputs = [ python ];
        buildInputs = [ python ];
      }
      // pyo3Env
    );

    rust-fmt = craneLib.cargoFmt {
      inherit src version;
      pname = "${appName}-fmt";
    };
  };
in
{
  packages = {
    ${appName} = appPkg;
  };
  inherit checks pyo3Env;
  devInputs = with pkgs; [
    cargo
    rustc
    rust-analyzer
    rustfmt
    clippy
  ];
}
