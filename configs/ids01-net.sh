#!/bin/bash
# IDS01 step 2: write the netplan file for the 4 NICs (mgmt0, dmzfw0, dmzsrv0, tap0).
# Run as root on the IDS01 CONSOLE after the 4 adapters are set in VMware:
#   sudo bash ids01-net.sh MAC_MGMT MAC_DMZFW MAC_DMZSRV MAC_TAP
# Take the 4 MACs from VMware > Network Adapter > Advanced for the segments
# LAB-VLAN99, LAB-DMZ-OUTER, LAB-DMZ-INNER, LAB-TRUNK. Linux does NOT name the NICs
# (ens33, ens37, ...) in adapter order, so guessing by name gets them mixed up.
# It only writes /root/01-lab.yaml.new; applying it is a separate, manual step.
set -e

if [ "$#" -ne 4 ]; then
  echo "Usage: sudo bash $0 MAC_MGMT MAC_DMZFW MAC_DMZSRV MAC_TAP"
  echo "MACs found on this machine:"
  for n in $(ls /sys/class/net | grep -v '^lo$' | sort -V); do echo "  $n  $(cat /sys/class/net/$n/address)"; done
  exit 1
fi

MACS=()
for m in "$@"; do MACS+=("$(echo "$m" | tr 'A-F' 'a-f')"); done
for m in "${MACS[@]}"; do
  grep -qi "^$m$" /sys/class/net/*/address || { echo "MAC $m is not on this machine."; exit 1; }
done

NAMES=(mgmt0 dmzfw0 dmzsrv0 tap0)
SEGS=(LAB-VLAN99 LAB-DMZ-OUTER LAB-DMZ-INNER LAB-TRUNK)
for i in 0 1 2 3; do echo "  ${MACS[$i]}  -> ${NAMES[$i]}  (${SEGS[$i]})"; done

capture() {   # $1 = new name, $2 = MAC
cat <<EOF

    $1:
      match: {macaddress: "$2"}
      set-name: $1
      dhcp4: false
      dhcp6: false
      accept-ra: false
      link-local: []
      optional: true
      receive-checksum-offload: false
      transmit-checksum-offload: false
      tcp-segmentation-offload: false
      tcp6-segmentation-offload: false
      generic-segmentation-offload: false
      generic-receive-offload: false
      large-receive-offload: false
EOF
}

{
cat <<EOF
network:
  version: 2
  renderer: networkd
  ethernets:
    mgmt0:
      match: {macaddress: "${MACS[0]}"}
      set-name: mgmt0
      dhcp4: false
      addresses: [10.10.99.20/24]
      routes:
        - to: default
          via: 10.10.99.1
      nameservers: {addresses: [10.10.99.1], search: [lab.internal]}
EOF
capture dmzfw0  "${MACS[1]}"
capture dmzsrv0 "${MACS[2]}"
capture tap0    "${MACS[3]}"
} > /root/01-lab.yaml.new
chmod 600 /root/01-lab.yaml.new

echo 'network: {config: disabled}' > /etc/cloud/cloud.cfg.d/99-disable-network-config.cfg
echo
echo "Written: /root/01-lab.yaml.new. Apply it with:"
echo "  sudo mkdir -p /root/netplan-old && sudo mv /etc/netplan/*.yaml /root/netplan-old/"
echo "  sudo cp /root/01-lab.yaml.new /etc/netplan/01-lab.yaml && sudo chmod 600 /etc/netplan/01-lab.yaml"
echo "  sudo reboot"
