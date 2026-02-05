{
  lib,
  buildGoModule,
  fetchFromGitHub,
}:

buildGoModule rec {
  pname = "wut";
  version = "0.1.3";

  src = fetchFromGitHub {
    owner = "simonbs";
    repo = "wut";
    rev = "v${version}";
    hash = "sha256-HQ/UmVVurP3N/dfXZO7j8d8PlZxceYTz5h0NKMcc2Gw=";
  };

  vendorHash = "sha256-lIRqcB0iEgzx+yLLy1i4T1s1w6AV4lTjW+b9sJKCr5s=";

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
