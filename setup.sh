#!/bin/bash

# Skrip Setup VPS Ubuntu 22.04 untuk Aplikasi Web Streaming PHP
#
# PERINGATAN: Jalankan skrip ini sebagai root atau dengan sudo.
# Skrip ini akan menginstal paket dan membuat beberapa konfigurasi.
# Selalu periksa kembali skrip sebelum menjalankannya di server produksi.

# Fungsi untuk menampilkan pesan error dan keluar
error_exit() {
    echo "Error: $1" >&2
    exit 1
}

# Fungsi untuk konfirmasi
confirm() {
    while true; do
        read -r -p "$1 [y/N]: " response
        case "$response" in
            [yY][eE][sS]|[yY])
                return 0
                ;;
            [nN][oO]|[nN]|"")
                return 1
                ;;
            *)
                echo "Pilihan tidak valid."
                ;;
        esac
    done
}

# 0. Periksa hak akses root/sudo
if [ "$(id -u)" -ne 0 ]; then
    echo "Skrip ini harus dijalankan sebagai root atau dengan sudo."
    exit 1
fi

echo "Memulai setup VPS untuk Aplikasi Streaming PHP..."
echo "--------------------------------------------------"

# 1. Update Sistem
echo "[1/9] Memperbarui sistem..."
apt update && apt upgrade -y || error_exit "Gagal memperbarui sistem."
echo "Sistem telah diperbarui."
echo "--------------------------------------------------"

# 2. Instal Dependensi Umum
echo "[2/9] Menginstal dependensi umum (curl, wget, unzip, git)..."
apt install -y curl wget unzip git software-properties-common || error_exit "Gagal menginstal dependensi umum."
echo "Dependensi umum telah terinstal."
echo "--------------------------------------------------"

# 3. Instal PHP dan Ekstensi yang Diperlukan
PHP_VERSION="8.1" # Anda bisa mengganti ke versi PHP yang lebih baru jika diinginkan (misal, 8.2, 8.3)
echo "[3/9] Menginstal PHP ${PHP_VERSION} dan ekstensi yang diperlukan..."
add-apt-repository -y ppa:ondrej/php # PPA untuk versi PHP terbaru
apt update
apt install -y php${PHP_VERSION} php${PHP_VERSION}-fpm php${PHP_VERSION}-cli php${PHP_VERSION}-common php${PHP_VERSION}-mysql php${PHP_VERSION}-zip php${PHP_VERSION}-gd php${PHP_VERSION}-mbstring php${PHP_VERSION}-curl php${PHP_VERSION}-xml php${PHP_VERSION}-bcmath php${PHP_VERSION}-json php${PHP_VERSION}-posix || error_exit "Gagal menginstal PHP ${PHP_VERSION} atau ekstensinya."

# Verifikasi instalasi PHP
php -v || error_exit "PHP tidak terinstal dengan benar."
echo "PHP ${PHP_VERSION} dan ekstensi telah terinstal."
echo "--------------------------------------------------"

# 4. Instal FFMPEG
echo "[4/9] Menginstal FFMPEG..."
apt install -y ffmpeg || error_exit "Gagal menginstal FFMPEG."
# Verifikasi instalasi FFMPEG
ffmpeg -version || error_exit "FFMPEG tidak terinstal dengan benar."
echo "FFMPEG telah terinstal."
echo "--------------------------------------------------"

# 5. Instal Rclone
echo "[5/9] Menginstal Rclone..."
curl https://rclone.org/install.sh | bash || error_exit "Gagal menginstal Rclone."
# Verifikasi instalasi Rclone
rclone version || error_exit "Rclone tidak terinstal dengan benar."
echo "Rclone telah terinstal."
echo "--------------------------------------------------"

