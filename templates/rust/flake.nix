{
  description = "Rust template — crane workspace with optional container image.";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    crane.url = "github:ipetkov/crane";
  };

  outputs =
    {
      self,
      nixpkgs,
      crane,
    }:

    let
      lib = nixpkgs.lib;

      # ─── Edit these ────────────────────────────────────
      appName = "hello-rust";
      defaultRepo = "ghcr.io/USER/${appName}";

      # ─── Boilerplate below ─────────────────────────────
      systems = [
        "x86_64-linux"
        "aarch64-darwin"
      ];
      forAllSystems = f: lib.genAttrs systems (system: f system);

      perSystem =
        system:
        let
          pkgs = import nixpkgs { inherit system; };
          isLinux = pkgs.stdenv.isLinux;
          craneLib = crane.mkLib pkgs;

          src = craneLib.cleanCargoSource ./.;
          version = "0.1.0";

          cargoArtifacts = craneLib.buildDepsOnly {
            inherit src version;
            pname = "${appName}-deps";
          };

          package = craneLib.buildPackage {
            inherit src cargoArtifacts version;
            pname = appName;
            doCheck = false;
          };

          checks = {
            ${appName + "-test"} = craneLib.cargoTest {
              inherit src cargoArtifacts version;
              pname = "${appName}-test";
            };
            ${appName + "-clippy"} = craneLib.cargoClippy {
              inherit src cargoArtifacts version;
              pname = "${appName}-clippy";
              cargoClippyExtraArgs = "--all-targets -- -D warnings";
            };
            ${appName + "-fmt"} = craneLib.cargoFmt {
              inherit src version;
              pname = "${appName}-fmt";
            };
          };

          image = pkgs.dockerTools.buildLayeredImage {
            name = appName;
            tag = "latest";
            contents = [
              package
              pkgs.cacert
            ];
            extraCommands = ''
              mkdir -p etc/ssl/certs tmp var/tmp
              chmod 1777 tmp var/tmp
              ln -sf ${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt etc/ssl/certs/ca-certificates.crt
            '';
            config = {
              Cmd = [ "${package}/bin/${appName}" ];
              Env = [
                "SSL_CERT_FILE=${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt"
              ];
            };
          };

          imageTag = builtins.substring 0 32 (baseNameOf image.outPath);

          skopeoPolicy = pkgs.writeText "skopeo-policy.json" ''
            {
              "default": [{ "type": "insecureAcceptAnything" }],
              "transports": {
                "docker-daemon": { "": [{ "type": "insecureAcceptAnything" }] },
                "docker-archive": { "": [{ "type": "insecureAcceptAnything" }] },
                "docker": { "": [{ "type": "insecureAcceptAnything" }] }
              }
            }
          '';

          pushApp = pkgs.writeShellApplication {
            name = "${appName}-push";
            runtimeInputs = [
              pkgs.skopeo
              pkgs.coreutils
              pkgs.git
              pkgs.nix
            ];
            text = ''
              set -euo pipefail
              : "''${GITHUB_TOKEN:?GITHUB_TOKEN must be set}"

              repo_root="$(git rev-parse --show-toplevel 2>/dev/null || printf '%s\n' "$PWD")"
              flake_ref="''${FLAKE_REF:-$repo_root}"

              registry_repo="''${GHCR_REPO:-${defaultRepo}}"
              actor="''${GITHUB_ACTOR:-USER}"
              creds="$actor:''${GITHUB_TOKEN}"
              content_tag="${imageTag}"

              if skopeo inspect --creds "$creds" "docker://$registry_repo:$content_tag" > /dev/null 2>&1; then
                echo "${appName} image unchanged (tag $content_tag exists), skipping push"
                exit 0
              fi

              system="$(nix eval --raw --impure --expr builtins.currentSystem)"
              image_tarball="$(nix build "$flake_ref#packages.$system.image" --no-link --print-out-paths)"
              tag="''${GHCR_TAG:-$content_tag}"

              echo "Pushing $registry_repo:$tag (content: $content_tag)"
              skopeo copy --retry-times 5 --policy ${skopeoPolicy} \
                --dest-creds "$creds" \
                "docker-archive:$image_tarball" \
                "docker://$registry_repo:$tag"

              if [ "$tag" != "$content_tag" ]; then
                skopeo copy --retry-times 5 --policy ${skopeoPolicy} \
                  --src-creds "$creds" --dest-creds "$creds" \
                  "docker://$registry_repo:$tag" \
                  "docker://$registry_repo:$content_tag"
              fi

              skopeo copy --retry-times 5 --policy ${skopeoPolicy} \
                --src-creds "$creds" --dest-creds "$creds" \
                "docker://$registry_repo:$tag" \
                "docker://$registry_repo:latest"
            '';
          };
        in
        {
          inherit
            pkgs
            isLinux
            craneLib
            package
            checks
            image
            pushApp
            ;
        };
    in
    {
      packages = forAllSystems (
        system:
        let
          s = perSystem system;
        in
        {
          ${appName} = s.package;
          default = s.package;
        }
        // lib.optionalAttrs s.isLinux {
          image = s.image;
          push-image = s.pushApp;
        }
      );

      apps = forAllSystems (
        system:
        let
          s = perSystem system;
        in
        {
          ${appName} = {
            type = "app";
            program = "${s.package}/bin/${appName}";
          };
          default = {
            type = "app";
            program = "${s.package}/bin/${appName}";
          };
        }
        // lib.optionalAttrs s.isLinux {
          push-image = {
            type = "app";
            program = "${s.pushApp}/bin/${appName}-push";
          };
        }
      );

      checks = forAllSystems (system: (perSystem system).checks);

      devShells = forAllSystems (
        system:
        let
          s = perSystem system;
        in
        {
          default = s.pkgs.mkShell {
            packages = with s.pkgs; [
              cargo
              rustc
              rust-analyzer
              rustfmt
              clippy
              nixfmt
              nixd
            ];
            inputsFrom = [ s.package ];
          };
        }
      );
    };
}
