FROM docker.io/library/wordpress:cli as cli

FROM docker.io/library/wordpress:apache

COPY --from=cli /usr/local/bin/wp /usr/local/bin/wp

RUN set -ex; \
        \
        savedAptMark="$(apt-mark showmanual)"; \
        \
        apt-get update; \
        apt-get install -y --no-install-recommends \
          libonig-dev \
          libxml2-dev; \
        \
        docker-php-ext-install -j "$(nproc)" \
        mbstring \
        xml; \
        \
        # some misbehaving extensions end up outputting to stdout 🙈 (https://github.com/docker-library/wordpress/issues/669#issuecomment-993945967)
        out="$(php -r 'exit(0);')"; \
        [ -z "$out" ]; \
        err="$(php -r 'exit(0);' 3>&1 1>&2 2>&3)"; \
        [ -z "$err" ]; \
        \
        extDir="$(php -r 'echo ini_get("extension_dir");')"; \
        [ -d "$extDir" ]; \
        # reset apt-mark's "manual" list so that "purge --auto-remove" will remove all build dependencies
        apt-mark auto '.*' > /dev/null; \
        apt-mark manual $savedAptMark; \
        ldd "$extDir"/*.so \
          | awk '/=>/ { so = $(NF-1); if (index(so, "/usr/local/") == 1) { next }; gsub("^/(usr/)?", "", so); printf "*%s\n", so }' \
          | sort -u \
          | xargs -r dpkg-query --search \
          | cut -d: -f1 \
          | sort -u \
          | xargs -rt apt-mark manual; \
        \
        apt-get purge -y --auto-remove -o APT::AutoRemove::RecommendsImportant=false; \
        rm -rf /var/lib/apt/lists/*; \
        \
        ! { ldd "$extDir"/*.so | grep 'not found'; }; \
        # check for output like "PHP Warning:  PHP Startup: Unable to load dynamic library 'foo' (tried: ...)
        err="$(php --version 3>&1 1>&2 2>&3)"; \
        [ -z "$err" ]

RUN set -ex; \
      pecl install igbinary; \
      docker-php-ext-enable igbinary

# Add persistent dependencies
RUN set -eux; \
	apt-get update; \
	apt-get install -y --no-install-recommends \
		jq \
        unzip \
	; \
	rm -rf /var/lib/apt/lists/*

# "define( 'WP_HOME', 'https://#{new_resource.site}');
# "define( 'WP_SITEURL', 'https://#{new_resource.site}');
# line += "define( 'DISALLOW_FILE_EDIT', true);\r\n"
# line += "define( 'DISALLOW_FILE_MODS', true);\r\n"
# line += "define( 'AUTOMATIC_UPDATER_DISABLED', true);\r\n"
# line += "define( 'FORCE_SSL_LOGIN', true);\r\n"
# line += "define( 'FORCE_SSL_ADMIN', true);\r\n"
# line += "define( 'WP_FAIL2BAN_SITE_HEALTH_SKIP_FILTERS', true);\r\n"
# line += "define( 'WP_ENVIRONMENT_TYPE', 'production');\r\n"
# line += "define( 'WP_MEMORY_LIMIT', '128M');\r\n"
# line += "define( 'WP2FA_ENCRYPT_KEY', '#{new_resource.wp2fa_encrypt_key}');\r\n"


WORKDIR /usr/src/wordpress
RUN set -eux; \
        find /etc/apache2 -name '*.conf' -type f -exec sed -ri -e "s!/var/www/html!$PWD!g" -e "s!Directory /var/www/!Directory $PWD!g" '{}' +; \
	    cp -s wp-config-docker.php wp-config.php

# Add custom themes and plugins
COPY wp-addon-install.sh /usr/local/bin/
RUN set -ex; \
        chmod +x /usr/local/bin/wp-addon-install.sh; \
        /usr/local/bin/wp-addon-install.sh

# TMPFS /tmp
# TMPFS /run
# Persistent /usr/src/wordpress/wp-content/uploads (wordpress:wordpress)

# Add custom entrypoint to enable plugins/themes and run migrations during container startup
COPY entrypoint-addon.sh /usr/local/bin/
# Ensure compatibility with checkout on windows where execute bit not supported
RUN chmod +x /usr/local/bin/wp-addon-install.sh

# Add underprivileged runtime user
RUN set -ex; \
      groupadd --system wordpress; \
      useradd --system --gid wordpress --no-create-home --home /nonexistent --comment "wordpress user" --shell /bin/false wordpress

# Use the underprivileged runtime user
USER wordpress

ENV APACHE_RUN_USER=wordpress \
    APACHE_RUN_GROUP=wordpress

ENTRYPOINT ["entrypoint-addon.sh"]
CMD ["apache2-foreground"]