# 6. Pilih dan Instal Web Server (Apache atau Nginx)
WEB_SERVER=""
while [[ "$WEB_SERVER" != "apache" && "$WEB_SERVER" != "nginx" ]]; do
    read -r -p "Pilih Web Server yang akan diinstal (apache/nginx): " WEB_SERVER
    WEB_SERVER=$(echo "$WEB_SERVER" | tr '[:upper:]' '[:lower:]')
done

# Path root direktori web aplikasi Anda
APP_DIR_NAME="streamingapp" # Ganti jika nama folder aplikasi Anda berbeda
WEB_ROOT="/var/www/html"
APP_PATH="${WEB_ROOT}/${APP_DIR_NAME}"

echo "[6/9] Menginstal dan mengkonfigurasi Web Server (${WEB_SERVER})..."
if [ "$WEB_SERVER" == "apache" ]; then
    apt install -y apache2 libapache2-mod-php${PHP_VERSION} || error_exit "Gagal menginstal Apache."
    a2enmod rewrite
    a2enmod php${PHP_VERSION}

    # Konfigurasi Apache Virtual Host dasar untuk IP Address
    APACHE_CONF_FILE="/etc/apache2/sites-available/000-default.conf"
    # Backup konfigurasi default
    cp "$APACHE_CONF_FILE" "$APACHE_CONF_FILE.bak"
    
    # Hapus isi default dan ganti dengan konfigurasi untuk aplikasi Anda di subdirektori
    # atau langsung di root jika APP_DIR_NAME kosong
    if [ -z "$APP_DIR_NAME" ]; then
      TARGET_WEB_ROOT="$WEB_ROOT"
    else
      TARGET_WEB_ROOT="$APP_PATH"
    fi

    cat > "$APACHE_CONF_FILE" <<EOF
<VirtualHost *:80>
    ServerAdmin webmaster@localhost
    DocumentRoot ${TARGET_WEB_ROOT}

    <Directory ${TARGET_WEB_ROOT}>
        Options Indexes FollowSymLinks
        AllowOverride All
        Require all granted
    </Directory>

    ErrorLog \${APACHE_LOG_DIR}/error.log
    CustomLog \${APACHE_LOG_DIR}/access.log combined
</VirtualHost>
EOF
    echo "Konfigurasi Apache dasar untuk IP Address telah dibuat."
    echo "File aplikasi Anda harus ditempatkan di: ${TARGET_WEB_ROOT}"
    systemctl restart apache2 || error_exit "Gagal me-restart Apache."
    systemctl enable apache2
    echo "Apache telah diinstal dan dikonfigurasi."

elif [ "$WEB_SERVER" == "nginx" ]; then
    apt install -y nginx || error_exit "Gagal menginstal Nginx."
    
    # Konfigurasi Nginx server block dasar untuk IP Address
    NGINX_CONF_FILE="/etc/nginx/sites-available/default"
    # Backup konfigurasi default
    cp "$NGINX_CONF_FILE" "$NGINX_CONF_FILE.bak"

    if [ -z "$APP_DIR_NAME" ]; then
      TARGET_WEB_ROOT="$WEB_ROOT"
    else
      TARGET_WEB_ROOT="$APP_PATH"
    fi

    cat > "$NGINX_CONF_FILE" <<EOF
server {
    listen 80 default_server;
    listen [::]:80 default_server;

    root ${TARGET_WEB_ROOT};
    index index.php index.html index.htm;

    server_name _; # Menggunakan IP Address

    location / {
        try_files \$uri \$uri/ /index.php?\$query_string;
    }

    location ~ \.php\$ {
        include snippets/fastcgi-php.conf;
        fastcgi_pass unix:/var/run/php/php${PHP_VERSION}-fpm.sock;
        fastcgi_param SCRIPT_FILENAME \$document_root\$fastcgi_script_name;
        include fastcgi_params;
    }

    location ~ /\.ht {
        deny all;
    }
}
EOF
    echo "Konfigurasi Nginx dasar untuk IP Address telah dibuat."
    echo "File aplikasi Anda harus ditempatkan di: ${TARGET_WEB_ROOT}"
    
    # Test konfigurasi Nginx
    nginx -t
    if [ $? -ne 0 ]; then
        error_exit "Konfigurasi Nginx tidak valid. Setup dihentikan."
    fi
    
    systemctl restart nginx || error_exit "Gagal me-restart Nginx."
    systemctl enable nginx
    echo "Nginx telah diinstal dan dikonfigurasi."
