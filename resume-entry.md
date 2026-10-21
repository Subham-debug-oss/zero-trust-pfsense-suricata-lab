**Zero-Trust Network Segmentation with Suricata IPS and WireGuard**
*Month Year – Month Year* | Network Security Engineer | pfSense, Suricata, WireGuard, VLANs, Wazuh

- Redesigned a flat lab network into five 802.1Q VLANs (LAN, Servers, IoT, DMZ, Management) on pfSense with default-deny inter-VLAN policy, preventing lateral movement from untrusted segments.
- Deployed Suricata in inline IPS mode with ET Open and custom rules, blocking port scans, SSH brute force, SYN/ICMP/UDP floods and web attack patterns (SQLi, path traversal) in repeatable attack tests.
- Replaced exposed admin services with a WireGuard VPN, restricting WebGUI and SSH to the management VLAN and leaving UDP 51820 as the only open WAN port.
- Forwarded Suricata EVE JSON logs to a Wazuh/ELK stack, built dashboards by signature and VLAN, and configured threshold alerts for severity 1 events.

*Optional metric line (fill in with your real numbers):* Validated controls with N scripted attack scenarios, with X% blocked or alerted within Y seconds.
