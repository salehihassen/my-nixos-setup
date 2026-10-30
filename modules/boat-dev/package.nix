{
  lib,
  stdenvNoCC,
  fetchurl,
  makeWrapper,
  openssh,
  xdg-utils,
  versionCheckHook,
}:

stdenvNoCC.mkDerivation (finalAttrs: {
  pname = "boat-dev";
  version = "1.0.85";

  # This release is statically linked; no ELF patching or nix-ld is needed.
  src = fetchurl {
    url = "https://github.com/ariana-dot-dev/agent-server/releases/download/boat-cli-v${finalAttrs.version}/boat-linux-x64";
    hash = "sha256-XXkzojjc6gRGu77g4lBmkpYdFlN7mWAAPk7OnssexJg=";
  };

  dontUnpack = true;
  nativeBuildInputs = [ makeWrapper ];

  installPhase = ''
    runHook preInstall
    install -Dm755 "$src" "$out/bin/boat"
    # Nix owns upgrades. SSH and browser opening use these external programs.
    wrapProgram "$out/bin/boat" \
      --set BOAT_NO_UPDATE 1 \
      --prefix PATH : ${lib.makeBinPath [ openssh xdg-utils ]}
    runHook postInstall
  '';

  doInstallCheck = true;
  nativeInstallCheckInputs = [ versionCheckHook ];
  versionCheckProgramArg = "--version";

  meta = {
    description = "Boat.dev cloud sandbox CLI";
    homepage = "https://boat.dev";
    license = lib.licenses.mit;
    sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
    mainProgram = "boat";
    platforms = [ "x86_64-linux" ];
  };
})
