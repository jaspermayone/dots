{
  lib,
  stdenvNoCC,
  fetchFromGitHub,
  bun,
  makeWrapper,
}:

stdenvNoCC.mkDerivation rec {
  pname = "qmd";
  version = "unstable-2025-02-01";

  src = fetchFromGitHub {
    owner = "tobi";
    repo = "qmd";
    rev = "47b705409eb1427e574ce82c16e1860b216869ed";
    hash = "sha256-mJxqZfTGjwHrZy0fxl3HA31Yg7YyIi876cXehmi0tIA=";
  };

  nativeBuildInputs = [
    bun
    makeWrapper
  ];

  buildPhase = ''
    runHook preBuild
    HOME=$TMPDIR bun install --frozen-lockfile --no-progress
    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall

    mkdir -p $out/lib/qmd $out/bin
    cp -r . $out/lib/qmd/

    # Use the existing qmd wrapper script, but ensure it finds our bun
    makeWrapper $out/lib/qmd/qmd $out/bin/qmd \
      --prefix PATH : ${lib.makeBinPath [ bun ]}

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
