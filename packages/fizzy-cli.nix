{
  lib,
  stdenvNoCC,
  fetchurl,
}:

# fizzy-cli (https://github.com/basecamp/fizzy-cli) — Basecamp's CLI for Fizzy.
# Distributed as a prebuilt static binary per platform, so we fetch the matching
# release artifact and drop it on PATH; no patchelf needed. The attribute/pname
# is `fizzy-cli` (matching the repo) but the installed binary is `fizzy`.
#
# After install, run `fizzy setup` once to authenticate.
stdenvNoCC.mkDerivation rec {
  pname = "fizzy-cli";
  version = "3.0.3";

  src = fetchurl {
    url =
      let
        plat =
          if stdenvNoCC.hostPlatform.isLinux then
            (if stdenvNoCC.hostPlatform.isAarch64 then "linux-arm64" else "linux-amd64")
          else if stdenvNoCC.hostPlatform.isDarwin then
            (if stdenvNoCC.hostPlatform.isAarch64 then "darwin-arm64" else "darwin-amd64")
          else
            throw "fizzy-cli: unsupported platform ${stdenvNoCC.hostPlatform.system}";
      in
      "https://github.com/basecamp/fizzy-cli/releases/download/v${version}/fizzy-${plat}";

    hash =
      {
        "aarch64-linux" = "sha256-2Obn+P9A8elDH3KXNlRCigPQPKBeG0bYotPdZOyPG5Y=";
        "x86_64-linux" = "sha256-r1vNVFkRaRkxo81nhpE0X8MiHsiE2M7px0ZMxfKPgVQ=";
        "aarch64-darwin" = "sha256-IHtYiFTRthDkZvYvmmfnKTqXH5g8tMNOP9QvkOiU4t4=";
        "x86_64-darwin" = "sha256-mjS7Ys/7zPKhrGgfdsY6OBV3OiFy2/UwItUPRN6Chts=";
      }
      .${stdenvNoCC.hostPlatform.system} or (throw "fizzy-cli: no hash for ${stdenvNoCC.hostPlatform.system}");
  };

  dontUnpack = true;

  installPhase = ''
    runHook preInstall
    install -Dm755 "$src" "$out/bin/fizzy"
    runHook postInstall
  '';

  meta = with lib; {
    description = "Basecamp's CLI for Fizzy";
    homepage = "https://github.com/basecamp/fizzy-cli";
    license = licenses.mit;
    platforms = [
      "aarch64-linux"
      "x86_64-linux"
      "aarch64-darwin"
      "x86_64-darwin"
    ];
    mainProgram = "fizzy";
  };
}
