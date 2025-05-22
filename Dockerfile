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

# Stage 2: WordPress CLI
FROM docker.io/library/wordpress:cli AS cli

# Stage 3: WordPress Customizer
FROM docker.io/library/wordpress:apache AS wordpress-customizer

# Copy WordPress CLI binary
COPY --from=cli /usr/local/bin/wp /usr/local/bin/wp

# Install runtime tools needed for customization
RUN apt-get update && apt-get install -y --no-install-recommends \
    jq \
    unzip \
    && rm -rf /var/lib/apt/lists/*

# Set up WordPress directory structure
WORKDIR /usr/src/wordpress
RUN set -eux; \
    find /etc/apache2 -name '*.conf' -type f -exec sed -ri -e "s!/var/www/html!$PWD!g" -e "s!Directory /var/www/!Directory $PWD!g" '{}' +; \
    cp -s wp-config-docker.php wp-config.php

# Install themes and plugins
COPY wp-addon-install.sh /usr/local/bin/
RUN chmod +x /usr/local/bin/wp-addon-install.sh \
    && /usr/local/bin/wp-addon-install.sh

# Stage 4: Final Runtime Image
FROM docker.io/library/wordpress:apache

# Create non-privileged user early for security
RUN groupadd --system wordpress \
    && useradd --system --gid wordpress --no-create-home --home /nonexistent --comment "wordpress user" --shell /bin/false wordpress

# Copy PHP extensions from builder
COPY --from=php-ext-builder /usr/local/lib/php/extensions/ /usr/local/lib/php/extensions/
COPY --from=php-ext-builder /usr/local/etc/php/conf.d/ /usr/local/etc/php/conf.d/

# Copy WordPress CLI from stage 2
COPY --from=cli /usr/local/bin/wp /usr/local/bin/wp

# Install only runtime dependencies
RUN apt-get update && apt-get install -y --no-install-recommends \
    # Required for mbstring extension
    libonig5 \
    # Required for xml extension
    libxml2 \
    # Required for wp-cli and entrypoint operations
    jq \
    unzip \
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

# WordPress configuration comments for reference
# define( 'WP_HOME', 'https://#{new_resource.site}');
# define( 'WP_SITEURL', 'https://#{new_resource.site}');
# define( 'DISALLOW_FILE_EDIT', true);
# define( 'DISALLOW_FILE_MODS', true);
# define( 'AUTOMATIC_UPDATER_DISABLED', true);
# define( 'FORCE_SSL_LOGIN', true);
# define( 'FORCE_SSL_ADMIN', true);
# define( 'WP_FAIL2BAN_SITE_HEALTH_SKIP_FILTERS', true);
# define( 'WP_ENVIRONMENT_TYPE', 'production');
# define( 'WP_MEMORY_LIMIT', '128M');
# define( 'WP2FA_ENCRYPT_KEY', '#{new_resource.wp2fa_encrypt_key}');

# Volume mount points
# TMPFS /tmp
# TMPFS /run
# Persistent /usr/src/wordpress/wp-content/uploads (wordpress:wordpress)

ENTRYPOINT ["entrypoint-addon.sh"]
CMD ["apache2-foreground"]