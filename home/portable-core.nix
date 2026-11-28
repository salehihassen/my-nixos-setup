{
  config,
  lib,
  pkgs,
  username ? "saleh",
  dotfilesRoot ? "/etc/nixos",
  ...
}:

# Lightweight shell, editor, and debugging tools for every machine, including
# servers. Heavier development tooling lives in portable-dev.nix.
let
  # Same exclusions as dotfiles/bash/.stow-local-ignore and stow-dotfiles.sh.
  ignoredFiles = [
    ".stow-local-ignore"
    ".bash_secrets"
    "bash_secrets"
    "network-diagnostics.sh"
    "list-secret-names.sh"
  ];
  source = config.dotfiles.source;
  packageFiles =
    package:
    let
      dir = "${source}/dotfiles/${package}";
    in
    map (file: builtins.unsafeDiscardStringContext (lib.removePrefix "${dir}/" (toString file))) (
      lib.filter (file: !(lib.elem (baseNameOf file) ignoredFiles)) (lib.filesystem.listFilesRecursive dir)
    );
  linkedDotfiles = lib.listToAttrs (
    lib.concatMap (
      package:
      map (relative: lib.nameValuePair relative { source = "${source}/dotfiles/${package}/${relative}"; }) (
        packageFiles package
      )
    ) config.dotfiles.stowPackages
  );
in
{
  imports = [
    ./ssh.nix
    ./tmux.nix
  ];

  options.dotfiles.stowPackages = lib.mkOption {
    type = lib.types.listOf lib.types.str;
    description = "Editable dotfile packages selected for Stow by the imported home modules.";
  };

  options.dotfiles.source = lib.mkOption {
    type = lib.types.nullOr lib.types.path;
    default = null;
    example = lib.literalExpression "inputs.my-nixos-setup";
    description = ''
      Read-only copy of this repository, such as a pinned flake input. When
      set, Home Manager links the selected packages' files from it instead of
      running Stow on the editable checkout at dotfilesRoot. Home Manager then
      refuses to replace an existing file it doesn't manage.
    '';
  };

  config = {
    dotfiles.stowPackages = [
      "bash"
      "git"
      "neovim"
    ];

    assertions = [
      {
        assertion = lib.hasPrefix "/" dotfilesRoot && dotfilesRoot != "/";
        message = "dotfilesRoot must be an absolute path to the editable configuration checkout";
      }
    ];

    home.username = username;
    home.homeDirectory = lib.mkDefault "/home/${username}";
    home.stateVersion = "25.11";

    programs.home-manager.enable = true;
    programs.direnv.enable = true;

    home.file = lib.mkIf (source != null) linkedDotfiles;

    # Home Manager owns packages and generated integration files. Stow runs
    # afterwards and owns the editable preferences in the declared checkout.
    home.activation.stowDotfiles = lib.mkIf (source == null) (lib.hm.dag.entryAfter [ "linkGeneration" ] ''
      export DOTFILES_STOW_PACKAGES=${lib.escapeShellArg (lib.concatStringsSep " " config.dotfiles.stowPackages)}
      export HOME=${lib.escapeShellArg config.home.homeDirectory}
      export PATH=${
        lib.makeBinPath [
          pkgs.coreutils
          pkgs.stow
        ]
      }:$PATH
      ${pkgs.bash}/bin/bash ${lib.escapeShellArg "${dotfilesRoot}/scripts/stow-dotfiles.sh"}
    '');

    home.sessionVariables = {
      DOTFILES_ROOT = if source == null then dotfilesRoot else "${source}";
      DOTFILES_STOW_PACKAGES = lib.concatStringsSep " " config.dotfiles.stowPackages;
    };

    home.packages = with pkgs; [
      stow
      bash-completion
      tree
      htop
      ripgrep
      fd
      jq
      unzip
      git
      curl
      bind
      openssl
      wakeonlan
    ];

    programs.neovim = {
      enable = true;
      withRuby = false;
      withPython3 = false;

      plugins = [
        pkgs.vimPlugins.nvim-lspconfig
        (pkgs.vimPlugins.nvim-treesitter.withPlugins (
          p: with p; [
            bash
            javascript
            json
            lua
            markdown
            markdown_inline
            nix
            tsx
            typescript
            vim
            vimdoc
          ]
        ))
      ];

      # Stow supplies init.lua and init.vim, so Home Manager must not create
      # $XDG_CONFIG_HOME/nvim/init.lua.
      sideloadInitLua = true;
      extraWrapperArgs = [
        "--add-flags"
        "-u ${config.xdg.configHome}/nvim/init.lua"
      ];
    };
  };
}
