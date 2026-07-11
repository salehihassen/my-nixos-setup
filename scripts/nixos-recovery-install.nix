{
  writeShellApplication,
  symlinkJoin,
  bash,
  btrfs-progs,
  coreutils,
  cryptsetup,
  dosfstools,
  e2fsprogs,
  gawk,
  gnugrep,
  gnused,
  gptfdisk,
  nixos-install-tools,
  parted,
  rsync,
  util-linux,
}:

let
  commonRuntimeInputs = [
    bash
    btrfs-progs
    coreutils
    cryptsetup
    dosfstools
    e2fsprogs
    gawk
    gnugrep
    gnused
    gptfdisk
    nixos-install-tools
    parted
    rsync
    util-linux
  ];

  singleBoot = writeShellApplication {
    name = "nixos-recovery-single-boot-destructive";
    runtimeInputs = commonRuntimeInputs;
    text = builtins.readFile ./nixos-recovery-single-boot-destructive.sh;
  };

  multiboot = writeShellApplication {
    name = "nixos-recovery-multiboot";
    runtimeInputs = commonRuntimeInputs;
    text = builtins.readFile ./nixos-recovery-multiboot.sh;
  };

  install = writeShellApplication {
    name = "nixos-recovery-install";
    runtimeInputs = commonRuntimeInputs ++ [
      singleBoot
      multiboot
    ];
    text = builtins.readFile ./nixos-recovery-install.sh;
  };
in

symlinkJoin {
  name = "nixos-recovery-tools";
  paths = [
    install
    singleBoot
    multiboot
  ];
}
