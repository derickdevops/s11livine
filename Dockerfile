# Use PHP 8.2 FPM Alpine as base
FROM php:8.2-fpm-alpine AS base

LABEL maintainer="Webforx Technology Limited"

WORKDIR /var/www/connect-backend

ENV DEBIAN_FRONTEND=noninteractive
ENV TZ=UTC

# Set timezone
RUN apk add --no-cache tzdata \
    && cp /usr/share/zoneinfo/$TZ /etc/localtime \
    && echo $TZ > /etc/timezone

# Install runtime deps + build deps in one layer, compile PHP extensions, then remove build deps
RUN apk add --no-cache \
        bash curl wget git vim unzip nginx supervisor nodejs npm sqlite ffmpeg dos2unix python3 bash-completion \
        libpng librsvg freetype libjpeg-turbo libwebp icu-libs zlib libzip libxml2 libmemcached cyrus-sasl \
    && apk add --no-cache --virtual .build-deps \
        autoconf gcc g++ make pkgconf linux-headers \
        zlib-dev libpng-dev libjpeg-turbo-dev freetype-dev libwebp-dev icu-dev libzip-dev libxml2-dev \
        libmemcached-dev cyrus-sasl-dev \
    && docker-php-ext-configure gd --with-freetype --with-jpeg --with-webp \
    && docker-php-ext-install mysqli pdo pdo_mysql gd intl bcmath soap zip opcache \
    && pecl install redis swoole xdebug igbinary msgpack memcached \
    && docker-php-ext-enable redis swoole xdebug igbinary msgpack memcached \
    && apk del .build-deps \
    && rm -rf /var/cache/apk/* /tmp/pear

# Install Composer and clear cache
RUN curl -sS https://getcomposer.org/installer | php -- --install-dir=/usr/bin/ --filename=composer \
    && composer clear-cache

# Install Yarn, Bun, PNPM and clean NPM cache
RUN npm install -g yarn bun pnpm \
    && npm cache clean --force

# PHP-FPM socket
RUN mkdir -p /var/www/connect-backend/php \
    && sed -i 's|listen = 9000|listen = /var/www/connect-backend/php/php8.2-fpm.sock|' /usr/local/etc/php-fpm.d/www.conf

# Copy application and Nginx configuration
COPY . .
RUN mkdir -p /etc/nginx/sites-available /etc/nginx/sites-enabled \
    && cp -r nginx/default /etc/nginx/sites-available/default \
    && cp -r nginx/start.sh .

# Setup Laravel cron
COPY laravel-cron /etc/cron.d/laravel-cron
RUN dos2unix /etc/cron.d/laravel-cron \
    && chmod 0644 /etc/cron.d/laravel-cron \
    && crontab /etc/cron.d/laravel-cron \
    && touch /var/log/laravel_scheduler.log

# Copy Supervisor config
COPY supervisord.conf /etc/supervisor/conf.d/supervisord.conf

# Set permissions
RUN chown -R www-data:www-data * \
    && ln -sf /etc/nginx/sites-available/default /etc/nginx/sites-enabled/

# Remove docs, locales and caches to reduce image size
RUN rm -rf /usr/share/doc /usr/share/man /usr/share/locale

# Expose ports
EXPOSE 80 443

# Start Supervisor
CMD ["bugs", "-n", "-c", "/etc/supervisor/conf.d/supervisord.conf"]


