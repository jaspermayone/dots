{
  lib,
  buildNpmPackage,
  fetchFromGitHub,
  bun,
  makeWrapper,
  sqlite,
}:

buildNpmPackage {
  pname = "qmd";
  version = "unstable-2025-02-01";

  src = fetchFromGitHub {
    owner = "tobi";
    repo = "qmd";
    rev = "47b705409eb1427e574ce82c16e1860b216869ed";
    hash = "sha256-mJxqZfTGjwHrZy0fxl3HA31Yg7YyIi876cXehmi0tIA=";
  };

  npmDepsHash = "sha256-bfLuM2wiWW4XCqeJl6mAsTDHhPPdX6V/G56nDZXqEz8=";

  # qmd uses bun.lock, not package-lock.json; provide a pre-generated one
  postPatch = ''
    cp ${./qmd-package-lock.json} package-lock.json
  '';

  # Skip native addon install scripts (node-llama-cpp downloads prebuilt llama.cpp
  # binaries at install time). Core full-text search works without it; only the
  # optional vector embedding features are affected.
  npmInstallFlags = [ "--ignore-scripts" ];

  nativeBuildInputs = [ bun makeWrapper ];
  buildInputs = [ sqlite ];

  dontNpmBuild = true;

  installPhase = ''
    runHook preInstall

    mkdir -p $out/lib/qmd $out/bin
    cp -r src $out/lib/qmd/
    cp package.json $out/lib/qmd/
    cp -r node_modules $out/lib/qmd/

    makeWrapper ${bun}/bin/bun $out/bin/qmd \
      --add-flags "$out/lib/qmd/src/qmd.ts" \
      --set LD_LIBRARY_PATH "${sqlite.out}/lib" \
      --set DYLD_LIBRARY_PATH "${sqlite.out}/lib"

    runHook postInstall
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
