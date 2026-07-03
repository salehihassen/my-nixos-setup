{ config, pkgs, inputs, ... }: 

{
  services.ssh-agent.enable = true;

  programs.ssh = {
    enable = true;

    enableDefaultConfig = false;

    settings = {
      "*" = {
        ForwardAgent = false;
        AddKeysToAgent = "no";
        Compression = false;
        ServerAliveInterval = 0;
        ServerAliveCountMax = 3;
        HashKnownHosts = false;
        UserKnownHostsFile = "~/.ssh/known_hosts";
        ControlMaster = "no";
        ControlPath = "~/.ssh/master-%r@%n:%p";
        ControlPersist = "no";
	SetEnv = {
          TERM = "xterm-256color";
        };
      };

      "github.com" = {
        HostName = "github.com";
        User = "git";
        IdentityFile = "~/.ssh/id_ed25519";
        IdentitiesOnly = true;

        # Cache passphrase in ssh-agent for 4 hours.
        AddKeysToAgent = "4h";
      };
      "codeberg.org" = {
        HostName = "codeberg.org";
        User = "git";
        IdentityFile = "~/.ssh/id_ed25519";
        IdentitiesOnly = true;

        # Cache passphrase in ssh-agent for 4 hours.
        AddKeysToAgent = "4h";
      };
    };
  };
}
