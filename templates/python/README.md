# Master flake template

Default = impure uv python. Toggles in `flake.nix`:

| Knob | Values | What it does |
|---|---|---|
| `appName` / `entrypoint` / `moduleName` | strings | name in pyproject + cli binary name + `python -m` fallback |
| `defaultRepo` | string | GHCR target for `nix run .#push-image` |
| `pythonMode` | `"uv"` (default) / `"nix"` | uv-managed (impure, latest PyPI) vs nixpkgs-managed (pure, deterministic) |
| `pythonSpec` | e.g. `"3.13"` | uv mode: portable cpython version |
| `pythonAttr` / `pythonNixDeps` | functions of pkgs/ps | nix mode: which nixpkgs python + which deps |
| `rustAccelerator` | `null` or `{ name; src; }` | drop in a crane-built rust sidecar (e.g. `./native/<name>`) |

## What you get

- `nix develop` — devshell with the right toolchain for the chosen mode
- `nix build .#default` (= `${appName}`) — builds the cli
- `nix run .#${appName}` — runs the cli
- `nix flake check` — ruff + (pytest if tests exist for nix mode) + clippy/test/fmt (if rust)
- `nix build .#image` (Linux only) — content-addressed container image
- `nix run .#push-image` — pushes to GHCR (needs GITHUB_TOKEN)

## Iteration speed (uv mode)

Source edits don't rebuild deps. Two-stage:
- `uv-deps` hashes only `pyproject.toml` + `uv.lock` → wheel cache + cpython
- `uv-bundle` hashes full source → fresh venv pointing at stage-1 cache

Adding a dep: edit `pyproject.toml`, run `uv lock`, both stages re-run. Editing a comment: only stage 2.

## Skipping the image entirely

For "this isn't ready for its own container yet" cases, deploy with `oom-nixrun` instead of building your own image:

```yaml
image: ghcr.io/sneakyfoot/oom-nixrun:latest
command: ["/bin/nixrun-entrypoint", "nix", "run", "github:USER/REPO#${appName}", "--"]
args: ["..."]
```

oom-nixrun has the nix-ld stub, `sandbox = relaxed`, and uv pre-baked so impure uv flakes build inside it without extra config.
