# syntax=docker/dockerfile:1

# Stage 1: PHP Extension Builder
FROM docker.io/library/wordpress:apache AS php-ext-builder

# Install build dependencies for PHP extensions
RUN apt-get update && apt-get install -y --no-install-recommends \
    libonig-dev \
    libxml2-dev \
    && rm -rf /var/lib/apt/lists/*

# Build and install PHP extensions
RUN docker-php-ext-install -j "$(nproc)" \
    mbstring \
    xml \
    && pecl install igbinary \
    && docker-php-ext-enable igbinary

# Verify extensions work properly
RUN set -eux; \
    out="$(php -r 'exit(0);')"; \
    [ -z "$out" ]; \
    err="$(php -r 'exit(0);' 3>&1 1>&2 2>&3)"; \
    [ -z "$err" ]; \
    php --version

# Stage 2: Composer Stage
FROM docker.io/library/composer:2 AS composer-stage

# Stage 3: WordPress CLI
FROM docker.io/library/wordpress:cli AS cli

# Stage 4: WordPress Customizer
FROM docker.io/library/wordpress:apache AS wordpress-customizer

# Copy Composer binary
COPY --from=composer-stage /usr/bin/composer /usr/local/bin/composer

# Set up WordPress directory structure
WORKDIR /usr/src/wordpress
RUN set -eux; \
    find /etc/apache2 -name '*.conf' -type f -exec sed -ri -e "s!/var/www/html!$PWD!g" -e "s!Directory /var/www/!Directory $PWD!g" '{}' +; \
    cp -s wp-config-docker.php wp-config.php

# Copy composer.json and install plugins
COPY composer.json composer.json
RUN composer install --no-dev --optimize-autoloader --no-interaction

# Remove hello plugin
RUN rm -rf wp-content/plugins/hello.php

# Stage 5: Final Runtime Image
FROM docker.io/library/wordpress:apache

# Create non-privileged user early for security
RUN groupadd --system wordpress \
    && useradd --system --gid wordpress --no-create-home --home /nonexistent --comment "wordpress user" --shell /bin/false wordpress

# Copy PHP extensions from builder
COPY --from=php-ext-builder /usr/local/lib/php/extensions/ /usr/local/lib/php/extensions/
COPY --from=php-ext-builder /usr/local/etc/php/conf.d/ /usr/local/etc/php/conf.d/

# Copy WordPress CLI from stage 3
COPY --from=cli /usr/local/bin/wp /usr/local/bin/wp

# Install only runtime dependencies
RUN apt-get update && apt-get install -y --no-install-recommends \
    # Required for mbstring extension
    libonig5 \
    # Required for xml extension
    libxml2 \
    # Required for wp-cli
    jq \
    && rm -rf /var/lib/apt/lists/*

# Copy customized WordPress from customizer stage
COPY --from=wordpress-customizer /usr/src/wordpress /usr/src/wordpress
COPY --from=wordpress-customizer /etc/apache2 /etc/apache2

# Set working directory
WORKDIR /usr/src/wordpress

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