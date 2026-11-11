#!/bin/bash
# PROXY01 (DMZ): Nginx reverse proxy in front of WEB01 + Squid forward proxy for the CLIENTS VLAN.
# Run as root on PROXY01 while its NIC is still on NAT:  sudo bash proxy01-setup.sh
# It does NOT enable ufw and does NOT apply the DMZ netplan file; see the end.
set -e

WEB01_IP=10.10.50.20
CLIENTS_NET=10.10.10.0/24
ADDR=10.10.50.10/24
GW=10.10.50.1
WAN_IP=172.16.148.10       # pfSense WAN address (goes into the certificate)

apt update
apt install -y nginx squid openssl ufw

# --- self-signed TLS certificate (lab only) ---
mkdir -p /etc/ssl/lab
[ -f /etc/ssl/lab/proxy01.crt ] || openssl req -x509 -newkey rsa:2048 -nodes -days 825 \
  -keyout /etc/ssl/lab/proxy01.key -out /etc/ssl/lab/proxy01.crt \
  -subj "/CN=www.lab.internal" \
  -addext "subjectAltName=DNS:www.lab.internal,IP:${WAN_IP},IP:10.10.50.10"
chmod 600 /etc/ssl/lab/proxy01.key

# --- Nginx reverse proxy ---
cat > /etc/nginx/sites-available/web01-rp <<EOF
upstream web01 {
    server ${WEB01_IP}:80;
}
server {
    # LAB CHOICE: port 80 is served (not redirected) so the IDS/IPS can inspect
    # cleartext attacks. In production: return 301 https://\$host\$request_uri;
    listen 80  default_server;
    listen 443 ssl default_server;
    server_name www.lab.internal _;

    ssl_certificate     /etc/ssl/lab/proxy01.crt;
    ssl_certificate_key /etc/ssl/lab/proxy01.key;
    ssl_protocols       TLSv1.2 TLSv1.3;

    server_tokens off;
    client_max_body_size 5m;
    add_header X-Content-Type-Options "nosniff" always;
    add_header X-Frame-Options "SAMEORIGIN" always;
    add_header Referrer-Policy "strict-origin-when-cross-origin" always;

    access_log /var/log/nginx/rp_access.log;
    error_log  /var/log/nginx/rp_error.log;

    location / {
        proxy_pass         http://web01;
        proxy_set_header   Host              \$host;
        proxy_set_header   X-Real-IP         \$remote_addr;
        proxy_set_header   X-Forwarded-For   \$proxy_add_x_forwarded_for;
        proxy_set_header   X-Forwarded-Proto \$scheme;
    }
}
EOF
ln -sf /etc/nginx/sites-available/web01-rp /etc/nginx/sites-enabled/web01-rp
rm -f /etc/nginx/sites-enabled/default
nginx -t && systemctl reload nginx

# --- Squid forward proxy for the CLIENTS VLAN ---
cat > /etc/squid/conf.d/lab.conf <<EOF
# Who may use the proxy
acl lab_clients src ${CLIENTS_NET}
# Simple URL-filtering policy (one domain per line, leading dot = subdomains)
acl blocked_sites dstdomain "/etc/squid/blocked_sites.txt"
http_access deny  lab_clients blocked_sites
http_access allow lab_clients
# Don't leak internal addressing to websites
forwarded_for delete
via off
EOF
printf '.example.com\n.tiktok.com\n' > /etc/squid/blocked_sites.txt
squid -k parse
systemctl restart squid

# --- host firewall rules (enabled manually at the end) ---
ufw default deny incoming
ufw default allow outgoing
ufw allow from 10.10.99.0/24 to any port 22 proto tcp comment 'SSH from MGMT only'
ufw allow 80/tcp  comment 'HTTP (port forward + clients)'
ufw allow 443/tcp comment 'HTTPS (port forward + clients)'
ufw allow from ${CLIENTS_NET} to any port 3128 proto tcp comment 'Squid for CLIENTS'

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
echo "Checks:"
nginx -t
ss -tlnp | grep -E ':80 |:443 |:3128 ' || true
echo "Done. DMZ network file: /root/01-lab.yaml.new (NIC: ${NIC})."
