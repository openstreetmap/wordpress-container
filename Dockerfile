# syntax=docker/dockerfile:1

# Stage 1: PHP Extension Builder
FROM docker.io/library/wordpress:apache AS php-ext-builder

# Install build dependencies for PHP extensions
RUN <<EOF
apt-get update
apt-get install -y --no-install-recommends \
    libonig-dev \
    libxml2-dev
rm -rf /var/lib/apt/lists/*
rm -rf /var/cache/apt/archives
rm -f /var/log/apt/* /var/log/dpkg.log /var/log/alternatives.log
EOF

# Build and install PHP extensions
RUN <<EOF
docker-php-ext-install -j "$(nproc)" \
    mbstring \
    xml
pecl install igbinary
docker-php-ext-enable igbinary
EOF

# Verify extensions work properly
RUN <<EOF
set -eux
out="$(php -r 'exit(0);')"
[ -z "$out" ]
err="$(php -r 'exit(0);' 3>&1 1>&2 2>&3)"
[ -z "$err" ]
php --version
EOF

# Stage 2: Composer Stage
FROM docker.io/library/composer:2 AS composer-stage

# Stage 3: WordPress CLI
FROM docker.io/library/wordpress:cli AS cli

# Stage 4: Final Runtime Image
FROM docker.io/library/wordpress:apache

# Create non-privileged user early for security
RUN <<EOF
groupadd --system wordpress
useradd --system --gid wordpress --no-create-home --home /nonexistent --comment "wordpress user" --shell /bin/false wordpress
EOF

# Copy PHP extensions from builder
COPY --from=php-ext-builder /usr/local/lib/php/extensions/ /usr/local/lib/php/extensions/
COPY --from=php-ext-builder /usr/local/etc/php/conf.d/ /usr/local/etc/php/conf.d/

# Copy WordPress CLI from stage 3
COPY --from=cli /usr/local/bin/wp /usr/local/bin/wp

# Copy Composer binary
COPY --from=composer-stage /usr/bin/composer /usr/local/bin/composer

# Install only runtime dependencies
RUN <<EOF
apt-get update
apt-get install -y --no-install-recommends \
    libonig5 \
    libxml2 \
    jq
rm -rf /var/lib/apt/lists/*
rm -rf /var/cache/apt/archives
rm -f /var/log/apt/* /var/log/dpkg.log /var/log/alternatives.log
EOF

# Set working directory
WORKDIR /usr/src/wordpress

# Set up WordPress directory structure
RUN <<EOF
set -eux
find /etc/apache2 -name '*.conf' -type f -exec sed -ri -e "s!/var/www/html!$PWD!g" -e "s!Directory /var/www/!Directory $PWD!g" '{}' +
cp -s wp-config-docker.php wp-config.php
EOF

# Copy composer.json and install plugins
COPY composer.json composer.json
RUN composer install --no-dev --optimize-autoloader --no-interaction

# Remove hello plugin
RUN rm -rf wp-content/plugins/hello.php

# Copy and set up custom entrypoint
COPY entrypoint-addon.sh /usr/local/bin/
RUN chmod +x /usr/local/bin/entrypoint-addon.sh

# Configure Apache to run as wordpress user
ENV APACHE_RUN_USER=wordpress \
    APACHE_RUN_GROUP=wordpress

# Switch to non-privileged user
USER wordpress

ENTRYPOINT ["entrypoint-addon.sh"]
CMD ["apache2-foreground"]