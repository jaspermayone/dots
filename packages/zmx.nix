{
  pkgs,
  lib,
  stdenv,
  fetchurl,
  autoPatchelfHook,
}:

stdenv.mkDerivation rec {
  pname = "zmx";
  version = "0.3.0";

  src = fetchurl {
    url =
      if stdenv.isLinux then
        (
          if stdenv.isAarch64 then
            "https://zmx.sh/a/zmx-${version}-linux-aarch64.tar.gz"
          else
            "https://zmx.sh/a/zmx-${version}-linux-x86_64.tar.gz"
        )
      else if stdenv.isDarwin then
        (
          if stdenv.isAarch64 then
            "https://zmx.sh/a/zmx-${version}-macos-aarch64.tar.gz"
          else
            "https://zmx.sh/a/zmx-${version}-macos-x86_64.tar.gz"
        )
      else
        throw "Unsupported platform";

    hash =
      if stdenv.isLinux && stdenv.isAarch64 then
        "sha256-OTMWzGzOjPZGdr4hj3TTNqbG2OcRc0Ifd0QLaAoRlLQ="
      else if stdenv.isLinux then
        "sha256-/K/xWB61pqPll4Gq13qMoGm0Q1vC/sQT3TI7RaTf3zI="
      else if stdenv.isDarwin && stdenv.isAarch64 then
        "sha256-yjgZvb47NA/XG+u7UFpSk9gjzOIqmYa0qIChLRX9m/k="
      else
        "sha256-ypYnuv4cN4bT10NqtYtWx2lU8+Ggw8pRa1r63Q5lmDY=";
  };

  nativeBuildInputs = lib.optionals stdenv.isLinux [ autoPatchelfHook ];

  sourceRoot = ".";

  installPhase = ''
    runHook preInstall
    mkdir -p $out/bin
    cp zmx $out/bin/
    chmod +x $out/bin/zmx
    runHook postInstall
  '';

  meta = with lib; {
    description = "Session persistence for terminal processes";
    homepage = "https://zmx.sh";
    license = licenses.mit;
    platforms = platforms.unix;
  };
}
