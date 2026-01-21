{ lib, config, ... }:

let ids = config.homelab.ids;
in {
  users.groups.media.gid = lib.mkDefault ids.mediaGid;

  users.users.${ids.user} = {
    isNormalUser = true;
    uid = lib.mkDefault ids.uid;

    extraGroups = [ "wheel" "media" ];

    openssh.authorizedKeys.keys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIMgak38Af+nKukrQHPyqtqrl6VI/vEhivai6+0KrASTV shakir@homelab"
    ];
  };
}
