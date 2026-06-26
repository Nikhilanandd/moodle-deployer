#!/bin/bash
# Moodle Deployer - Pre-flight validation
# Validates all prerequisites before deployment begins

check_root() {
    if [[ "$(id -u)" -ne 0 ]]; then
        error "This script must be run as root."
        return 1
    fi
    ok "Running as root"
}

check_command() {
    local cmd="$1"
    local name="${2:-${cmd}}"
    if ! command -v "${cmd}" &>/dev/null; then
        error "${name} is not installed."
        return 1
    fi
    ok "${name} found: $(command -v "${cmd}")"
}

check_service() {
    local service="$1"
    local name="${2:-${service}}"
    if ! systemctl is-active --quiet "${service}" 2>/dev/null; then
        error "${name} service is not running."
        return 1
    fi
    ok "${name} service is active"
}

check_php_version() {
    local required_version="$1"
    local installed_version
    installed_version="$(php -r 'echo PHP_MAJOR_VERSION.".".PHP_MINOR_VERSION;' 2>/dev/null || true)"
    if [[ -z "${installed_version}" ]]; then
        error "Could not determine PHP version."
        return 1
    fi
    if [[ "${installed_version}" != "${required_version}" ]]; then
        warn "PHP ${installed_version} installed, ${required_version} requested. Will use PHP-FPM ${required_version}."
    else
        ok "PHP ${installed_version} version matches requirement"
    fi
}

check_phpfpm_pool() {
    local php_version="$1"
    local pool_sock="/run/php/php${php_version}-fpm.sock"
    if [[ ! -S "${pool_sock}" ]]; then
        error "PHP-FPM socket not found: ${pool_sock}"
        error "Ensure php${php_version}-fpm is installed and running."
        return 1
    fi
    ok "PHP-FPM ${php_version} socket found"
}

check_disk_space() {
    local path="$1"
    local required_mb="${2:-1024}"
    local available_mb
    available_mb="$(df -m "${path}" 2>/dev/null | awk 'NR==2 {print $4}')"
    if [[ -z "${available_mb}" ]] || [[ "${available_mb}" -lt "${required_mb}" ]]; then
        error "Insufficient disk space at ${path}. Required: ${required_mb}MB, Available: ${available_mb:-0}MB."
        return 1
    fi
    ok "Disk space sufficient: ${available_mb}MB available at ${path}"
}

check_port_free() {
    local port="$1"
    if ss -tlnp 2>/dev/null | grep -q ":${port} "; then
        error "Port ${port} is already in use."
        ss -tlnp 2>/dev/null | grep ":${port} " || true
        return 1
    fi
    ok "Port ${port} is available"
}

check_directory_not_exists() {
    local dir="$1"
    if [[ -d "${dir}" ]]; then
        error "Directory already exists: ${dir}"
        return 1
    fi
    ok "Directory does not exist: ${dir}"
}

check_database_not_exists() {
    local db_name="$1"
    if mysql -e "SELECT SCHEMA_NAME FROM INFORMATION_SCHEMA.SCHEMATA WHERE SCHEMA_NAME = '${db_name}';" 2>/dev/null | grep -q "${db_name}"; then
        error "Database '${db_name}' already exists."
        return 1
    fi
    ok "Database '${db_name}' does not exist"
}

check_nginx_config_not_exists() {
    local config_path="$1"
    if [[ -f "${config_path}" ]]; then
        error "Nginx config already exists: ${config_path}"
        return 1
    fi
    ok "Nginx config does not exist: ${config_path}"
}

check_backup_exists() {
    local path="$1"
    local label="$2"
    if [[ -z "${path}" ]]; then
        error "No backup file found for ${label}."
        return 1
    fi
    if [[ ! -f "${path}" ]]; then
        error "Backup file not found: ${path}"
        return 1
    fi
    if [[ ! -r "${path}" ]]; then
        error "Backup file not readable: ${path}"
        return 1
    fi
    ok "${label} backup found: $(basename "${path}") ($(du -h "${path}" | cut -f1))"
}

validate_all() {
    local instance_name="$1"
    local install_dir="$2"
    local http_port="$3"
    local php_version="$4"
    local db_name="$5"
    local code_backup="$6"
    local db_backup="$7"
    local moodledata_backup="$8"

    header "PRE-FLIGHT CHECKS"

    check_root || return 1
    check_command "php" "PHP CLI" || return 1
    check_php_version "${php_version}" || return 1
    check_command "mysql" "MariaDB client" || return 1
    check_command "nginx" "Nginx" || return 1
    check_service "mariadb" "MariaDB" || return 1
    check_service "php${php_version}-fpm" "PHP-FPM ${php_version}" || return 1
    check_service "nginx" "Nginx" || return 1
    check_phpfpm_pool "${php_version}" || return 1
    check_disk_space "${install_dir}" 2048 || return 1
    check_port_free "${http_port}" || return 1
    check_directory_not_exists "${install_dir}" || return 1
    check_database_not_exists "${db_name}" || return 1
    check_nginx_config_not_exists "/etc/nginx/sites-available/${instance_name}.conf" || return 1

    if [[ -n "${code_backup}" ]]; then
        check_backup_exists "${code_backup}" "Code" || return 1
    fi
    if [[ -n "${db_backup}" ]]; then
        check_backup_exists "${db_backup}" "Database" || return 1
    fi
    if [[ -n "${moodledata_backup}" ]]; then
        check_backup_exists "${moodledata_backup}" "Moodledata" || return 1
    fi

    echo ""
    ok "All pre-flight checks passed"
    return 0
}
