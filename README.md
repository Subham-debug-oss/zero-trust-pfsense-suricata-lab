# Zero-Trust Network Segmentation Lab: pfSense + Suricata IPS + WireGuard

A follow-up to the Snort/pfSense IDS/IPS project. Instead of one flat network behind a perimeter firewall, this lab splits the network into isolated VLANs, enforces default-deny between them, runs Suricata inline, and exposes administration only through a WireGuard VPN.

## Goals

1. Segment the network into VLANs (LAN, SERVERS, IOT, DMZ, MGMT) with default-deny inter-VLAN policy.
2. Run Suricata in inline (netmap) IPS mode with ET Open rules plus custom rules.
3. Replace open admin access with WireGuard (no SSH or WebGUI exposed on WAN).
4. Ship Suricata EVE JSON logs to a Wazuh/ELK stack and build alerts.
5. Prove it works with repeatable attack tests (`test-attacks.sh`).

## Architecture

```
                 Internet
                     |
               [ WAN / pfSense ]---- WireGuard (wg0) 10.99.0.0/24
                     |
            trunk (802.1Q tagged)
                     |
          [ Managed switch / vSwitch ]
   +--------+--------+--------+--------+
 VLAN10   VLAN20   VLAN30   VLAN40   VLAN99
  LAN     SERVERS   IOT      DMZ      MGMT
10.0.10/24 10.0.20/24 10.0.30/24 10.0.40/24 10.0.99/24
```

| VLAN | Name    | Subnet        | Purpose                      |
|------|---------|---------------|------------------------------|
| 10   | LAN     | 10.0.10.0/24  | Trusted user devices         |
| 20   | SERVERS | 10.0.20.0/24  | Internal services, SIEM      |
| 30   | IOT     | 10.0.30.0/24  | Untrusted devices, internet only |
| 40   | DMZ     | 10.0.40.0/24  | Public-facing test web server|
| 99   | MGMT    | 10.0.99.0/24  | Admin access, WireGuard only |

## Lab requirements

- Hypervisor (Proxmox, VirtualBox or VMware) with 16 GB RAM free
- pfSense CE 2.7+ VM (2 vCPU, 4 GB RAM, 3 NICs: WAN, trunk, spare)
- Ubuntu Server VM for the SIEM (Wazuh or ELK, 4 vCPU, 8 GB RAM)
- 2-3 small Linux VMs as VLAN clients (one acts as attacker, e.g. Kali)

## Step 1: Create VLANs on pfSense

1. **Interfaces > Assignments > VLANs > Add**: parent = trunk NIC, tags 10, 20, 30, 40, 99.
2. **Interfaces > Assignments**: add each VLAN, enable it, set static IPv4 (`.1` of each subnet).
3. **Services > DHCP Server**: enable per VLAN with a range such as `.100-.200`.
4. Hypervisor side: make the trunk port group carry all tags, and attach each client VM to a single VLAN.

## Step 2: Default-deny firewall policy

Rules are evaluated top to bottom, per interface, inbound direction.

| Interface | Rule | Action |
|-----------|------|--------|
| LAN | to SERVERS tcp 443,22 | Pass |
| LAN | to any (internet) | Pass |
| SERVERS | to LAN, IOT, MGMT | **Block** |
| SERVERS | to internet tcp 80,443,53 | Pass |
| IOT | to RFC1918 (private) alias | **Block** |
| IOT | to internet | Pass |
| DMZ | to any private alias | **Block** |
| DMZ | to internet tcp 80,443,53 | Pass |
| MGMT | from WireGuard only | Pass |
| WAN | everything except WireGuard UDP 51820 | Block (default) |

Tip: create an alias `RFC1918` = `10.0.0.0/8, 172.16.0.0/12, 192.168.0.0/16` and reuse it.

Verify with `nmap` from each VLAN to confirm blocked paths are really blocked.

## Step 3: Install Suricata in inline IPS mode

1. **System > Package Manager > Available Packages**: install `suricata`.
2. **Services > Suricata > Global Settings**: enable ET Open rules, set update interval to 12 hours, enable Rules Update.
3. **Services > Suricata > Interfaces > Add**: one instance per VLAN you want to inspect (start with WAN, DMZ, IOT).
   - Enable **Block Offenders** and set IPS Mode to **Inline Mode** (needs a NIC with netmap support; virtio and vmxnet3 work, Intel is safest).
   - Log format: enable **EVE JSON Log** with alerts, http, dns, tls, flow.
4. **Categories**: enable `emerging-scan`, `emerging-dos`, `emerging-exploit`, `emerging-malware`, `emerging-web_server`, `emerging-policy`.
5. **Rules > Custom**: paste the contents of `local.rules` from this folder.
6. Restart each Suricata interface and confirm it shows green.

Inline mode caveat: if a rule is set to `drop` but the interface is in legacy (pcap) mode, it only alerts. Check the interface mode first when drops don't happen.

## Step 4: WireGuard for management access

1. **VPN > WireGuard > Tunnels > Add**: listen port 51820, generate keys, address `10.99.0.1/24`.
2. Add a **Peer** per admin device with its public key and allowed IPs `10.99.0.2/32`.
3. **Interfaces > Assignments**: assign `tun_wg0`, enable it.
4. **Firewall > Rules > WAN**: pass UDP 51820 to WAN address.
5. **Firewall > Rules > WireGuard**: pass from `10.99.0.0/24` to MGMT and the pfSense WebGUI.
6. **System > Advanced > Admin Access**: bind the WebGUI and SSH to the MGMT interface only, so they cannot be reached from WAN.
7. Client side: use `wireguard-peer.conf` as a template.

## Step 5: Log forwarding and alerting

1. Install the Wazuh agent (or Filebeat) on the pfSense box or a log relay, pointed at `/var/log/suricata/*/eve.json`.
2. Alternatively, **Status > System Logs > Settings > Remote Logging**: send syslog to the SIEM at `10.0.20.10:514`.
3. In Wazuh/Kibana, build:
   - Alert count by `alert.signature` and by source VLAN
   - Top blocked source IPs
   - A rule that fires when one source triggers 5+ alerts in 2 minutes
4. Send a notification (email or Slack webhook) for severity 1 alerts.

## Step 6: Validate with attack tests

From the attacker VM in the IOT or DMZ VLAN, run `test-attacks.sh` against targets in other VLANs. Expected results:

| Test | Expected result |
|------|-----------------|
| Ping/SSH from IOT to LAN | Blocked by firewall (timeout) |
| nmap SYN scan of SERVERS | Blocked, scan alerts logged |
| SSH brute force against DMZ host | Blocked after threshold, source added to block list |
| SYN flood on DMZ web server | Rate rule fires, flood source dropped |
| SQLi-style request to DMZ web | Custom rule fires and drops |
| Access WebGUI from WAN | No response |
| Access WebGUI over WireGuard | Works |

Record screenshots of each result for your write-up.

## Deliverables checklist

- [ ] VLAN and firewall rule export (Diagnostics > Backup & Restore, config.xml with secrets removed)
- [ ] Network diagram
- [ ] Suricata custom rules with comments
- [ ] Screenshots of dashboard showing blocked attacks
- [ ] Short write-up: what worked, what broke, what you'd harden next

## Stretch goals

- Add a second Suricata sensor on a mirrored switch port for passive detection
- Automate pfSense config backups with Ansible
- Add Pi-hole or pfBlockerNG for DNS sinkholing on the IOT VLAN
- Map your detections to MITRE ATT&CK techniques (T1110, T1046, T1498)

## Authorization note

Run attack tests only against machines in your own lab.
