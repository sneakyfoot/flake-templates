# rust-python flake template

Rust binary embedding pure-nix python via pyo3. Same pattern as `wizard`:
crane for the rust workspace, `python.withPackages` for the python env,
pyo3 wired so the embedded interpreter resolves bundled python code without
runtime env scaffolding.

## Layout

```
flake.nix              # composer
nix/python.nix         # python env (withPackages) + ruff/pytest checks
nix/rust.nix           # crane workspace + pyo3 wiring (postFixup PYTHONPATH)
Cargo.toml             # workspace
crates/<appName>/      # one rust crate per binary
python/                # python sources, gets put on PYTHONPATH
  pyproject.toml
  hello_tools/         # importable from rust via `py.import("hello_tools")`
```

## What you get

- `nix develop` — rust + python toolchains + PYO3_PYTHON pinned
- `nix build .#default` — crane-built rust binary, PYTHONPATH-wrapped
- `nix run .#hello` — runs it (default binary calls into `hello_tools.greet`)
- `nix flake check` — rust test / clippy / fmt + python ruff / pytest

## Adding python deps

Edit `nix/python.nix`'s `withPackages` list. For deps not in nixpkgs, define a
`buildPythonPackage` derivation and include it.

## Adding more binaries

Drop another crate under `crates/`. In `nix/rust.nix`, call `mkPackage` for
each binary name and add to the `packages` attrset.
