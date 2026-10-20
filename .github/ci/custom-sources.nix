# Fetch inputs of the packages we override or obtain outside the main Nixpkgs
# package set. Keep this list in sync when adding another custom package.
let
  flake = builtins.getFlake (toString ../..);
  host = flake.nixosConfigurations.j2;
  config = host.config;
  home = config.home-manager.users.saleh;
  t3code = home.services.t3code.package;
  lock = builtins.fromJSON (builtins.readFile ../../flake.lock);

  download = label: src: {
    inherit label;
    inherit (src) name;
    url = src.url;
    hash = src.outputHash;
    unpack = src.outputHashMode == "recursive";
  };
  flakeSource =
    input:
    let
      pinned = lock.nodes.${lock.nodes.root.inputs.${input}}.locked;
    in
    assert pinned.type == "github";
    {
      label = input;
      name = "source";
      url = "https://github.com/${pinned.owner}/${pinned.repo}/archive/${pinned.rev}.tar.gz";
      hash = pinned.narHash;
      unpack = true;
    };
  bundle =
    label: drv:
    let
      # Disable substitution for this fetcher, while permitting its build tools
      # to come from public caches. An existing local output is rebuilt below.
      fresh = drv.overrideAttrs { allowSubstitutes = false; };
    in
    assert (drv.outputHash or "") != "";
    {
      inherit label;
      inherit (fresh) drvPath;
      outputPath = fresh.outPath;
    };
in
{
  downloads =
    map flakeSource [
      "compose2nix"
      "displaylinkSrc"
      "noctalia"
      "t3-code-nix"
      "zen-browser"
    ]
    ++ [
      (download "niri" config.programs.niri.package.src)
      (download "t3code" t3code.sourceUnwrapped.src)
      (download "zen-browser-release" home.programs.zen-browser.package.unwrapped.src)
      {
        label = "displaylink-archive";
        inherit (host.pkgs.displaylink.src) name;
        hash = host.pkgs.displaylink.src.outputHash;
        url = "https://www.synaptics.com/sites/default/files/exe_files/2026-06/DisplayLink%20USB%20Graphics%20Software%20for%20Ubuntu6.3-EXE.zip";
        unpack = false;
      }
    ];

  bundles = [
    (bundle "caddy-plugins" config.services.caddy.package.src)
    (bundle "compose2nix-go-modules" flake.inputs.compose2nix.packages.x86_64-linux.default.goModules)
    (bundle "niri-cargo-vendor" config.programs.niri.package.cargoDeps.vendorStaging)
    (bundle "t3code-pnpm-deps" t3code.sourceUnwrapped.pnpmDeps)
    (bundle "t3code-monitor-cargo-vendor" t3code.resourceMonitor.cargoDeps.vendorStaging)
  ];
}
