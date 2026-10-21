#!/usr/bin/env bash
# Validation tests for the segmentation + Suricata IPS lab.
# Run ONLY inside your own isolated lab, from the attacker VM.
# Usage: ./test-attacks.sh <DMZ_WEB_IP> <SERVER_IP> <LAN_IP>
# Example: ./test-attacks.sh 10.0.40.10 10.0.20.10 10.0.10.50

set -u

DMZ="${1:?DMZ web server IP required}"
SRV="${2:?Servers VLAN IP required}"
LAN="${3:?LAN host IP required}"

need() { command -v "$1" >/dev/null 2>&1 || { echo "Missing tool: $1 (apt install $2)"; exit 1; }; }
need nmap nmap
need hping3 hping3
need curl curl
need hydra hydra

echo "=== 1. Inter-VLAN isolation (expect timeouts / filtered) ==="
for target in "$LAN" "$SRV"; do
  echo "-- ping $target"; ping -c 2 -W 2 "$target" || echo "BLOCKED (expected)"
  echo "-- ssh port check $target"; nmap -Pn -p 22 --max-retries 1 "$target" | grep -E "22/tcp"
done

echo
echo "=== 2. Port scan against DMZ (expect scan alert + source blocked) ==="
nmap -sS -T4 -p 1-1000 "$DMZ" >/dev/null 2>&1
echo "Scan sent. Check Suricata alerts for sid 9000020."

echo
echo "=== 3. SSH brute force against DMZ (expect block after ~5 attempts) ==="
printf 'admin\nroot\ntest\nuser\nguest\nbackup\noracle\nftp\n' > /tmp/users.txt
printf 'password\n123456\nadmin\nletmein\nqwerty\ntoor\nwelcome\n' > /tmp/pass.txt
hydra -L /tmp/users.txt -P /tmp/pass.txt -t 4 -f "ssh://$DMZ" 2>&1 | tail -5
echo "Check sid 9000001 and the pfSense Blocks tab."

echo
echo "=== 4. Web attack patterns (expect drops) ==="
curl -s -m 5 -o /dev/null -w "SQLi probe HTTP code: %{http_code}\n" "http://$DMZ/?id=1%20UNION%20SELECT%201,2,3" || echo "Connection dropped (expected)"
curl -s -m 5 -o /dev/null -w "Traversal probe HTTP code: %{http_code}\n" --path-as-is "http://$DMZ/../../etc/passwd" || echo "Connection dropped (expected)"

echo
echo "=== 5. SYN flood, short burst (expect sid 9000010 + drop) ==="
timeout 8 hping3 -S --flood -p 80 "$DMZ" >/dev/null 2>&1
echo "Flood stopped after 8 seconds."

echo
echo "=== Done. Review: Services > Suricata > Alerts / Blocks, and your SIEM dashboard. ==="
