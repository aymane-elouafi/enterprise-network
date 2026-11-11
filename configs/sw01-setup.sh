#!/bin/sh
# Run on SW01 as root: installs the VLAN-aware bridge script and its systemd unit.
# Ports (renamed by the .link files): trunk0, vlan10, vlan20, vlan99
set -e

cat > /usr/local/sbin/sw01-vlans.sh <<'EOF'
#!/bin/sh
# SW01: VLAN-aware Linux bridge acting as an 802.1Q access switch
#   trunk0 : tagged 10,20,99  (LAB-TRUNK, to pfSense em1)
#   vlan10 : access VLAN 10   (LAB-VLAN10)
#   vlan20 : access VLAN 20   (LAB-VLAN20)
#   vlan99 : access VLAN 99   (LAB-VLAN99)
set -e
# wait until udev has renamed all ports (max ~30 s)
for i in trunk0 vlan10 vlan20 vlan99; do
  n=0; until ip link show "$i" >/dev/null 2>&1; do n=$((n+1)); [ $n -gt 30 ] && exit 1; sleep 1; done
done
# bridge with VLAN filtering; vlan_default_pvid 0 = ports get NO VLAN by default
ip link add name br0 type bridge vlan_filtering 1 vlan_default_pvid 0 stp_state 0
ip link set br0 up
for p in trunk0 vlan10 vlan20 vlan99; do
  ip link set "$p" master br0
  ip link set "$p" up
done
# trunk: tagged members of 10, 20, 99
for v in 10 20 99; do bridge vlan add dev trunk0 vid "$v"; done
# access ports: untagged member + PVID (tag added on ingress, removed on egress)
bridge vlan add dev vlan10 vid 10 pvid untagged
bridge vlan add dev vlan20 vid 20 pvid untagged
bridge vlan add dev vlan99 vid 99 pvid untagged
EOF

cat > /etc/systemd/system/sw01-vlans.service <<'EOF'
[Unit]
Description=SW01 VLAN-aware bridge (802.1Q access switch)
After=systemd-udevd.service network-pre.target
Wants=network-pre.target

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/usr/local/sbin/sw01-vlans.sh
ExecStop=/sbin/ip link del br0

[Install]
WantedBy=multi-user.target
EOF

chmod +x /usr/local/sbin/sw01-vlans.sh
systemctl daemon-reload
systemctl enable --now sw01-vlans.service
bridge vlan show
