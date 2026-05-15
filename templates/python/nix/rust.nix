# Optional rust accelerator built with crane (deps-only cache shared across
# build/test/lint/fmt). Set rustAccelerator = { name; src } in flake.nix to
# enable. The crate must have its own Cargo.lock under src.
{
  pkgs,
  craneLib,
  name,
  src,
}:

let
  cleanSrc = craneLib.cleanCargoSource src;

  cargoArtifacts = craneLib.buildDepsOnly {
    src = cleanSrc;
    pname = "${name}-deps";
    version = "0.1.0";
  };

  package = craneLib.buildPackage {
    src = cleanSrc;
    inherit cargoArtifacts;
    pname = name;
    version = "0.1.0";
    cargoExtraArgs = "-p ${name}";
    doCheck = false;
  };

  checks = {
    "${name}-test" = craneLib.cargoTest {
      src = cleanSrc;
      inherit cargoArtifacts;
      pname = "${name}-test";
    };
    "${name}-clippy" = craneLib.cargoClippy {
      src = cleanSrc;
      inherit cargoArtifacts;
      pname = "${name}-clippy";
      cargoClippyExtraArgs = "--all-targets -- -D warnings";
    };
    "${name}-fmt" = craneLib.cargoFmt {
      src = cleanSrc;
      pname = "${name}-fmt";
    };
  };

in
{
  inherit package checks;
  devInputs = with pkgs; [
    cargo
    rustc
    rust-analyzer
    rustfmt
    clippy
  ];
}
