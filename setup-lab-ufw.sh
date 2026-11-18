#!/usr/bin/env bash
# ==========================================================
#  setup-lab-ufw.sh
#  Membuat server Ubuntu "rentan" untuk latihan UFW (SIMULASI)
#
#  Port DIBUTUHKAN (harus tetap terbuka) : 22, 80, 443
#  Port TIDAK DIBUTUHKAN (soal siswa)    : 21, 23, 445, 3306, 8080
#
#  Cara pakai : sudo bash setup-lab-ufw.sh
#  Aman diulang: dijalankan lagi = kondisi lab kembali ke awal.
#  PERINGATAN : HANYA untuk VM latihan, jangan di server produksi!
# ==========================================================
set -euo pipefail

if [[ $EUID -ne 0 ]]; then
  echo "Jalankan dengan sudo:  sudo bash $0"
  exit 1
fi

export DEBIAN_FRONTEND=noninteractive

echo "[1/7] Update repositori dan instal paket..."
apt-get update -y
apt-get install -y ufw openssh-server apache2 ssl-cert \
  vsftpd samba mysql-server socat nmap curl

# ----------------------------------------------------------
echo "[2/7] SSH (port 22) - DIBUTUHKAN..."
systemctl enable --now ssh

# ----------------------------------------------------------
echo "[3/7] Web server HTTP 80 dan HTTPS 443 - DIBUTUHKAN..."
a2enmod ssl >/dev/null
a2ensite default-ssl >/dev/null
cat > /var/www/html/index.html <<'EOF'
<!DOCTYPE html>
<html lang="id">
<head><meta charset="utf-8"><title>SMK Nusantara</title></head>
<body>
  <h1>Website SMK Nusantara</h1>
  <p>Server latihan keamanan firewall UFW.</p>
</body>
</html>
EOF
systemctl enable apache2
systemctl restart apache2

# ----------------------------------------------------------
echo "[4/7] Port 8080 (HTTP-alt, via Apache) - TIDAK DIBUTUHKAN..."
echo "Listen 8080" > /etc/apache2/conf-available/port-8080-lab.conf
a2enconf port-8080-lab >/dev/null
systemctl restart apache2

# ----------------------------------------------------------
echo "[5/7] Port 21 (FTP), 445 (SMB), 3306 (MySQL) - TIDAK DIBUTUHKAN..."

# FTP (vsftpd) -> port 21
sed -i 's/^listen=.*/listen=YES/; s/^listen_ipv6=.*/listen_ipv6=NO/' /etc/vsftpd.conf
grep -q '^listen=' /etc/vsftpd.conf || echo 'listen=YES' >> /etc/vsftpd.conf
systemctl enable vsftpd
systemctl restart vsftpd

# SMB (Samba) -> port 445
if ! grep -q '^\s*smb ports' /etc/samba/smb.conf; then
  sed -i '/^\[global\]/a\   smb ports = 445' /etc/samba/smb.conf
fi
systemctl enable smbd nmbd
systemctl restart smbd nmbd

# MySQL dibuat terbuka ke jaringan -> port 3306
sed -i 's/^bind-address.*/bind-address = 0.0.0.0/' /etc/mysql/mysql.conf.d/mysqld.cnf
systemctl enable mysql
systemctl restart mysql

# ----------------------------------------------------------
echo "[6/7] Port 23 (Telnet palsu untuk simulasi) - TIDAK DIBUTUHKAN..."
# Hanya pendengar sederhana dengan banner. Bukan telnet asli.
cat > /etc/systemd/system/fake-telnet.service <<'EOF'
[Unit]
Description=Telnet palsu untuk lab UFW (simulasi)
After=network.target

[Service]
ExecStart=/usr/bin/socat TCP-LISTEN:23,reuseaddr,fork SYSTEM:"echo SIMULASI-TELNET-SMK-NUSANTARA"
Restart=always

[Install]
WantedBy=multi-user.target
EOF
systemctl daemon-reload
systemctl enable fake-telnet
systemctl restart fake-telnet

# ----------------------------------------------------------
echo "[7/7] Konfigurasi UFW (kondisi rentan)..."
ufw --force reset >/dev/null
ufw default deny incoming  >/dev/null
ufw default allow outgoing >/dev/null

# Port yang DIBUTUHKAN (SSH diizinkan lebih dulu agar tidak terkunci)
ufw allow 22/tcp  comment 'SSH'
ufw allow 80/tcp  comment 'HTTP'
ufw allow 443/tcp comment 'HTTPS'

# Port yang TIDAK DIBUTUHKAN (soal untuk siswa)
ufw allow 21/tcp   comment 'FTP'
ufw allow 23/tcp   comment 'Telnet'
ufw allow 445/tcp  comment 'SMB'
ufw allow 3306/tcp comment 'MySQL'
ufw allow 8080/tcp comment 'HTTP-alt'

ufw --force enable

echo
echo "=========================================="
echo " LAB SIAP. Kondisi server saat ini:"
echo "=========================================="
ufw status numbered
echo
ss -tulpn | grep -E ':(21|22|23|80|443|445|3306|8080)\s' || true
echo
echo "IP server ini  : $(hostname -I | awk '{print $1}')"
echo "Selesai. Sekarang kerjakan soal sesuai lembar kerja."
