#!/bin/bash
# Moodle Deployer - Pre-flight validation
# Validates all prerequisites before deployment begins

# Common system binary paths (for tools not in root's PATH)
SYSTEM_PATHS=(
    /usr/local/sbin /usr/local/bin /usr/sbin /usr/bin /sbin /bin
)

find_binary() {
    local cmd="$1"
    local found

    found="$(command -v "${cmd}" 2>/dev/null || true)"
    if [[ -n "${found}" ]]; then
        echo "${found}"
        return 0
    fi

    local p
    for p in "${SYSTEM_PATHS[@]}"; do
        if [[ -x "${p}/${cmd}" ]]; then
            echo "${p}/${cmd}"
            return 0
        fi
    done

    echo ""
    return 1
}

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
    local found

    found="$(find_binary "${cmd}")"
    if [[ -z "${found}" ]]; then
        error "${name} is not installed or not found in PATH."
        return 1
    fi
    ok "${name} found: ${found}"
}

check_service() {
    local service="$1"
    local name="${2:-${service}}"

    if ! systemctl is-active --quiet "${service}" 2>/dev/null; then
        warn "${name} service is not running."
        return 1
    fi
    ok "${name} service is active"
}

check_service_exists() {
    local service="$1"
    if systemctl list-unit-files "${service}.service" &>/dev/null; then
        return 0
    fi
    return 1
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
    local socket_path="${2:-/run/php/php${php_version}-fpm.sock}"

    if [[ ! -S "${socket_path}" ]]; then
        warn "PHP-FPM socket not found: ${socket_path}"
        warn "Ensure php${php_version}-fpm is installed and running."
        return 1
    fi
    ok "PHP-FPM ${php_version} socket found: ${socket_path}"
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

check_nginx_installed() {
    local nginx_bin
    nginx_bin="$(find_binary "nginx")"
    if [[ -z "${nginx_bin}" ]]; then
        warn "Nginx binary not found. Web server config will be skipped."
        return 1
    fi
    ok "Nginx binary found: ${nginx_bin}"
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
    local nginx_config_path="$9"

    header "PRE-FLIGHT CHECKS"

    local errors=0
    local warnings=0

    check_root || ((errors++))
    check_command "php" "PHP CLI" || ((errors++))
    check_php_version "${php_version}" || true
    check_command "mysql" "MariaDB client" || ((errors++))
    check_service "mariadb" "MariaDB" || ((errors++))
    check_disk_space "${install_dir}" 2048 || ((errors++))
    check_port_free "${http_port}" || ((errors++))
    check_directory_not_exists "${install_dir}" || ((errors++))
    check_database_not_exists "${db_name}" || ((errors++))
    check_nginx_config_not_exists "${nginx_config_path}" || ((errors++))

    # Non-fatal: nginx optional
    if check_nginx_installed; then
        check_service "nginx" "Nginx" || ((warnings++))
    else
        ((warnings++))
    fi

    # Non-fatal: PHP-FPM
    check_service "php${php_version}-fpm" "PHP-FPM ${php_version}" || ((warnings++))
    check_phpfpm_pool "${php_version}" || ((warnings++))

    if [[ -n "${code_backup}" ]]; then
        check_backup_exists "${code_backup}" "Code" || ((errors++))
    fi
    if [[ -n "${db_backup}" ]]; then
        check_backup_exists "${db_backup}" "Database" || ((errors++))
    fi
    if [[ -n "${moodledata_backup}" ]]; then
        check_backup_exists "${moodledata_backup}" "Moodledata" || ((errors++))
    fi

    echo ""

    if [[ ${errors} -gt 0 ]]; then
        error "${errors} critical check(s) failed. Aborting."
        return 1
    fi

    if [[ ${warnings} -gt 0 ]]; then
        warn "${warnings} warning(s) found (non-critical)."
        if ! confirm "Continue despite warnings?" "y"; then
            error "Aborted by user."
            return 1
        fi
    fi

    ok "All pre-flight checks passed"
    return 0
}