fi
echo "--------------------------------------------------"

# 7. Atur Firewall (UFW)
echo "[7/9] Mengatur UFW (Firewall)..."
ufw allow ssh # Port 22 (atau port SSH kustom Anda)
ufw allow http  # Port 80
ufw allow https # Port 443 (jika Anda akan menggunakan SSL nantinya)
# Tambahkan port RTMP jika server ini juga akan menjadi server RTMP (misal 1935)
# ufw allow 1935/tcp 
ufw --force enable || echo "Peringatan: Gagal mengaktifkan UFW secara paksa."
ufw status
echo "UFW telah diatur."
echo "--------------------------------------------------"

# 8. Buat Direktori Aplikasi dan Atur Izin
echo "[8/9] Membuat direktori aplikasi dan mengatur izin..."

# Jika APP_DIR_NAME tidak kosong, buat subdirektorinya
if [ ! -z "$APP_DIR_NAME" ]; then
    mkdir -p "$APP_PATH" || error_exit "Gagal membuat direktori aplikasi di ${APP_PATH}."
    TARGET_OWNERSHIP_PATH="$APP_PATH"
else
    TARGET_OWNERSHIP_PATH="$WEB_ROOT" # Jika aplikasi di root web
fi

# Atur kepemilikan ke user www-data (user web server umum)
# Ini penting agar PHP bisa menulis ke direktori 'data' dan subdirektorinya
chown -R www-data:www-data "$TARGET_OWNERSHIP_PATH"
chmod -R 755 "$TARGET_OWNERSHIP_PATH" # Izin baca & eksekusi untuk semua, tulis hanya untuk owner

echo "Direktori aplikasi di ${TARGET_OWNERSHIP_PATH} telah disiapkan."
echo "Pastikan Anda mengunggah file aplikasi PHP Anda ke direktori tersebut."
echo "Kemudian, Anda perlu secara manual membuat subdirektori 'data', 'bin' di dalam ${TARGET_OWNERSHIP_PATH} dan mengatur izin tulis untuk 'data' dan subdirektorinya untuk user www-data."
echo "Contoh setelah upload aplikasi:"
echo "  sudo mkdir -p ${TARGET_OWNERSHIP_PATH}/data/datajson ${TARGET_OWNERSHIP_PATH}/data/rtmp ${TARGET_OWNERSHIP_PATH}/data/secure/service_accounts ${TARGET_OWNERSHIP_PATH}/pid"
echo "  sudo chown -R www-data:www-data ${TARGET_OWNERSHIP_PATH}/data"
echo "  sudo chmod -R 775 ${TARGET_OWNERSHIP_PATH}/data  # Izin tulis untuk group www-data"
echo "  sudo mkdir -p ${TARGET_OWNERSHIP_PATH}/bin/rclone"
echo "  sudo cp /path/to/your/local/ffmpeg ${TARGET_OWNERSHIP_PATH}/bin/"
echo "  sudo cp /path/to/your/local/rclone_binary ${TARGET_OWNERSHIP_PATH}/bin/rclone/"
echo "  sudo chmod +x ${TARGET_OWNERSHIP_PATH}/bin/ffmpeg ${TARGET_OWNERSHIP_PATH}/bin/rclone/rclone"
echo "--------------------------------------------------"

