{
  lib,
  stdenv,
  fetchFromGitHub,
  installShellFiles,
  rustPlatform,
}:

rustPlatform.buildRustPackage (finalAttrs: {
  pname = "atuin";
  version = "18.13.3";

  src = fetchFromGitHub {
    owner = "atuinsh";
    repo = "atuin";
    tag = "v${finalAttrs.version}";
    hash = "sha256-hLt6CDHEPV8BVpOADVn4bLNcBz89eC2jKtIexHG0yAY=";
  };

  cargoHash = "sha256-VYwzMnfc/a4Sghmr5oMfhvoMkaWlY4w4e4Flu8MWQg0=";

  # 18.13.3 requires rustc 1.94.0 in Cargo.toml, but it builds fine on 1.93.x.
  # Lower the workspace rust-version so Cargo doesn't reject the toolchain.
  postPatch = ''
    sed -i 's/^rust-version = "[^"]*"/rust-version = "1.85.0"/' Cargo.toml
  '';

  buildFeatures = [
    "client"
    "sync"
    "clipboard"
    "daemon"
  ];

  nativeBuildInputs = [ installShellFiles ];

  postInstall = lib.optionalString (stdenv.buildPlatform.canExecute stdenv.hostPlatform) ''
    installShellCompletion --cmd atuin \
      --bash <($out/bin/atuin gen-completions -s bash) \
      --fish <($out/bin/atuin gen-completions -s fish) \
      --zsh <($out/bin/atuin gen-completions -s zsh)
  '';

  checkFlags = [
    "--skip=registration"
    "--skip=sync"
    "--skip=change_password"
    "--skip=multi_user_test"
  ];

  preCheck = ''
    export HOME=$(mktemp -d)
  '';

  meta = {
    description = "Replacement for a shell history which records additional commands context with optional encrypted synchronization between machines";
    homepage = "https://github.com/atuinsh/atuin";
    license = lib.licenses.mit;
    mainProgram = "atuin";
  };
})
