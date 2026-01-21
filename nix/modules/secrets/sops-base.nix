{ lib, ... }:

{
  sops = {
    defaultSopsFormat = lib.mkDefault "yaml";

    age.sshKeyPaths = lib.mkDefault [ "/etc/ssh/ssh_host_ed25519_key" ];
  };
}
