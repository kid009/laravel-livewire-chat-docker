# -----------------------------------------------------------------------------
# Base Image
# -----------------------------------------------------------------------------
# PHP 8.3 FPM สำหรับ Laravel + Livewire + Reverb
# ใช้ tag 8.3-fpm เพื่อให้ได้ security patch ล่าสุด
FROM php:8.3-fpm

# -----------------------------------------------------------------------------
# Build Arguments
# -----------------------------------------------------------------------------
# UID/GID ให้ตรงกับ host user เพื่อป้องกัน permission denied ตอน mount volume
# บน Linux/WSL/macOS ให้ส่งค่าจาก docker-compose.yml ผ่าน ${UID}/${GID}
# บน Windows สามารถปล่อย default 1000 ได้
ARG UID=1000
ARG GID=1000

# เลือก php.ini ที่จะใช้: php.ini-development (default สำหรับ dev) หรือ php.ini-production
ARG PHP_INI=php.ini-development

# -----------------------------------------------------------------------------
# Working Directory
# -----------------------------------------------------------------------------
WORKDIR /var/www

# -----------------------------------------------------------------------------
# System Dependencies & PHP Extensions
# -----------------------------------------------------------------------------
# ติดตั้ง OS packages และไลบรารีที่จำเป็นสำหรับ Extensions ต่างๆ
RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates \
    curl \
    git \
    unzip \
    zip \
    libzip-dev \
    libpng-dev \
    libjpeg-dev \
    libfreetype6-dev \
    libicu-dev \
    # ตั้งค่า GD ให้รองรับ JPEG และ FreeType
    && docker-php-ext-configure gd --with-freetype --with-jpeg \
    # ติดตั้ง PHP extensions หลักสำหรับ Laravel, Reverb (pcntl, sockets) และจัดการรูป/ภาษา
    && docker-php-ext-install -j$(nproc) \
        bcmath \
        exif \
        gd \
        intl \
        opcache \
        pcntl \
        pdo_mysql \
        sockets \
        zip \
    # ติดตั้ง Redis extension สำหรับ Queue / Cache / Broadcast
    && pecl install redis \
    && docker-php-ext-enable redis \
    # ล้าง Cache เพื่อลดขนาด Image
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/* /tmp/pear

# -----------------------------------------------------------------------------
# Node.js 22 LTS
# -----------------------------------------------------------------------------
# ลง Node.js ไว้ใน image เดียวกันเพื่อความสะดวกในการรัน npm install / npm run build
RUN curl -fsSL https://deb.nodesource.com/setup_22.x | bash - \
    && apt-get install -y --no-install-recommends nodejs \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# -----------------------------------------------------------------------------
# Composer 2
# -----------------------------------------------------------------------------
COPY --from=composer:2 /usr/bin/composer /usr/bin/composer

# -----------------------------------------------------------------------------
# PHP Configuration
# -----------------------------------------------------------------------------
# คัดลอก php.ini ตาม ARG ที่ระบุ (development สำหรับ dev, production สำหรับ prod)
# ตัวอย่าง build สำหรับ production: docker build --build-arg PHP_INI=php.ini-production .
RUN cp /usr/local/etc/php/${PHP_INI} /usr/local/etc/php/php.ini

# คัดลอกไฟล์คอนฟิกเพิ่มเติม (upload size, memory limit, execution time)
# สามารถ override ได้อีกทีผ่าน docker-compose volume mount ถ้าต้องการปรับระหว่าง dev
COPY docker/php/local.ini /usr/local/etc/php/conf.d/99-local.ini

# -----------------------------------------------------------------------------
# User, Permission & Cache Directories
# -----------------------------------------------------------------------------
# ปรับ UID/GID ของ www-data ให้ตรงกับ host user
# หาก UID/GID ซ้ำกับ user/group อื่นใน image จะถูกย้ายไปก่อนเพื่อหลีกเลี่ยง conflict
# หมายเหตุ: ไม่ควรใช้ UID/GID ต่ำกว่า 1000 (เช่น 0=root) เพราะอาจทำลายระบบใน image
RUN set -eux \
    && if getent group ${GID} >/dev/null 2>&1; then \
           existing_group=$(getent group ${GID} | cut -d: -f1); \
           if [ "$existing_group" != "www-data" ]; then \
               groupmod -o -g 99999 "$existing_group"; \
           fi; \
       fi \
    && groupmod -o -g ${GID} www-data \
    && if getent passwd ${UID} >/dev/null 2>&1; then \
           existing_user=$(getent passwd ${UID} | cut -d: -f1); \
           if [ "$existing_user" != "www-data" ]; then \
               usermod -o -u 99999 "$existing_user"; \
           fi; \
       fi \
    && usermod -o -u ${UID} www-data \
    && mkdir -p /var/www /home/www-data/.composer /home/www-data/.npm \
    && chown -R www-data:www-data /var/www /home/www-data

# สลับไปใช้ non-root user
USER www-data

# 9000: PHP-FPM (Nginx เชื่อมต่อ)
# 5173: Vite Dev Server (ใช้กรณีรัน npm run dev ในคอนเทนเนอร์นี้)
EXPOSE 9000 5173

CMD ["php-fpm"]
