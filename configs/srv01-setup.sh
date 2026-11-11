#!/bin/bash
# SRV01 (critical server, VLAN 20): MariaDB for DVWA + Samba share for the CLIENTS VLAN.
# Run as root on SRV01 while its NIC is still on NAT:  sudo bash srv01-setup.sh
# It asks for the Samba password of user "alice" (kept out of this file on purpose).
# It does NOT enable ufw and does NOT apply the VLAN 20 netplan file; see the end.
set -e

WEB01_IP=10.10.50.20
CLIENTS_NET=10.10.10.0/24
ADDR=10.10.20.10/24
GW=10.10.20.1

apt update
apt install -y mariadb-server samba ufw

# --- MariaDB: non-interactive equivalent of mariadb-secure-installation ---
sed -i 's/^bind-address.*/bind-address = 0.0.0.0/' /etc/mysql/mariadb.conf.d/50-server.cnf
systemctl restart mariadb
mariadb <<SQL
DELETE FROM mysql.global_priv WHERE User='';
DROP DATABASE IF EXISTS test;
CREATE DATABASE IF NOT EXISTS dvwa;
CREATE USER IF NOT EXISTS 'dvwa'@'${WEB01_IP}' IDENTIFIED BY 'p@ssw0rd';
GRANT ALL PRIVILEGES ON dvwa.* TO 'dvwa'@'${WEB01_IP}';
FLUSH PRIVILEGES;
SQL
# (root keeps Ubuntu's default unix_socket login: no password, local root only)

# --- Samba share for CLIENTS ---
id alice >/dev/null 2>&1 || useradd -M -s /usr/sbin/nologin alice
printf 'Samba password for alice: '; read -r -s SMBPASS; echo
printf 'Repeat: '; read -r -s SMBPASS2; echo
[ "$SMBPASS" = "$SMBPASS2" ] || { echo "Passwords differ, aborting."; exit 1; }
printf '%s\n%s\n' "$SMBPASS" "$SMBPASS" | smbpasswd -a -s alice
unset SMBPASS SMBPASS2
mkdir -p /srv/share
echo "Q3 payroll summary - CONFIDENTIAL" > /srv/share/payroll.txt
chown -R alice: /srv/share && chmod 770 /srv/share
grep -q '^\[share\]' /etc/samba/smb.conf || cat >> /etc/samba/smb.conf <<'EOF'

[share]
   path = /srv/share
   valid users = alice
   read only = no
   browseable = yes
EOF
testparm -s >/dev/null && systemctl restart smbd

# --- host firewall rules (enabled manually at the end) ---
ufw default deny incoming
ufw default allow outgoing
ufw allow from 10.10.99.0/24 to any port 22 proto tcp comment 'SSH from MGMT only'
ufw allow from ${WEB01_IP} to any port 3306 proto tcp comment 'DB from WEB01 only'
ufw allow from ${CLIENTS_NET} to any port 445 proto tcp comment 'SMB from CLIENTS'

# --- VLAN 20 netplan file, written but not applied ---
echo 'network: {config: disabled}' > /etc/cloud/cloud.cfg.d/99-disable-network-config.cfg
NIC=$(ls /sys/class/net | grep -v '^lo$' | head -n1)
cat > /root/01-lab.yaml.new <<EOF
network:
  version: 2
  renderer: networkd
  ethernets:
    ${NIC}:
      dhcp4: false
      dhcp6: false
      addresses: [${ADDR}]
      routes:
        - to: default
          via: ${GW}
      nameservers:
        addresses: [${GW}]
        search: [lab.internal]
EOF
chmod 600 /root/01-lab.yaml.new

echo
echo "Checks:"
mariadb -e "SELECT User,Host FROM mysql.user WHERE User='dvwa';"
ss -tlnp | grep -E ':3306|:445' || true
echo "Done. VLAN 20 network file: /root/01-lab.yaml.new (NIC: ${NIC})."
