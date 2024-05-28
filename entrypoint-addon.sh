#!/usr/bin/env bash
set -Eeuo pipefail

echo "Running standard entrypoint to populate wp-config.php"
docker-entrypoint.sh apache2 -l

# Ensure wordpress core database is installed
if ! wp  --path=/usr/src/wordpress core is-installed; then
  wp --path=/usr/src/wordpress core install --url=http://localhost:8080 --title="Wordpress" --admin_user="osm_admin" --admin_email="osm_admin@openstreetmap.org" --skip-email
fi

# Ensure wordpress core database is up to date
wp --path=/usr/src/wordpress core update-db

# Activate all plugins
wp --path=/usr/src/wordpress plugin activate --all

exec "$@"