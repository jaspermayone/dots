{
  lib,
  buildGoModule,
  fetchFromGitHub,
}:

buildGoModule rec {
  pname = "wut";
  version = "0.3.1";

  src = fetchFromGitHub {
    owner = "simonbs";
    repo = "wut";
    rev = "v${version}";
    hash = "sha256-/le6Vl26Wy7+kLXY4rqCW5/tDSOPJCDl/5L0O75j2Bs=";
  };

  vendorHash = null; # No vendor dependencies

  # Override to allow Go to download required toolchain
  preBuild = ''
    export GOTOOLCHAIN=auto
  '';

  ldflags = [
    "-s"
    "-w"
  ];

  meta = with lib; {
    description = "Workspace manager for Git worktrees";
    homepage = "https://github.com/simonbs/wut";
    license = licenses.mit;
    maintainers = [ ];
    mainProgram = "wut";
  };
}