# 9. Konfigurasi PHP (Opsional, tapi direkomendasikan)
echo "[9/9] Mengkonfigurasi beberapa parameter PHP di php.ini..."
# Cari file php.ini yang digunakan oleh web server (FPM atau mod_php)
PHP_INI_PATH=""
if [ "$WEB_SERVER" == "apache" ]; then
    # Untuk Apache dengan mod_php, pathnya bisa berbeda. Ini asumsi umum.
    # Jika menggunakan PHP-FPM dengan Apache, pathnya akan seperti Nginx.
    # Untuk kesederhanaan, kita akan fokus pada FPM yang lebih umum untuk produksi.
    PHP_INI_PATH=$(php -i | grep /.+/php.ini | grep php${PHP_VERSION}-fpm | awk '{print $3}' | head -n 1)
    if [ -z "$PHP_INI_PATH" ]; then # Fallback jika FPM tidak terdeteksi untuk Apache (mungkin mod_php)
       PHP_INI_PATH=$(php -i | grep /.+/php.ini | grep apache2 | awk '{print $3}' | head -n 1)
    fi
else # Nginx pasti menggunakan FPM
    PHP_INI_PATH=$(php -i | grep /.+/php.ini | grep php${PHP_VERSION}-fpm | awk '{print $3}' | head -n 1)
fi


if [ -f "$PHP_INI_PATH" ]; then
    echo "File php.ini ditemukan di: ${PHP_INI_PATH}"
    # Backup file php.ini
    cp "$PHP_INI_PATH" "$PHP_INI_PATH.bak_$(date +%F_%T)"

    # Parameter yang mungkin perlu disesuaikan
    sed -i 's/upload_max_filesize = .*/upload_max_filesize = 64M/' "$PHP_INI_PATH"
    sed -i 's/post_max_size = .*/post_max_size = 64M/' "$PHP_INI_PATH"
    sed -i 's/memory_limit = .*/memory_limit = 256M/' "$PHP_INI_PATH"
    sed -i 's/max_execution_time = .*/max_execution_time = 300/' "$PHP_INI_PATH" # Untuk proses upload SA / rclone yang lama
    
    # Pastikan exec tidak ada di disable_functions
    # Ini penting karena error Anda sebelumnya!
    CURRENT_DISABLED_FUNCTIONS=$(grep -Po '^disable_functions\s*=\s*\K.*' "$PHP_INI_PATH")
    if [[ "$CURRENT_DISABLED_FUNCTIONS" == *"exec"* ]]; then
        echo "Peringatan: 'exec' ditemukan di disable_functions. Mencoba menghapusnya..."
        # Hapus 'exec' dengan hati-hati, menjaga fungsi lain yang mungkin dinonaktifkan
        NEW_DISABLED_FUNCTIONS=$(echo "$CURRENT_DISABLED_FUNCTIONS" | sed -E 's/(^|,)\s*exec\s*(,|$)/\1\2/g' | sed -E 's/,$//; s/^,//')
        sed -i "s/disable_functions = .*/disable_functions = ${NEW_DISABLED_FUNCTIONS}/" "$PHP_INI_PATH"
        echo "disable_functions setelah diubah: ${NEW_DISABLED_FUNCTIONS}"
    else
        echo "'exec' tidak ditemukan di disable_functions. Bagus!"
    fi

    echo "Beberapa parameter php.ini telah disesuaikan."
    
    # Restart layanan PHP-FPM dan Web Server untuk menerapkan perubahan php.ini
    echo "Me-restart layanan PHP-FPM dan Web Server..."
    systemctl restart php${PHP_VERSION}-fpm || echo "Peringatan: Gagal me-restart php${PHP_VERSION}-fpm."
    if [ "$WEB_SERVER" == "apache" ]; then
        systemctl restart apache2
    elif [ "$WEB_SERVER" == "nginx" ]; then
        systemctl restart nginx
    fi
