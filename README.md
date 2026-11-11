# Enterprise network lab

A virtualized enterprise network built in VMware, documented step by step: pfSense firewall with VLANs and a DMZ, a VLAN-aware Debian switch, Nginx reverse proxy, Squid proxy, Apache/DVWA and Samba servers, a Suricata IDS, then attack simulations to test detection at each layer.

- [Part 1: main installation](part-1-main-installation/Part%201%20-%20Building%20a%20Segmented%20Enterprise%20Lab.md)
- [Part 2: attack phase](part-2-attack-phase/screenshots) (in progress)
- [Roadmap](ROADMAP.md)
- `configs/`: setup scripts for each VM. `diagrams/`: architecture diagram.

Lab only: all addresses are private and the vulnerable apps (DVWA) are deliberately insecure.
