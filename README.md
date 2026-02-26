# Homelab

A personal homelab built on Proxmox, with Terraform provisioning VMs and NixOS managing host and service configuration. The lab is defined from a single flake, deployed with Colmena and uses sops-nix for secret management. This is an opinionated, reproducible setup for my own infrastructure: networking, storage, media, private apps and monitoring, all managed declaratively.

<img width="1870" height="1000" alt="image" src="https://github.com/user-attachments/assets/9337fde9-1ec5-41dc-bf60-bbc9d3b7c8af" />

## Overview

This repository manages two layers of the homelab:

* **Infrastructure layer**: Proxmox VM provisioning via Terraform
* **System layer**: NixOS hosts, modules, profiles and services via flakes

## Architecture

The lab is split into a few role-specific VMs:

* **vm-gw** - DNS, reverse proxy, homepage, Tailscale
* **vm-media** - media stack and download automation
* **vm-storage** - storage with mergerfs and NFS
* **vm-apps** - smaller self-hosted applications
* **vm-sensitive** - more private applications
* **vm-monitoring** - Prometheus, Grafana, Loki, Alertmanager, exporters

## Hardware

The homelab runs on a single Proxmox host built mostly from second hand parts rather than dedicated server hardware. The goal is to keep it inexpensive, reasonably quiet and capable.

The server idles at around 32W. Deeper C-states are currently limited by the NIC, so idle power would likely be lower with a different NIC.

Current host:

* **CPU:** Intel i3-8100
* **Memory:** 32GB DDR4
* **Motherboard:** ASUS PRIME H370-A
* **Boot / VM storage:** 512GB NVMe SSD
* **Bulk storage:** 2x 16TB Seagate IronWolf Pro HDDs
* **Case / PSU:** Fractal Design Define R5 + Seasonic Focus GX-750
* **Router:** MikroTik hAP ax2

The Intel iGPU is passed through to the media VM for hardware transcoding.

## Networking

The lab uses static IPs for its main hosts and a single internal domain for service discovery.

* AdGuard provides local DNS resolution for service names
* Caddy handles TLS and reverse proxies internal services
* Services are exposed through the gateway VM
* Tailscale provides remote access without opening up the wider network

## Monitoring

The monitoring VM collects host metrics, logs and Proxmox metrics then exposes dashboards and alerting.

Coverage includes:

* Node-level health across all VMs
* Proxmox node and storage visibility
* Telegram alerts via Alertmanager
* Centralised logs with Loki and Promtail

<img width="1574" height="808" alt="image" src="https://github.com/user-attachments/assets/00af45b1-e66b-4feb-b4e1-5a5ea9210a95" />


## Planned next steps

* Segment the network with VLANs so the homelab, IoT devices and general home devices are separated
* Add more disks and move bulk storage to mirrored storage before putting important data on it
* Start using Immich for photo backup once storage redundancy is in place
* Deploy Vaultwarden for self-hosted password management
* Add Paperless-ngx for document scanning and archiving
* Try copyparty for general file storage and sharing

