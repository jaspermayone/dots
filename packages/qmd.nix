{
  lib,
  buildNpmPackage,
  fetchFromGitHub,
  nodejs,
  python3,
  stdenv,
  darwin,
}:

buildNpmPackage rec {
  pname = "qmd";
  version = "unstable-2025-01-31";

  src = fetchFromGitHub {
    owner = "tobi";
    repo = "qmd";
    rev = "47b705409eb1427e574ce82c16e1860b216869ed";
    hash = lib.fakeHash;
  };

  npmDepsHash = "sha256-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA="; # Placeholder - needs to be updated

  nativeBuildInputs = [
    nodejs
    python3
  ] ++ lib.optionals stdenv.hostPlatform.isDarwin [
    darwin.cctools
  ];

  buildInputs = lib.optionals stdenv.hostPlatform.isDarwin (
    with darwin.apple_sdk.frameworks; [
      Security
    ]
  );

  # Skip npm install scripts that might fail
  npmInstallFlags = [ "--ignore-scripts" ];

  # QMD requires Bun runtime but can be built with npm
  postInstall = ''
    # Ensure binary is executable
    chmod +x $out/bin/qmd
  '';

  meta = with lib; {
    description = "On-device search engine for markdown notes and knowledge bases";
    homepage = "https://github.com/tobi/qmd";
    license = licenses.mit;
    maintainers = [ ];
    mainProgram = "qmd";
    platforms = platforms.unix;
  };
}
