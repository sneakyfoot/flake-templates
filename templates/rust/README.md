# Rust flake template

Pure rust workspace, crane-built. Toggles in `flake.nix`:

| Knob | What it does |
|---|---|
| `appName` | crate name + cli binary name + image name |
| `defaultRepo` | GHCR target for `nix run .#push-image` |

## What you get

- `nix develop` — devshell with cargo / rustc / rust-analyzer / rustfmt / clippy
- `nix build .#default` (= `${appName}`) — builds the binary
- `nix run .#${appName}` — runs the cli
- `nix flake check` — cargo test / clippy / fmt (crane deps cached, shared across checks)
- `nix build .#image` (Linux only) — minimal container with the binary + cacert
- `nix run .#push-image` — pushes to GHCR (needs GITHUB_TOKEN)

For projects that mix rust + python, see the `python` template (set `rustAccelerator = { ... }` for a sidecar) or the `rust-python` template (rust binary embedding python via pyo3).
