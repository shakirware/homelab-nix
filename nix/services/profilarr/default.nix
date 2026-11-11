{ ... }:

{
  homelab.backup = {
    paths = [ "/srv/appdata/profilarr" ];
    exclude = [
      "/srv/appdata/profilarr/backups"
      "/srv/appdata/profilarr/log"
    ];
  };
}