else
    echo "Peringatan: File php.ini tidak ditemukan secara otomatis. Anda mungkin perlu mengeditnya manual."
    echo "Lokasi umum: /etc/php/${PHP_VERSION}/fpm/php.ini atau /etc/php/${PHP_VERSION}/apache2/php.ini"
fi
echo "--------------------------------------------------"

# Selesai
PUBLIC_IP=$(curl -s ifconfig.me)
echo "Setup Selesai!"
echo "================================================================================"
echo " VPS Anda seharusnya sudah siap untuk Aplikasi Streaming PHP."
echo ""
echo " Langkah Selanjutnya:"
echo " 1. Unggah file aplikasi PHP Anda ke: ${TARGET_WEB_ROOT}"
echo "    (Misalnya menggunakan SCP, FTP, atau Git)"
echo " 2. Di dalam ${TARGET_WEB_ROOT}, buat struktur direktori yang diperlukan:"
echo "    - mkdir -p data/datajson data/rtmp data/secure/service_accounts pid"
echo "    - mkdir -p bin/rclone"
echo " 3. Salin binary FFMPEG dan Rclone portabel Anda ke ${TARGET_WEB_ROOT}/bin/ (atau ${TARGET_WEB_ROOT}/bin/rclone/ untuk rclone)"
echo "    - Contoh: scp /path/lokal/ffmpeg user@${PUBLIC_IP}:${TARGET_WEB_ROOT}/bin/"
echo "    - Contoh: scp /path/lokal/rclone user@${PUBLIC_IP}:${TARGET_WEB_ROOT}/bin/rclone/"
echo " 4. Berikan izin eksekusi pada binary tersebut di server:"
echo "    - chmod +x ${TARGET_WEB_ROOT}/bin/ffmpeg"
echo "    - chmod +x ${TARGET_WEB_ROOT}/bin/rclone/rclone"
echo " 5. Atur kepemilikan dan izin untuk direktori 'data' agar PHP bisa menulis:"
echo "    - sudo chown -R www-data:www-data ${TARGET_WEB_ROOT}/data"
echo "    - sudo chmod -R 775 ${TARGET_WEB_ROOT}/data (atau 755 jika www-data adalah owner)"
echo " 6. (PENTING) Konfigurasi file 'config.php' aplikasi Anda, terutama DEFAULT_GOOGLE_CLIENT_ID dan DEFAULT_GOOGLE_CLIENT_SECRET jika menggunakan OAuth."
echo " 7. Akses aplikasi Anda melalui IP Address: http://${PUBLIC_IP}/${APP_DIR_NAME}"
echo "    (atau http://${PUBLIC_IP}/ jika Anda mengosongkan APP_DIR_NAME)"
echo " 8. Lakukan konfigurasi Rclone (Service Account) melalui antarmuka web aplikasi Anda."
echo ""
echo " Catatan Keamanan:"
echo " - Pastikan Anda telah mengamankan SSH (misalnya, menggunakan key-based authentication, mengubah port default, fail2ban)."
echo " - Pertimbangkan untuk menggunakan HTTPS dengan SSL Certificate (misalnya, dari Let's Encrypt) jika ini untuk produksi."
echo "================================================================================"

if confirm "Apakah Anda ingin menjalankan 'rclone config' sekarang untuk membuat file konfigurasi rclone awal secara manual? (Ini akan menggunakan konfigurasi default rclone, bukan yang portabel dari aplikasi)"; then
    echo "Menjalankan 'rclone config'. Ikuti petunjuknya."
    echo "PENTING: Jika Anda berencana menggunakan file konfigurasi rclone portabel yang dikelola aplikasi (data/rclone_settings.json dan file SA JSON), Anda mungkin tidak perlu melakukan ini, atau lakukan ini hanya untuk pengujian rclone global."
    rclone config
else
    echo "Setup rclone config global dilewati. Anda akan mengkonfigurasi rclone melalui antarmuka web aplikasi."
fi

echo "Skrip setup telah selesai."