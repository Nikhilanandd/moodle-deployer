#!/bin/bash
# Moodle Deployer - Nginx configuration
# Generates nginx site config from template, enables site, and reloads nginx

find_nginx_bin() {
    local nginx_bin
    nginx_bin="$(find_binary "nginx" 2>/dev/null || true)"
    echo "${nginx_bin}"
}

configure_nginx() {
    local instance_name="$1"
    local install_dir="$2"
    local http_port="$3"
    local server_name="$4"
    local php_version="$5"
    local nginx_available="${6:-/etc/nginx/sites-available}"
    local nginx_enabled="${7:-/etc/nginx/sites-enabled}"

    local nginx_bin
    nginx_bin="$(find_nginx_bin)"

    if [[ -z "${nginx_bin}" ]]; then
        warn "Nginx binary not found. Skipping nginx configuration."
        return 0
    fi

    header "NGINX CONFIGURATION"

    local template="${SCRIPT_DIR}/templates/nginx.conf.tpl"
    local config_file="${nginx_available}/${instance_name}.conf"
    local symlink="${nginx_enabled}/${instance_name}.conf"

    if [[ ! -f "${template}" ]]; then
        error "Nginx template not found: ${template}"
        return 1
    fi

    info "Generating nginx configuration from template"

    local config
    config="$(cat "${template}")"
    config="${config//__PORT__/${http_port}}"
    config="${config//__SERVER_NAME__/${server_name}}"
    config="${config//__MOODLE_DIR__/${install_dir}/moodle}"
    config="${config//__PHP_VERSION__/${php_version}}"

    echo "${config}" > "${config_file}"
    ok "Nginx config created: ${config_file}"

    rollback_add "rm -f '${config_file}'"

    info "Enabling site: ${instance_name}"
    mkdir -p "${nginx_enabled}"
    ln -sf "${config_file}" "${symlink}"
    ok "Site enabled: ${symlink}"

    rollback_add "rm -f '${symlink}'"

    info "Testing nginx configuration"
    if ! "${nginx_bin}" -t 2>&1; then
        error "Nginx configuration test failed."
        return 1
    fi
    ok "Nginx configuration test passed"

    info "Reloading nginx"
    if ! systemctl reload nginx 2>&1; then
        error "Failed to reload nginx."
        return 1
    fi
    ok "Nginx reloaded successfully"
}

disable_nginx_site() {
    local instance_name="$1"
    local nginx_available="${2:-/etc/nginx/sites-available}"
    local nginx_enabled="${3:-/etc/nginx/sites-enabled}"

    local config_file="${nginx_available}/${instance_name}.conf"
    local symlink="${nginx_enabled}/${instance_name}.conf"

    if [[ -L "${symlink}" ]]; then
        info "Disabling nginx site: ${instance_name}"
        rm -f "${symlink}"
    fi

    if [[ -f "${config_file}" ]]; then
        info "Removing nginx config: ${config_file}"
        rm -f "${config_file}"
    fi
}

reload_nginx() {
    local nginx_bin
    nginx_bin="$(find_nginx_bin)"

    if [[ -z "${nginx_bin}" ]]; then
        return 0
    fi

    if "${nginx_bin}" -t 2>&1; then
        systemctl reload nginx 2>/dev/null || true
        ok "Nginx reloaded"
    else
        warn "Nginx configuration test failed. Reload skipped."
    fi
}
