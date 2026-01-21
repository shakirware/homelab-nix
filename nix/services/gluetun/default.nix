{ config, lib, pkgs, ... }:

let
  tz = "Europe/London";
  bindIp = "0.0.0.0";

  vpnNet = "vpn-net";
in {
  environment.systemPackages = with pkgs; [ podman ];

  systemd.services."podman-network-${vpnNet}" = {
    description = "Ensure podman network ${vpnNet} exists";
    wantedBy = [ "multi-user.target" ];
    after = [ "podman.service" ];
    requires = [ "podman.service" ];

    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStart = ''
        ${pkgs.bash}/bin/bash -lc "${pkgs.podman}/bin/podman network inspect ${vpnNet} >/dev/null 2>&1 || ${pkgs.podman}/bin/podman network create --subnet 10.99.0.0/24 --gateway 10.99.0.1 ${vpnNet}"
      '';
    };
  };

  virtualisation.oci-containers.containers.gluetun = {
    image = "qmcgaw/gluetun:v3.41.0";
    autoStart = true;

    extraOptions =
      [ "--network=${vpnNet}" "--cap-add=NET_ADMIN" "--device=/dev/net/tun" ];

    ports = [
      "${bindIp}:8080:8080" # qbittorrent webui
      "${bindIp}:9696:9696" # prowlarr
      "${bindIp}:6881:6881" # torrent TCP
      "${bindIp}:6881:6881/udp" # torrent UDP
      "${bindIp}:8901:8901" # iptv proxy
    ];

    environment = {
      TZ = tz;

      VPN_SERVICE_PROVIDER = "mullvad";
      VPN_TYPE = "wireguard";

      IPV6 = "off";

      FIREWALL_OUTBOUND_SUBNETS = "192.168.0.0/16";

      FIREWALL_INPUT_PORTS = "8080,9696,6881,8901";
    };

    volumes = [ "/srv/appdata/gluetun:/gluetun" ];
  };

  systemd.services.podman-gluetun = {
    after = [ "podman-network-${vpnNet}.service" "podman.service" ];
    requires = [ "podman-network-${vpnNet}.service" "podman.service" ];
  };

  networking.firewall.allowedTCPPorts = lib.mkAfter [ 8080 9696 6881 8901 ];
  networking.firewall.allowedUDPPorts = lib.mkAfter [ 6881 ];
}
