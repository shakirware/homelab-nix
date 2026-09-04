{ config, lib, pkgs, ... }:

let
  tz = "Europe/London";
  bindIp = "0.0.0.0";

  vpnNet = "vpn-net";

  podmanBin = "${pkgs.podman}/bin/podman";
  curlBin = "${pkgs.curl}/bin/curl";

  vpnCheck = pkgs.writeShellScript "gluetun-vpn-check" ''
    set -euo pipefail

    # Gluetun itself must consider the VPN healthy.
    ${podmanBin} exec gluetun \
      /gluetun-entrypoint healthcheck >/dev/null

    # Compare the VPN exit IP with vm-media's normal WAN IP.
    vpn_ip="$(${podmanBin} exec gluetun cat /tmp/gluetun/ip)"
    host_ip="$(${curlBin} -4fsS --max-time 10 https://api.ipify.org)"

    if [ -z "$vpn_ip" ] || [ -z "$host_ip" ]; then
      echo "gluetun: could not determine public IPs" >&2
      exit 1
    fi

    if [ "$vpn_ip" = "$host_ip" ]; then
      echo "gluetun: VPN public IP matches host WAN IP ($vpn_ip)" >&2
      exit 1
    fi

    echo "gluetun: healthy; VPN IP $vpn_ip differs from host IP $host_ip"
  '';
in {
  sops.secrets."gluetun/wireguard_config" = { };

  sops.templates."gluetun-wg0.conf" = {
    content = config.sops.placeholder."gluetun/wireguard_config";
    owner = "root";
    group = "root";
    mode = "0400";
    restartUnits = [ "podman-gluetun.service" ];
  };

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
    image = "qmcgaw/gluetun:v3.41.3@sha256:fa19cc76b2af13d57a8d3dc3066f2ada061b1c761b8aecf989b3877c0486e027";
    autoStart = true;

    extraOptions =
      [ "--network=${vpnNet}" "--cap-add=NET_ADMIN" "--device=/dev/net/tun" ];

    ports = [
      "${bindIp}:8191:8191" # flaresolverr
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

      FIREWALL_INPUT_PORTS = "8080,9696,6881,8901,8191";
    };

    volumes = [
      "/srv/appdata/gluetun:/gluetun"
      "${config.sops.templates."gluetun-wg0.conf".path}:/gluetun/wireguard/wg0.conf:ro"
    ];
  };

  systemd.services.podman-gluetun = {
    after = [ "podman-network-${vpnNet}.service" "podman.service" ];
    requires = [ "podman-network-${vpnNet}.service" "podman.service" ];
  };

  # These containers share Gluetun's network namespace.  PartOf ensures a
  # credential-driven Gluetun restart recreates every namespace consumer too.
  systemd.services.podman-flaresolverr.partOf = [ "podman-gluetun.service" ];
  systemd.services.podman-prowlarr.partOf = [ "podman-gluetun.service" ];
  systemd.services.podman-qbittorrent.partOf = [ "podman-gluetun.service" ];
  systemd.services.podman-tuliprox.partOf = [ "podman-gluetun.service" ];

  systemd.services.gluetun-vpn-check = {
    description = "Verify Gluetun VPN connectivity and public IP";

    after = [
      "podman-gluetun.service"
      "network-online.target"
    ];

    requires = [
      "podman-gluetun.service"
    ];

    wants = [
      "network-online.target"
    ];

    serviceConfig = {
      Type = "oneshot";
      ExecStart = vpnCheck;
      TimeoutStartSec = "30s";
    };
  };

  systemd.timers.gluetun-vpn-check = {
    description = "Periodically verify Gluetun VPN connectivity";
    wantedBy = [ "timers.target" ];

    timerConfig = {
      OnBootSec = "2m";
      OnUnitActiveSec = "1m";
      Unit = "gluetun-vpn-check.service";
    };
  };

  networking.firewall.allowedTCPPorts =
    lib.mkAfter [ 8080 9696 6881 8901 8191 ];
  networking.firewall.allowedUDPPorts = lib.mkAfter [ 6881 ];
}
