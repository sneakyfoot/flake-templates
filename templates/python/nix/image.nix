# Container image (Linux only) — cli + optional rust accelerator + tools.
#
# Two deploy paths:
#   1. This image (immutable, prebuilt, push to your own GHCR repo)
#   2. Use ghcr.io/sneakyfoot/oom-nixrun:latest + `nix run github:USER/REPO#${appName}`
#      (skip building your own image — oom-nixrun has everything to nix-run
#       any flake, including impure uv builds with __noChroot derivations)
#
# Content-addressed tag: skopeo push only when image content actually changes.
{
  pkgs,
  lib,
  appName,
  defaultRepo,
  cli,
  extraBin,
  needsNixLd,
}:

let
  gpuLibPath = "/run/opengl-driver/lib:/run/opengl-driver-32/lib";

  nixLdLibs = with pkgs; [
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
  ];

  # nix-ld stub at /lib64/<dynamicLinker basename>. Only needed for uv mode
  # where portable cpython links against the canonical glibc loader.
  nixLdSetup = pkgs.runCommand "nix-ld-setup" { } ''
    set -euo pipefail
    mkdir -p "$out/lib64"
    install -D -m755 ${pkgs.nix-ld}/libexec/nix-ld \
      "$out/lib64/$(basename ${pkgs.stdenv.cc.bintools.dynamicLinker})"
  '';

  image = pkgs.dockerTools.buildLayeredImage {
    name = appName;
    tag = "latest";
    contents = [
      cli
      pkgs.bash
      pkgs.coreutils
      pkgs.cacert
      pkgs.git
    ]
    ++ extraBin
    ++ lib.optionals needsNixLd [ nixLdSetup ];

    extraCommands = ''
      mkdir -p etc/ssl/certs tmp var/tmp
      chmod 1777 tmp var/tmp
      ln -sf ${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt etc/ssl/certs/ca-certificates.crt
      ln -sf ${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt etc/ssl/certs/ca-bundle.crt
    '';

    config = {
      Cmd = [ "${cli}/bin/${appName}" ];
      Env = [
        "NIX_SSL_CERT_FILE=${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt"
        "SSL_CERT_FILE=${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt"
      ]
      ++ lib.optionals needsNixLd [
        "NIX_LD=${pkgs.stdenv.cc.bintools.dynamicLinker}"
        "NIX_LD_LIBRARY_PATH=${lib.makeLibraryPath nixLdLibs}"
        "LD_LIBRARY_PATH=${gpuLibPath}"
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
  inherit image pushApp imageTag;
}
