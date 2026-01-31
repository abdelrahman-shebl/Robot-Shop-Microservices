# Stage 1: Vendor
FROM composer:2.7 AS vendor

WORKDIR /app

#  FIX 1: Copy from 'html/' folder, and ONLY copy composer.json (no lock file)
COPY html/composer.json ./

#  FIX 2: Install dependencies (This generates the missing lock file automatically)
RUN composer install \
    --no-dev \
    --no-scripts \
    --no-progress \
    --prefer-dist \
    --ignore-platform-reqs

# ---

# Stage 2: Final Image
FROM php:8.2-apache

RUN apt-get update && apt-get install -yqq --no-install-recommends \
    unzip \
    libzip-dev \
    && docker-php-ext-install pdo_mysql opcache zip \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

RUN mv "$PHP_INI_DIR/php.ini-production" "$PHP_INI_DIR/php.ini" \
    && echo "instana.enable_auto_profile=1" > "/usr/local/etc/php/conf.d/zzz-instana-extras.ini"

# Create non-root user with specific UID/GID
RUN groupadd -g 2000 appuser && useradd -u 1000 -g appuser appuser

COPY status.conf /etc/apache2/mods-available/status.conf
RUN a2enmod rewrite && a2enmod status

WORKDIR /var/www/html

# Copy the vendor folder we just built in Stage 1
COPY --from=vendor /app/vendor/ /var/www/html/vendor/

# Copy the rest of your source code
COPY html/ /var/www/html/

RUN mkdir -p /var/www/html/var \
    && chown -R appuser:appuser /var/www/html \
    && chmod -R 775 /var/www/html/var

EXPOSE 80

# Configure Apache to run as appuser
RUN sed -i 's/www-data/appuser/g' /etc/apache2/envvars

USER appuser

CMD ["apache2-foreground"]