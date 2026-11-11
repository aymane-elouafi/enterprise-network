#!/bin/bash
# IDS01 step 1: install and configure Suricata 8 (IDS mode, AF_PACKET on dmzfw0 and tap0).
# Run as root on IDS01 while its NIC is still on NAT:  sudo bash ids01-install.sh
# It does NOT start Suricata and does NOT touch the network; see ids01-net.sh for that.
set -e

hostnamectl set-hostname ids01
grep -q 'ids01' /etc/hosts || sed -i 's/^127\.0\.1\.1.*/127.0.1.1 ids01.lab.internal ids01/' /etc/hosts

apt update
# a previous experiment may have left Suricata behind
apt purge -y 'suricata*' || true
apt install -y software-properties-common open-vm-tools ufw
add-apt-repository -y ppa:oisf/suricata-stable
apt update
apt install -y suricata jq ethtool
suricata -V
suricata-update              # downloads ET Open into /var/lib/suricata/rules/suricata.rules
systemctl stop suricata || true
# the service runs as user suricata and needs /run/suricata for its control socket (suricatasc)
echo 'd /run/suricata 0755 suricata suricata -' > /etc/tmpfiles.d/suricata.conf

# --- custom rules (SIDs 1000000-1999999 are reserved for local rules) ---
mkdir -p /etc/suricata/rules
cat > /etc/suricata/rules/local.rules <<'EOF'
# 1) "Hello world": any ping to an internal host
alert icmp any any -> $HOME_NET any (msg:"LAB ICMP echo request to internal host"; itype:8; classtype:misc-activity; sid:1000001; rev:1;)

# 2) Internal recon: many SYNs from CLIENTS to SERVERS in a short time
alert tcp 10.10.10.0/24 any -> 10.10.20.0/24 any (msg:"LAB Possible port scan CLIENTS to SERVERS"; flags:S,12; threshold:type threshold, track by_src, count 20, seconds 10; classtype:attempted-recon; sid:1000002; rev:1;)

# 3) Data leak: /etc/passwd content leaving a web server
alert http $HOME_NET any -> any any (msg:"LAB /etc/passwd content in HTTP response"; flow:established,to_client; http.response_body; content:"root:x:0:0:"; classtype:successful-recon-limited; sid:1000003; rev:1;)

# 4) Brute force on the DVWA brute-force page
alert http any any -> $HOME_NET any (msg:"LAB Brute force against DVWA login form"; flow:established,to_server; http.uri; content:"/vulnerabilities/brute/"; content:"password="; threshold:type threshold, track by_src, count 15, seconds 20; classtype:attempted-user; sid:1000004; rev:1;)

# 5) OS command injection attempt in DVWA (separators ; | & raw or URL-encoded)
alert http any any -> $HOME_NET any (msg:"LAB Command injection attempt DVWA exec"; flow:established,to_server; http.uri; content:"/vulnerabilities/exec/"; http.request_body; pcre:"/ip=[^&]*(%3B|%7C|%26|\x3B|\x7C)/i"; classtype:web-application-attack; sid:1000005; rev:1;)

# 6) Pivot attempt: a DMZ host opening connections into internal networks (DB pinhole excluded)
alert tcp 10.10.50.0/24 any -> [10.10.10.0/24,10.10.20.0/24,10.10.99.0/24] !3306 (msg:"LAB DMZ host attempting connection into internal network"; flags:S,12; classtype:policy-violation; sid:1000006; rev:1;)
EOF

# --- patch suricata.yaml ---
[ -f /etc/suricata/suricata.yaml.orig ] || cp /etc/suricata/suricata.yaml /etc/suricata/suricata.yaml.orig
python3 - <<'PY'
import re, sys
p = '/etc/suricata/suricata.yaml'
s = open(p).read()

def sub(pattern, repl, what, flags=0):
    global s
    s, n = re.subn(pattern, repl, s, count=1, flags=flags)
    if n != 1:
        sys.exit("could not patch: " + what)

for name, val in [("HOME_NET", "[10.10.0.0/16]"),
                  ("HTTP_SERVERS", "[10.10.50.10,10.10.50.20]"),
                  ("SQL_SERVERS", "[10.10.20.10]"),
                  ("DNS_SERVERS", "[10.10.10.1,10.10.20.1,10.10.50.1,10.10.99.1]")]:
    sub(r'(?m)^(\s*%s:).*$' % name, lambda m, v=val: '%s "%s"' % (m.group(1), v), name)

def nic(name, cid):
    return ("  - interface: %s\n    threads: 1\n    cluster-id: %d\n    cluster-type: cluster_flow\n"
            "    defrag: yes\n    use-mmap: yes\n    tpacket-v3: yes\n") % (name, cid)

sub(r'(?ms)^af-packet:\n.*?(?=^  - interface: default)',
    lambda m: "af-packet:\n" + nic("dmzfw0", 99) + nic("tap0", 98), "af-packet")
sub(r'(?m)^(\s*)community-id:\s*false', r'\1community-id: true', "community-id")
if 'local.rules' not in s:
    if '\n  - suricata.rules\n' not in s:
        sys.exit("could not patch: rule-files")
    s = s.replace('\n  - suricata.rules\n', '\n  - suricata.rules\n  - /etc/suricata/rules/local.rules\n', 1)
open(p, 'w').write(s)
print("suricata.yaml patched")
PY

suricata -T -c /etc/suricata/suricata.yaml -v || echo "(-T may complain about dmzfw0/tap0 until the NICs exist; re-run it after ids01-net.sh)"

# --- host firewall (enabled manually at the end, once the management NIC is on VLAN 99) ---
ufw default deny incoming
ufw default allow outgoing
ufw allow from 10.10.99.0/24 to any port 22 proto tcp comment 'SSH from MGMT only'

echo
echo "Done. Next: shut down, set the 4 adapters in VMware, boot, run ids01-net.sh on the console."
