# Lab roadmap (each step is its own lab, built on the previous one)

| # | Lab | What it adds | Status |
|---|-----|--------------|--------|
| 1 | pfSense + VLANs + DMZ + Suricata IDS | Network base, firewall, reverse/forward proxy, IDS | built |
| 1b | Attack phase against lab 1 | Detection gaps in firewall, IDS, Nginx, Squid | in progress (2.1-2.3 done) |
| 2 | Active Directory (DC01 + CLIENT01/02 domain-joined) | Identity: Kerberos, GPO, LDAP. Then AD attacks: Kerberoasting, AS-REP roasting, pass-the-hash, BloodHound | planned |
| 3 | Wazuh SIEM (manager + indexer + dashboard) | Central logs from all VMs, agents on Linux and Windows, Suricata + pfSense logs ingested | planned |
| 4 | FIM (inside Wazuh) | File Integrity Monitoring on WEB01 (web root, /etc), DC01 (SYSVOL), tested with the web shell from attack 6.x | planned |
| 5 | EDR/XDR discussion + lab | Wazuh active response and Sysmon on Windows; compare with real EDR/XDR products (concepts: endpoint telemetry vs network vs identity correlation) | planned |
| 6 | DLP | Detect/block sensitive data leaving (payroll.txt on SRV01 as the bait): egress inspection, Wazuh rules, a small open-source DLP or proxy-based content rules | planned |

## Constraints
- Host has 15 GB RAM and little disk: run only the VMs a lab needs, snapshot before each lab.
- Wazuh all-in-one needs about 4 GB RAM and 20+ GB disk; a Windows Server DC about 2 GB.
- Each lab ends with a short write-up in Obsidian (Project/).
