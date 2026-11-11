#!/bin/sh
# WEB01 (DMZ application server): Apache + PHP + DVWA, DB on SRV01.
# Run as root on WEB01 while its NIC is still on NAT (needs Internet):  sudo sh web01-setup.sh
# It does NOT enable ufw and does NOT apply the DMZ netplan file; you do that last (see the end).
set -e

DB_HOST=10.10.20.10        # SRV01
PROXY_IP=10.10.50.10       # PROXY01 (add 10.10.50.30 later for WAF01)
ADDR=10.10.50.20/24
GW=10.10.50.1

apt update
apt install -y apache2 php libapache2-mod-php php-mysql php-gd git ufw

# --- web content and DVWA ---
rm -f /var/www/html/index.html
echo '<h1>WEB01 - lab.internal</h1>' > /var/www/html/index.html
[ -d /var/www/html/dvwa ] || git clone https://github.com/digininja/DVWA.git /var/www/html/dvwa
cd /var/www/html/dvwa/config
[ -f config.inc.php ] || cp config.inc.php.dist config.inc.php
# DVWA reads the DB host as getenv('DB_SERVER') ?: '127.0.0.1': replace the fallback
sed -i "/'db_server'/ s/'127\.0\.0\.1'/'${DB_HOST}'/" config.inc.php
grep -E "db_(server|database|user|password)'" config.inc.php
chown -R www-data:www-data /var/www/html/dvwa/hackable/uploads /var/www/html/dvwa/config

# DVWA's setup page asks for these PHP settings (also needed for the file-inclusion exercises)
for ini in /etc/php/*/apache2/php.ini; do
  sed -i 's/^allow_url_include *=.*/allow_url_include = On/; s/^allow_url_fopen *=.*/allow_url_fopen = On/' "$ini"
done

# --- log the real visitor IP sent by the reverse proxy instead of the proxy's own address ---
cat > /etc/apache2/conf-available/remoteip.conf <<EOF
RemoteIPHeader X-Forwarded-For
RemoteIPInternalProxy ${PROXY_IP}
EOF
a2enmod remoteip
a2enconf remoteip
sed -i 's/LogFormat "%h %l/LogFormat "%a %l/' /etc/apache2/apache2.conf
apache2ctl configtest
systemctl restart apache2

# --- host firewall rules (defense in depth); enabled manually at the end ---
ufw default deny incoming
ufw default allow outgoing
ufw allow from 10.10.99.0/24 to any port 22 proto tcp comment 'SSH from MGMT only'
ufw allow from ${PROXY_IP} to any port 80 proto tcp comment 'HTTP from PROXY01 only'

# --- DMZ netplan file, written but not applied ---
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
echo "Done. Packages and DVWA are installed. The DMZ network file is at /root/01-lab.yaml.new (NIC: ${NIC})."
echo "Next: run the 'finish' commands from the guide (swap the netplan file, enable ufw, power off)."
