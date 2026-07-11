{
  writeShellApplication,
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
  parted,
  rsync,
  util-linux,
}:

writeShellApplication {
  name = "nixos-recovery-install";

  runtimeInputs = [
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
    parted
    rsync
    util-linux
  ];

  text = builtins.readFile ./nixos-recovery-install.sh;
}
