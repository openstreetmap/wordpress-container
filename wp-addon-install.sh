#!/usr/bin/env bash
set -Eeuo pipefail

curl -Lsg 'https://api.wordpress.org/plugins/info/1.1/?action=plugin_information&request[slug]=wp-fail2ban' | jq -r .download_link
# wp-last-login
# wp-2fa
# wp-fail2ban
