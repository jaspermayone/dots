{
  lib,
  buildGoModule,
  fetchFromGitHub,
}:

buildGoModule rec {
  pname = "wut";
  version = "0.1.2";

  src = fetchFromGitHub {
    owner = "simonbs";
    repo = "wut";
    rev = "v${version}";
    hash = "sha256-PEUHjiLA9d0xOoOepIlpCoDhIdLvYhC1WId878pLd6Q=";
  };

  vendorHash = "sha256-lIRqcB0iEgzx+yLLy1i4T1s1w6AV4lTjW+b9sJKCr5s="; # Placeholder - will be updated by build

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
