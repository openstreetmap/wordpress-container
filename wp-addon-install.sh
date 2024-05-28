#!/usr/bin/env bash
set -Eeuo pipefail

install_wordpress_addon() {
    local type=$1
    local slug=$2

    if [[ "$type" != "plugin" && "$type" != "theme" ]]; then
        echo "Invalid type. Use 'plugin' or 'theme'."
        return 1
    fi

    local api_url="https://api.wordpress.org/${type}s/info/1.2/?action=${type}_information&request[slug]=${slug}"
    local download_link=$(curl -Lsg "$api_url" | jq -r '.download_link')

    if [[ -z "$download_link" || "$download_link" == "null" ]]; then
        echo "Invalid slug or no download link found."
        return 1
    fi

    local target_dir="/usr/src/wordpress/wp-content/${type}s"
    mkdir -p "$target_dir"

    curl -L "$download_link" -o "/tmp/${slug}.zip"
    unzip -q "/tmp/${slug}.zip" -d "$target_dir"
    rm "/tmp/${slug}.zip"

    echo "${type^} '${slug}' installed successfully to ${target_dir}."
}

remove_wordpress_addon() {
    local type=$1
    local slug=$2

    if [[ "$type" != "plugin" && "$type" != "theme" ]]; then
        echo "Invalid type. Use 'plugin' or 'theme'."
        return 1
    fi

    rm -Rf "/usr/src/wordpress/wp-content/${type}s/${slug}"

    echo "${type^} '${slug}' removed successfully."
}

install_wordpress_addon plugin wp-last-login
install_wordpress_addon plugin wp-2fa
install_wordpress_addon plugin wp-fail2ban
remove_wordpress_addon plugin hello.php