{ config, pkgs, inputs, ... }: 

{
  services.ssh-agent.enable = true;
  
  programs.ssh = {
    enable = true;
  
    enableDefaultConfig = false;
  
    matchBlocks = {
      "*" = {
        forwardAgent = false;
        addKeysToAgent = "no";
        compression = false;
        serverAliveInterval = 0;
        serverAliveCountMax = 3;
        hashKnownHosts = false;
        userKnownHostsFile = "~/.ssh/known_hosts";
        controlMaster = "no";
        controlPath = "~/.ssh/master-%r@%n:%p";
        controlPersist = "no";
      };

      "github.com" = {
        hostname = "github.com";
        user = "git";
        identityFile = "~/.ssh/id_ed25519";
        identitiesOnly = true;
  
        # Cache passphrase in ssh-agent for 4 hours.
        addKeysToAgent = "4h";
      };
      "codeberg.org" = {
        hostname = "codeberg.org";
        user = "git";
        identityFile = "~/.ssh/id_ed25519";
        identitiesOnly = true;
  
        # Cache passphrase in ssh-agent for 4 hours.
        addKeysToAgent = "4h";
      };
    };
  };
}

