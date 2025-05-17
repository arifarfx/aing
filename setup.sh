#!/bin/bash

# Skrip Setup VPS Ubuntu 24.04 LTS untuk Aplikasi Web Streaming PHP
# Fokus pada PHP 8.3
#
# PERINGATAN: Jalankan skrip ini sebagai root atau dengan sudo.
# Selalu periksa kembali skrip sebelum menjalankannya di server produksi.

# Fungsi untuk menampilkan pesan error dan keluar
error_exit() {
    echo ""
    echo "!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!"
    echo "Error: $1" >&2
    echo "Setup dihentikan."
    echo "!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!"
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

echo "Memulai setup VPS Ubuntu 24.04 LTS untuk Aplikasi Streaming PHP..."
echo "--------------------------------------------------"

# 1. Update Sistem
echo "[1/9] Memperbarui sistem..."
apt update && apt upgrade -y || error_exit "Gagal memperbarui sistem."
echo "Sistem telah diperbarui."
echo "--------------------------------------------------"

# 2. Instal Dependensi Umum
echo "[2/9] Menginstal dependensi umum (curl, wget, unzip, git, software-properties-common)..."
apt install -y curl wget unzip git software-properties-common || error_exit "Gagal menginstal dependensi umum."
echo "Dependensi umum telah terinstal."
echo "--------------------------------------------------"

# 3. Instal PHP 8.3 dan Ekstensi yang Diperlukan
PHP_VERSION_TARGET="8.3"
echo "[3/9] Menginstal PHP ${PHP_VERSION_TARGET} dan ekstensi yang diperlukan..."
# Tambahkan PPA Ondřej Surý untuk versi PHP yang up-to-date dan lebih banyak ekstensi
# Ini juga berguna jika default Ubuntu 24.04 belum PHP 8.3 atau butuh ekstensi tertentu
echo "Menambahkan PPA ondrej/php..."
add-apt-repository -y ppa:ondrej/php || error_exit "Gagal menambahkan PPA ondrej/php."
apt update

echo "Menginstal paket PHP ${PHP_VERSION_TARGET}..."
apt install -y \
    php${PHP_VERSION_TARGET} \
    php${PHP_VERSION_TARGET}-fpm \
    php${PHP_VERSION_TARGET}-cli \
    php${PHP_VERSION_TARGET}-common \
    php${PHP_VERSION_TARGET}-mysql \
    php${PHP_VERSION_TARGET}-zip \
    php${PHP_VERSION_TARGET}-gd \
    php${PHP_VERSION_TARGET}-mbstring \
    php${PHP_VERSION_TARGET}-curl \
    php${PHP_VERSION_TARGET}-xml \
    php${PHP_VERSION_TARGET}-bcmath \
    php${PHP_VERSION_TARGET}-intl \
    php${PHP_VERSION_TARGET}-opcache \
    php${PHP_VERSION_TARGET}-readline \
    php${PHP_VERSION_TARGET}-json \
    php${PHP_VERSION_TARGET}-posix || error_exit "Gagal menginstal PHP ${PHP_VERSION_TARGET} atau ekstensinya."

# Verifikasi instalasi PHP
INSTALLED_PHP_VERSION=$(php -v | head -n 1 | cut -d " " -f 2)
if [[ "$INSTALLED_PHP_VERSION" != "$PHP_VERSION_TARGET"* ]]; then
    error_exit "Versi PHP yang terinstal (${INSTALLED_PHP_VERSION}) tidak sesuai dengan target (${PHP_VERSION_TARGET})."
fi
echo "PHP ${INSTALLED_PHP_VERSION} dan ekstensi telah terinstal."
echo "--------------------------------------------------"

# 4. Instal FFMPEG
echo "[4/9] Menginstal FFMPEG..."
apt install -y ffmpeg || error_exit "Gagal menginstal FFMPEG."
ffmpeg -version || error_exit "FFMPEG tidak terinstal dengan benar atau tidak ditemukan."
echo "FFMPEG telah terinstal."
echo "--------------------------------------------------"

# 5. Instal Rclone
echo "[5/9] Menginstal Rclone..."
# Cek jika rclone sudah terinstal, jika ya, coba update
if command -v rclone &> /dev/null; then
    echo "Rclone sudah terinstal. Mencoba update..."
    curl https://rclone.org/install.sh | bash -s -- --force-update || echo "Peringatan: Gagal mengupdate rclone. Versi yang ada akan digunakan."
else
    curl https://rclone.org/install.sh | bash || error_exit "Gagal menginstal Rclone."
fi
rclone version || error_exit "Rclone tidak terinstal dengan benar atau tidak ditemukan."
echo "Rclone telah terinstal/diperbarui."
echo "--------------------------------------------------"

# 6. Pilih dan Instal Web Server (Apache atau Nginx)
WEB_SERVER=""
while [[ "$WEB_SERVER" != "apache" && "$WEB_SERVER" != "nginx" ]]; do
    read -r -p "Pilih Web Server yang akan diinstal (apache/nginx) [nginx]: " WEB_SERVER_INPUT
    WEB_SERVER=$(echo "${WEB_SERVER_INPUT:-nginx}" | tr '[:upper:]' '[:lower:]') # Default ke nginx jika input kosong
done

APP_DIR_NAME="streamingapp" # Ganti jika nama folder aplikasi Anda berbeda
WEB_ROOT_BASE="/var/www" # Base direktori web
WEB_ROOT_HTML="${WEB_ROOT_BASE}/html" # Default html root
APP_PATH="${WEB_ROOT_BASE}/${APP_DIR_NAME}" # Path aplikasi di /var/www/namaaplikasi

echo "[6/9] Menginstal dan mengkonfigurasi Web Server (${WEB_SERVER})..."
# Buat direktori aplikasi utama jika belum ada
mkdir -p "$APP_PATH" || error_exit "Gagal membuat direktori aplikasi di ${APP_PATH}."

if [ "$WEB_SERVER" == "apache" ]; then
    apt install -y apache2 libapache2-mod-fcgid || error_exit "Gagal menginstal Apache dan mod_fcgid."
    
    # Aktifkan modul yang diperlukan
    a2enmod rewrite proxy_fcgi setenvif
    a2enconf php${PHP_VERSION_TARGET}-fpm # Menggunakan PHP-FPM dengan Apache

    # Buat file konfigurasi Virtual Host baru untuk aplikasi
    APACHE_APP_CONF="/etc/apache2/sites-available/${APP_DIR_NAME}.conf"
    cat > "$APACHE_APP_CONF" <<EOF
<VirtualHost *:80>
    ServerAdmin webmaster@localhost
    DocumentRoot ${APP_PATH}

    <Directory ${APP_PATH}>
        Options Indexes FollowSymLinks
        AllowOverride All
        Require all granted
    </Directory>

    <FilesMatch \.php\$>
        SetHandler "proxy:unix:/var/run/php/php${PHP_VERSION_TARGET}-fpm.sock|fcgi://localhost/"
    </FilesMatch>

    ErrorLog \${APACHE_LOG_DIR}/${APP_DIR_NAME}_error.log
    CustomLog \${APACHE_LOG_DIR}/${APP_DIR_NAME}_access.log combined
</VirtualHost>
EOF
    echo "Konfigurasi Apache Virtual Host untuk ${APP_DIR_NAME} telah dibuat di ${APACHE_APP_CONF}."
    
    # Nonaktifkan situs default dan aktifkan situs aplikasi
    a2dissite 000-default.conf
    a2ensite "${APP_DIR_NAME}.conf"
    
    systemctl restart apache2 || error_exit "Gagal me-restart Apache."
    systemctl enable apache2
    echo "Apache telah diinstal dan dikonfigurasi untuk menggunakan PHP-FPM."

elif [ "$WEB_SERVER" == "nginx" ]; then
    apt install -y nginx || error_exit "Gagal menginstal Nginx."
    
    # Buat file konfigurasi server block baru untuk aplikasi
    NGINX_APP_CONF="/etc/nginx/sites-available/${APP_DIR_NAME}"
    cat > "$NGINX_APP_CONF" <<EOF
server {
    listen 80;
    listen [::]:80;

    server_name _; # Akan merespons ke IP Address atau domain apa pun yang mengarah ke server ini
    root ${APP_PATH};
    index index.php index.html index.htm;

    location / {
        try_files \$uri \$uri/ /index.php?\$query_string;
    }

    location ~ \.php\$ {
        include snippets/fastcgi-php.conf;
        fastcgi_pass unix:/var/run/php/php${PHP_VERSION_TARGET}-fpm.sock;
        fastcgi_param SCRIPT_FILENAME \$document_root\$fastcgi_script_name;
        include fastcgi_params;
    }

    location ~ /\.ht {
        deny all;
    }
    
    # Logging
    access_log /var/log/nginx/${APP_DIR_NAME}_access.log;
    error_log /var/log/nginx/${APP_DIR_NAME}_error.log;
}
EOF
    echo "Konfigurasi Nginx server block untuk ${APP_DIR_NAME} telah dibuat di ${NGINX_APP_CONF}."

    # Buat symlink untuk mengaktifkan situs (jika sites-enabled ada)
    if [ -d "/etc/nginx/sites-enabled" ]; then
        ln -sf "$NGINX_APP_CONF" "/etc/nginx/sites-enabled/${APP_DIR_NAME}"
        # Hapus link default jika ada dan berbeda
        if [ -L "/etc/nginx/sites-enabled/default" ] && [ "$(readlink -f /etc/nginx/sites-enabled/default)" != "$NGINX_APP_CONF" ]; then
            rm -f "/etc/nginx/sites-enabled/default"
        fi
    else
        echo "Peringatan: Direktori /etc/nginx/sites-enabled tidak ditemukan. Anda mungkin perlu include konfigurasi secara manual di nginx.conf."
    fi
    
    nginx -t
    if [ $? -ne 0 ]; then
        error_exit "Konfigurasi Nginx tidak valid. Setup dihentikan."
    fi
    
    systemctl restart nginx || error_exit "Gagal me-restart Nginx."
    systemctl enable nginx
    echo "Nginx telah diinstal dan dikonfigurasi."
fi
echo "File aplikasi Anda harus ditempatkan di: ${APP_PATH}"
echo "--------------------------------------------------"

# 7. Atur Firewall (UFW)
echo "[7/9] Mengatur UFW (Firewall)..."
ufw allow ssh
ufw allow http
ufw allow https
# ufw allow 1935/tcp # Uncomment jika menggunakan server ini sebagai RTMP server juga
if ! ufw status | grep -qw active; then
    ufw --force enable || echo "Peringatan: Gagal mengaktifkan UFW secara paksa."
else
    echo "UFW sudah aktif."
fi
ufw status
echo "UFW telah diatur."
echo "--------------------------------------------------"

# 8. Atur Izin Direktori Aplikasi (Dasar)
echo "[8/9] Mengatur izin dasar untuk direktori aplikasi..."
# Kepemilikan akan diatur ke user yang menjalankan skrip (root/sudo) + grup www-data
# Aplikasi PHP akan berjalan sebagai www-data (via PHP-FPM)
# Jadi www-data perlu izin tulis ke subdirektori data
chown -R "$(logname)":www-data "$APP_PATH"
chmod -R 775 "$APP_PATH" # Memberi izin tulis ke grup www-data juga

echo "Direktori aplikasi di ${APP_PATH} telah disiapkan dengan izin dasar."
echo "Pastikan Anda mengunggah file aplikasi PHP Anda ke direktori tersebut."
echo "Setelah upload, pastikan direktori 'data' dan subdirektorinya dapat ditulis oleh user 'www-data'."
echo "Contoh perintah setelah upload aplikasi dan membuat subdirektori data, bin, dll. di dalam ${APP_PATH}:"
echo "  sudo chown -R www-data:www-data ${APP_PATH}/data"
echo "  sudo chmod -R 775 ${APP_PATH}/data"
echo "  sudo chmod +x ${APP_PATH}/bin/ffmpeg ${APP_PATH}/bin/rclone/rclone"
echo "--------------------------------------------------"

# 9. Konfigurasi PHP (php.ini)
echo "[9/9] Mengkonfigurasi beberapa parameter PHP di php.ini untuk PHP ${PHP_VERSION_TARGET}..."
PHP_INI_FPM_PATH="/etc/php/${PHP_VERSION_TARGET}/fpm/php.ini"
PHP_INI_CLI_PATH="/etc/php/${PHP_VERSION_TARGET}/cli/php.ini"

configure_php_ini() {
    local INI_PATH=$1
    if [ -f "$INI_PATH" ]; then
        echo "Mengkonfigurasi file: ${INI_PATH}"
        # Backup file php.ini
        cp "$INI_PATH" "$INI_PATH.bak_$(date +%F_%T)"

        sed -i 's/^upload_max_filesize = .*/upload_max_filesize = 128M/' "$INI_PATH"
        sed -i 's/^post_max_size = .*/post_max_size = 128M/' "$INI_PATH"
        sed -i 's/^memory_limit = .*/memory_limit = 512M/' "$INI_PATH"
        sed -i 's/^max_execution_time = .*/max_execution_time = 600/' "$INI_PATH"
        sed -i 's/^max_input_time = .*/max_input_time = 300/' "$INI_PATH"
        sed -i 's/^;date.timezone =/date.timezone = Asia\/Jakarta/' "$INI_PATH" # Set timezone
        
        # Pastikan exec tidak ada di disable_functions
        CURRENT_DISABLED_FUNCTIONS=$(grep -Po '^disable_functions\s*=\s*\K[^\r\n]*' "$INI_PATH")
        if [[ "$CURRENT_DISABLED_FUNCTIONS" == *"exec"* ]]; then
            echo "Peringatan: 'exec' ditemukan di disable_functions di ${INI_PATH}. Mencoba menghapusnya..."
            NEW_DISABLED_FUNCTIONS=$(echo "$CURRENT_DISABLED_FUNCTIONS" | sed -E 's/(^|,)\s*exec\s*(,|$)/\1\2/g' | sed -E 's/,$//; s/^,//')
            sed -i "s/^disable_functions = .*/disable_functions = ${NEW_DISABLED_FUNCTIONS}/" "$INI_PATH"
            echo "disable_functions setelah diubah: ${NEW_DISABLED_FUNCTIONS}"
        else
            echo "'exec' tidak ditemukan di disable_functions di ${INI_PATH}. Bagus."
        fi
        # Pastikan display_errors Off untuk produksi, On untuk development (skrip Anda sudah handle ini)
        # sed -i 's/^display_errors = .*/display_errors = Off/' "$INI_PATH" 
        echo "Parameter php.ini di ${INI_PATH} telah disesuaikan."
    else
        echo "Peringatan: File php.ini tidak ditemukan di ${INI_PATH}. Anda mungkin perlu mengeditnya manual."
    fi
}

configure_php_ini "$PHP_INI_FPM_PATH"
configure_php_ini "$PHP_INI_CLI_PATH"

echo "Me-restart layanan PHP-FPM..."
systemctl restart "php${PHP_VERSION_TARGET}-fpm" || echo "Peringatan: Gagal me-restart php${PHP_VERSION_TARGET}-fpm."

# Restart web server (lagi, untuk memastikan semua config termuat)
if [ "$WEB_SERVER" == "apache" ]; then
    systemctl restart apache2
elif [ "$WEB_SERVER" == "nginx" ]; then
    systemctl restart nginx
fi
echo "--------------------------------------------------"

# Selesai
PUBLIC_IP=$(curl -s https://ifconfig.me/ip || curl -s http://checkip.amazonaws.com || hostname -I | awk '{print $1}')
echo "Setup Selesai!"
echo "================================================================================"
echo " VPS Anda seharusnya sudah siap untuk Aplikasi Streaming PHP dengan PHP ${PHP_VERSION_TARGET}."
echo ""
echo " Langkah Selanjutnya Penting:"
echo " 1. Unggah SEMUA file aplikasi PHP Anda ke direktori: ${APP_PATH}"
echo "    (Gunakan SCP, SFTP, atau Git. Pastikan file .htaccess ada jika diperlukan aplikasi Anda)."
echo " 2. Di dalam ${APP_PATH}, buat struktur direktori yang diperlukan oleh aplikasi Anda:"
echo "    - sudo mkdir -p data/datajson data/rtmp data/secure/service_accounts pid bin/rclone"
echo " 3. Salin binary FFMPEG dan Rclone portabel Anda ke ${APP_PATH}/bin/ (atau ${APP_PATH}/bin/rclone/ untuk rclone)"
echo "    (Anda mungkin perlu mengunduhnya ke server dulu jika belum ada)"
echo "    - sudo cp /path/ke/ffmpeg_binary ${APP_PATH}/bin/ffmpeg"
echo "    - sudo cp /path/ke/rclone_binary ${APP_PATH}/bin/rclone/rclone"
echo " 4. Berikan izin eksekusi pada binary tersebut di server:"
echo "    - sudo chmod +x ${APP_PATH}/bin/ffmpeg"
echo "    - sudo chmod +x ${APP_PATH}/bin/rclone/rclone"
echo " 5. Atur kepemilikan dan izin untuk direktori 'data' agar PHP (user www-data) bisa menulis:"
echo "    - sudo chown -R www-data:www-data ${APP_PATH}/data"
echo "    - sudo chmod -R 775 ${APP_PATH}/data"
echo "    - sudo chmod 750 ${APP_PATH}/data/secure ${APP_PATH}/data/secure/service_accounts"
echo "    - (Jika ada file config.php, dashboard.php, dll. di root APP_PATH, kepemilikannya sudah $(logname):www-data)"
echo " 6. (PENTING) Isi file 'config.php' aplikasi Anda dengan kredensial yang benar (misal DEFAULT_GOOGLE_CLIENT_ID jika pakai OAuth)."
echo " 7. Akses aplikasi Anda melalui IP Address: http://${PUBLIC_IP}"
echo "    (Web server sudah dikonfigurasi untuk melayani dari ${APP_PATH} jika ${APP_DIR_NAME} adalah 'streamingapp')"
echo " 8. Lakukan konfigurasi Rclone (Service Account) melalui antarmuka web aplikasi Anda."
echo ""
echo " Catatan Keamanan:"
echo " - Amankan SSH Anda (key-based auth, ubah port, fail2ban)."
echo " - Pertimbangkan HTTPS dengan SSL (Let's Encrypt) untuk produksi."
echo "================================================================================"

if confirm "Apakah Anda ingin menjalankan 'rclone config' global sekarang? (Ini berbeda dari konfigurasi rclone portabel yang akan dikelola aplikasi Anda)"; then
    echo "Menjalankan 'rclone config'. PENTING: Konfigurasi ini akan disimpan di ~/.config/rclone/rclone.conf untuk user saat ini (root), bukan untuk aplikasi secara langsung."
    rclone config
else
    echo "Setup rclone config global dilewati. Aplikasi akan mengelola konfigurasi rclone-nya sendiri."
fi

echo "Skrip setup telah selesai dijalankan."
