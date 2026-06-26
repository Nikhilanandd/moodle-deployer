#!/bin/bash
# Moodle Deployer - PHP configuration
# Creates Moodle-specific PHP-FPM ini file and restarts PHP-FPM

PHP_CONF_D="/etc/php"  # Base path, version will be appended

configure_php() {
    local php_version="$1"

    header "PHP CONFIGURATION"

    local template="${SCRIPT_DIR}/templates/php.ini.tpl"
    local conf_dir="${PHP_CONF_D}/${php_version}/fpm/conf.d"
    local conf_file="${conf_dir}/99-moodle.ini"

    if [[ ! -f "${template}" ]]; then
        error "PHP template not found: ${template}"
        return 1
    fi

    if [[ ! -d "${conf_dir}" ]]; then
        error "PHP-FPM conf.d directory not found: ${conf_dir}"
        error "Is php${php_version}-fpm installed?"
        return 1
    fi

    info "Copying Moodle PHP configuration to ${conf_file}"
    cp "${template}" "${conf_file}"
    chmod 644 "${conf_file}"
    ok "PHP configuration created: ${conf_file}"

    rollback_add "rm -f '${conf_file}'"

    info "Restarting PHP-FPM ${php_version}"
    if ! systemctl restart "php${php_version}-fpm" 2>&1; then
        error "Failed to restart PHP-FPM ${php_version}."
        return 1
    fi
    ok "PHP-FPM ${php_version} restarted successfully"
}

remove_php_config() {
    local php_version="$1"
    local conf_file="${PHP_CONF_D}/${php_version}/fpm/conf.d/99-moodle.ini"

    if [[ -f "${conf_file}" ]]; then
        info "Removing Moodle PHP configuration"
        rm -f "${conf_file}"
        systemctl restart "php${php_version}-fpm" 2>/dev/null || true
        ok "PHP-FPM ${php_version} restarted after config removal"
    fi
}
