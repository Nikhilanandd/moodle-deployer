#!/bin/bash
#===============================================================================
# Moodle Deployer - Instance uninstaller
# Safely removes a Moodle instance deployed by deploy-moodle.sh
#
# Usage: sudo ./uninstall-instance.sh
#===============================================================================

set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

source "${SCRIPT_DIR}/lib/colors.sh"
source "${SCRIPT_DIR}/lib/logging.sh"
source "${SCRIPT_DIR}/lib/validation.sh"
source "${SCRIPT_DIR}/lib/database.sh"
source "${SCRIPT_DIR}/lib/nginx.sh"
source "${SCRIPT_DIR}/lib/php.sh"

validate_path() {
    local path="$1"
    if [[ -z "${path}" ]] || [[ "${path}" == "/" ]] || [[ "${path}" == "/srv" ]]; then
        error "Refusing to operate on path: ${path}"
        return 1
    fi
    return 0
}

main() {
    echo -e "${BOLD}${RED}"
    echo "  _    _ _   _ _ _ _   _         ____            _            "
    echo " | |  | | | (_) (_) | (_)       |  _ \  ___  _ __| | ___ _ __  "
    echo " | |  | | |_ _| |_| |_ _  ___  | | | |/ _ \| '__| |/ _ \ '__| "
    echo " | |__| | __| | | | __| |/ __| | |_| | (_) | |  | |  __/ |   "
    echo "  \____/ \__|_|_| \__|_|\___| |____/ \___/|_|  |_|\___|_|   "
    echo -e "${NC}"
    echo -e "${BOLD}${RED}Moodle Instance Uninstaller${NC}"
    echo -e "${YELLOW}WARNING: This will permanently remove a Moodle instance.${NC}"
    echo ""

    read -r -p "$(echo -e "${CYAN}Instance name to remove:${NC} ")" INSTANCE_NAME
    INSTANCE_NAME="${INSTANCE_NAME,,}"
    INSTANCE_NAME="${INSTANCE_NAME// /-}"

    if [[ -z "${INSTANCE_NAME}" ]]; then
        error "Instance name cannot be empty."
        exit 1
    fi

    local DEFAULT_INSTALL_DIR="/srv/${INSTANCE_NAME}"
    read -r -p "$(echo -e "${CYAN}Installation directory${NC} [${DEFAULT_INSTALL_DIR}]: ")" INSTALL_DIR
    INSTALL_DIR="${INSTALL_DIR:-${DEFAULT_INSTALL_DIR}}"
    INSTALL_DIR="${INSTALL_DIR%/}"

    validate_path "${INSTALL_DIR}"

    local DEFAULT_DB_NAME="${INSTANCE_NAME//-/_}"
    local DEFAULT_DB_USER="${INSTANCE_NAME//-/_}"
    if [[ ${#DEFAULT_DB_USER} -gt 32 ]]; then
        DEFAULT_DB_USER="${DEFAULT_DB_USER:0:32}"
    fi

    read -r -p "$(echo -e "${CYAN}Database name${NC} [${DEFAULT_DB_NAME}]: ")" DB_NAME
    DB_NAME="${DB_NAME:-${DEFAULT_DB_NAME}}"
    DB_NAME="${DB_NAME//-/_}"

    read -r -p "$(echo -e "${CYAN}Database user${NC} [${DEFAULT_DB_USER}]: ")" DB_USER
    DB_USER="${DB_USER:-${DEFAULT_DB_USER}}"
    DB_USER="${DB_USER//-/_}"

    read -r -p "$(echo -e "${CYAN}PHP version${NC} [8.1]: ")" PHP_VERSION
    PHP_VERSION="${PHP_VERSION:-8.1}"

    # Configurable paths
    local NGINX_AVAILABLE="/etc/nginx/sites-available"
    local NGINX_ENABLED="/etc/nginx/sites-enabled"
    local PHP_CONF_D="/etc/php"

    echo ""

    header "UNINSTALL SUMMARY"
    echo -e "The following will be ${RED}permanently removed${NC}:"
    echo ""

    if [[ -d "${INSTALL_DIR}" ]]; then
        echo -e "  ${BOLD}Directory:${NC} ${INSTALL_DIR}"
    else
        echo -e "  ${BOLD}Directory:${NC} ${INSTALL_DIR} ${YELLOW}(not found)${NC}"
    fi

    local nginx_config="${NGINX_AVAILABLE}/${INSTANCE_NAME}.conf"
    local nginx_symlink="${NGINX_ENABLED}/${INSTANCE_NAME}.conf"

    if [[ -f "${nginx_config}" ]]; then
        echo -e "  ${BOLD}Nginx config:${NC} ${nginx_config}"
    fi

    if [[ -L "${nginx_symlink}" ]]; then
        echo -e "  ${BOLD}Nginx symlink:${NC} ${nginx_symlink}"
    fi

    if mysql -e "SELECT SCHEMA_NAME FROM INFORMATION_SCHEMA.SCHEMATA WHERE SCHEMA_NAME = '${DB_NAME}';" 2>/dev/null | grep -q "${DB_NAME}"; then
        echo -e "  ${BOLD}Database:${NC} ${DB_NAME}"
    else
        echo -e "  ${BOLD}Database:${NC} ${DB_NAME} ${YELLOW}(not found)${NC}"
    fi

    if mysql -e "SELECT USER FROM mysql.user WHERE USER = '${DB_USER}';" 2>/dev/null | grep -q "${DB_USER}"; then
        echo -e "  ${BOLD}Database user:${NC} ${DB_USER}"
    else
        echo -e "  ${BOLD}Database user:${NC} ${DB_USER} ${YELLOW}(not found)${NC}"
    fi

    local php_ini="${PHP_CONF_D}/${PHP_VERSION}/fpm/conf.d/99-moodle.ini"
    if [[ -f "${php_ini}" ]]; then
        echo -e "  ${BOLD}PHP config:${NC} ${php_ini}"
    fi

    echo ""

    if ! confirm "Are you ABSOLUTELY sure you want to remove this instance?" "n"; then
        info "Uninstall cancelled."
        exit 0
    fi

    if ! confirm "Type the instance name '${INSTANCE_NAME}' to confirm" "n"; then
        info "Uninstall cancelled."
        exit 0
    fi

    echo ""
    header "UNINSTALLING"

    if [[ -L "${nginx_symlink}" ]]; then
        info "Disabling nginx site: ${INSTANCE_NAME}"
        rm -f "${nginx_symlink}"
    fi

    if [[ -f "${nginx_config}" ]]; then
        info "Removing nginx config: ${nginx_config}"
        rm -f "${nginx_config}"
    fi

    if [[ -L "${nginx_symlink}" ]] || [[ -f "${nginx_config}" ]]; then
        info "Reloading nginx"
        local nginx_bin
        nginx_bin="$(find_binary "nginx" 2>/dev/null || true)"
        if [[ -n "${nginx_bin}" ]]; then
            "${nginx_bin}" -t && systemctl reload nginx || warn "Nginx reload failed"
        fi
    fi

    if mysql -e "SELECT SCHEMA_NAME FROM INFORMATION_SCHEMA.SCHEMATA WHERE SCHEMA_NAME = '${DB_NAME}';" 2>/dev/null | grep -q "${DB_NAME}"; then
        drop_database "${DB_NAME}"
    else
        info "Database '${DB_NAME}' does not exist, skipping."
    fi

    if mysql -e "SELECT USER FROM mysql.user WHERE USER = '${DB_USER}';" 2>/dev/null | grep -q "${DB_USER}"; then
        drop_user "${DB_USER}"
    else
        info "Database user '${DB_USER}' does not exist, skipping."
    fi

    if [[ -d "${INSTALL_DIR}" ]]; then
        info "Removing installation directory: ${INSTALL_DIR}"
        rm -rf "${INSTALL_DIR}"
        ok "Directory removed"
    else
        info "Directory '${INSTALL_DIR}' does not exist, skipping."
    fi

    local php_ini_file="${PHP_CONF_D}/${PHP_VERSION}/fpm/conf.d/99-moodle.ini"
    if [[ -f "${php_ini_file}" ]]; then
        remove_php_config "${PHP_VERSION}" "${PHP_CONF_D}"
    else
        info "PHP config '${php_ini_file}' does not exist, skipping."
    fi

    echo ""
    header "UNINSTALL COMPLETE"
    ok "Instance '${INSTANCE_NAME}' has been removed."
}

main "$@"
