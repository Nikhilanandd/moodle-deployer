#!/bin/bash
#===============================================================================
# Moodle Deployer - Production-grade Moodle instance deployment utility
# Restores the latest Moodle backup into a new Moodle instance with full
# database, nginx, PHP-FPM automation.
#
# Usage: sudo ./deploy-moodle.sh
#===============================================================================

set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

source "${SCRIPT_DIR}/lib/colors.sh"
source "${SCRIPT_DIR}/lib/logging.sh"
source "${SCRIPT_DIR}/lib/rollback.sh"
source "${SCRIPT_DIR}/lib/validation.sh"
source "${SCRIPT_DIR}/lib/backup.sh"
source "${SCRIPT_DIR}/lib/database.sh"
source "${SCRIPT_DIR}/lib/permissions.sh"
source "${SCRIPT_DIR}/lib/nginx.sh"
source "${SCRIPT_DIR}/lib/php.sh"

#-------------------------------------------------------------------------------
# Global state
#-------------------------------------------------------------------------------
INSTANCE_NAME=""
INSTALL_DIR=""
HTTP_PORT=""
SERVER_NAME=""
PHP_VERSION="8.1"
DB_NAME=""
DB_USER=""
DB_PASS=""
BACKUP_ROOT=""
WEB_USER="www-data"
NGINX_AVAILABLE="/etc/nginx/sites-available"
NGINX_ENABLED="/etc/nginx/sites-enabled"
PHP_CONF_D="/etc/php"
RESTORE_CODE=false
RESTORE_DB=false
RESTORE_MOODLEDATA=false
CODE_BACKUP=""
DB_BACKUP=""
MOODLEDATA_BACKUP=""
ROLLBACK_REQUIRED=true

#===============================================================================
# TRAP HANDLERS
#===============================================================================

safe_rm() {
    local path="$1"
    if [[ -z "${path}" ]] || [[ "${path}" == "/" ]] || [[ "${path}" == "/srv" ]]; then
        error "ROLLBACK REFUSED: Path '${path}' is unsafe to remove."
        return 1
    fi
    rm -rf "${path}"
}

error_handler() {
    local exit_code=$?
    error "Unhandled error at line ${BASH_LINENO[0]}: '${BASH_COMMAND}' (exit: ${exit_code})"
    if [[ "${ROLLBACK_REQUIRED}" == true ]]; then
        rollback_execute "${exit_code}"
    fi
    exit "${exit_code}"
}

int_handler() {
    warn "Interrupted by user."
    if [[ "${ROLLBACK_REQUIRED}" == true ]]; then
        rollback_execute 1
    fi
    exit 1
}

trap 'error_handler' ERR
trap 'int_handler' INT

#===============================================================================
# CLEANUP INSTALL FILES
#===============================================================================

cleanup_install_files() {
    local moodle_dir="$1"

    header "CLEANING INSTALLATION FILES"

    if [[ ! -d "${moodle_dir}" ]]; then
        warn "Moodle directory does not exist, skipping cleanup: ${moodle_dir}"
        return 0
    fi

    info "Removing generated configuration and runtime files"

    rm -f "${moodle_dir}/config.php"
    rm -f "${moodle_dir}/config.php.bak"

    local runtime_dirs=("cache" "localcache" "temp" "trashdir" "sessions")
    local dir
    for dir in "${runtime_dirs[@]}"; do
        local target="${moodle_dir}/${dir}"
        if [[ -d "${target}" ]]; then
            safe_rm "${target}"
            info "  Removed: ${dir}/"
        fi
    done

    if [[ -d "${moodle_dir}/.git" ]]; then
        safe_rm "${moodle_dir}/.git"
        info "  Removed: .git/"
    fi

    rm -f "${moodle_dir}/phpunit.xml"
    rm -f "${moodle_dir}/phpunit.xml.dist"
    rm -f "${moodle_dir}/.phpunit.xml"

    if [[ -d "${moodle_dir}/behat" ]]; then
        safe_rm "${moodle_dir}/behat"
        info "  Removed: behat/"
    fi

    if [[ -d "${moodle_dir}/vendor" ]]; then
        find "${moodle_dir}/vendor" -maxdepth 3 -type d \( -name test -o -name tests -o -name Test -o -name Tests \) -exec rm -rf {} + 2>/dev/null || true
        info "  Removed vendor test directories"
    fi

    ok "Installation files cleaned"
}

#===============================================================================
# CREATE DIRECTORIES
#===============================================================================

create_directories() {
    local install_dir="$1"

    header "CREATING DIRECTORIES"

    if [[ -d "${install_dir}" ]]; then
        error "Installation directory already exists: ${install_dir}"
        return 1
    fi

    mkdir -p "${install_dir}/moodle"
    mkdir -p "${install_dir}/moodledata"

    rollback_add "safe_rm '${install_dir}'"

    ok "Directories created under ${install_dir}"
}

#===============================================================================
# GATHER INFORMATION
#===============================================================================

gather_info() {
    header "CONFIGURATION"

    local DEFAULT_SERVER_IP
    DEFAULT_SERVER_IP="$(hostname -I 2>/dev/null | awk '{print $1}')"
    DEFAULT_SERVER_IP="${DEFAULT_SERVER_IP:-127.0.0.1}"

    read -r -p "$(echo -e "${CYAN}Instance name${NC} (e.g., moodle-preprod): ")" INSTANCE_NAME
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

    read -r -p "$(echo -e "${CYAN}HTTP Port${NC}: ")" HTTP_PORT
    if [[ -z "${HTTP_PORT}" ]]; then
        error "HTTP Port cannot be empty."
        exit 1
    fi
    if ! [[ "${HTTP_PORT}" =~ ^[0-9]+$ ]] || [[ "${HTTP_PORT}" -lt 1 ]] || [[ "${HTTP_PORT}" -gt 65535 ]]; then
        error "Invalid port: ${HTTP_PORT}. Must be between 1-65535."
        exit 1
    fi

    read -r -p "$(echo -e "${CYAN}Server Name / IP${NC} [${DEFAULT_SERVER_IP}]: ")" SERVER_NAME
    SERVER_NAME="${SERVER_NAME:-${DEFAULT_SERVER_IP}}"

    read -r -p "$(echo -e "${CYAN}PHP Version${NC} [8.1]: ")" PHP_VERSION
    PHP_VERSION="${PHP_VERSION:-8.1}"

    local DEFAULT_DB_NAME="${INSTANCE_NAME}"
    read -r -p "$(echo -e "${CYAN}Database name${NC} [${DEFAULT_DB_NAME}]: ")" DB_NAME
    DB_NAME="${DB_NAME:-${DEFAULT_DB_NAME}}"
    DB_NAME="${DB_NAME//-/_}"

    local DEFAULT_DB_USER="${INSTANCE_NAME}"
    DEFAULT_DB_USER="${DEFAULT_DB_USER//-/_}"
    read -r -p "$(echo -e "${CYAN}Database user${NC} [${DEFAULT_DB_USER}]: ")" DB_USER
    DB_USER="${DB_USER:-${DEFAULT_DB_USER}}"
    DB_USER="${DB_USER//-/_}"

    if [[ ${#DB_USER} -gt 32 ]]; then
        DB_USER="${DB_USER:0:32}"
        warn "Database user truncated to 32 characters: ${DB_USER}"
    fi

    read -r -s -p "$(echo -e "${CYAN}Database password${NC}: ")" DB_PASS
    echo ""
    if [[ -z "${DB_PASS}" ]]; then
        error "Database password cannot be empty."
        exit 1
    fi

    read -r -s -p "$(echo -e "${CYAN}Confirm database password${NC}: ")" DB_PASS_CONFIRM
    echo ""
    if [[ "${DB_PASS}" != "${DB_PASS_CONFIRM}" ]]; then
        error "Passwords do not match."
        exit 1
    fi

    # Backup root path
    local DEFAULT_BACKUP_ROOT="/srv/backups/moodlelms"
    read -r -p "$(echo -e "${CYAN}Backup root directory${NC} [${DEFAULT_BACKUP_ROOT}]: ")" BACKUP_ROOT
    BACKUP_ROOT="${BACKUP_ROOT:-${DEFAULT_BACKUP_ROOT}}"
    BACKUP_ROOT="${BACKUP_ROOT%/}"

    # Web server user
    read -r -p "$(echo -e "${CYAN}Web server user${NC} [www-data]: ")" WEB_USER
    WEB_USER="${WEB_USER:-www-data}"

    echo ""
    if confirm "Restore latest code backup?" "y"; then
        RESTORE_CODE=true
        CODE_BACKUP="$(find_latest_backup "${BACKUP_ROOT}/code" "*.tar.gz")"
        if [[ -z "${CODE_BACKUP}" ]]; then
            error "No code backup found in ${BACKUP_ROOT}/code/"
            exit 1
        fi
    fi

    if confirm "Restore latest database backup?" "y"; then
        RESTORE_DB=true
        DB_BACKUP="$(detect_db_backup "${BACKUP_ROOT}")"
        if [[ -z "${DB_BACKUP}" ]]; then
            error "No database backup found in ${BACKUP_ROOT}/db/"
            exit 1
        fi
    fi

    if confirm "Restore latest moodledata backup?" "y"; then
        RESTORE_MOODLEDATA=true
        MOODLEDATA_BACKUP="$(find_latest_backup "${BACKUP_ROOT}/moodledata" "*.tar.gz")"
        if [[ -z "${MOODLEDATA_BACKUP}" ]]; then
            error "No moodledata backup found in ${BACKUP_ROOT}/moodledata/"
            exit 1
        fi
    fi

    echo ""
    info "Configuration collected for instance: ${INSTANCE_NAME}"
}

#===============================================================================
# PRINT SUMMARY
#===============================================================================

print_summary() {
    local url="http://${SERVER_NAME}:${HTTP_PORT}"

    header "DEPLOYMENT COMPLETE"

    echo -e "${BOLD}Instance Name:${NC}      ${INSTANCE_NAME}"
    echo -e "${BOLD}Install Path:${NC}       ${INSTALL_DIR}/moodle"
    echo -e "${BOLD}Moodledata Path:${NC}    ${INSTALL_DIR}/moodledata"
    echo -e "${BOLD}Web User:${NC}           ${WEB_USER}"
    echo -e "${BOLD}Database:${NC}           ${DB_NAME}"
    echo -e "${BOLD}Database User:${NC}      ${DB_USER}"
    echo -e "${BOLD}HTTP URL:${NC}           ${url}"
    echo -e "${BOLD}Nginx Config:${NC}       ${NGINX_AVAILABLE}/${INSTANCE_NAME}.conf"
    echo -e "${BOLD}Log File:${NC}           ${LOG_FILE}"
    echo ""
    echo -e "${BOLD}${GREEN}NEXT STEPS${NC}"
    echo ""
    echo -e "  1. Open your browser and visit: ${BOLD}${url}${NC}"
    echo -e "  2. Complete the Moodle web installer."
    echo -e "  3. Database is ready: ${DB_NAME} / ${DB_USER}"
    echo -e "  4. PHP-FPM is configured for Moodle (99-moodle.ini)."
    echo -e ""
    echo -e "${YELLOW}  NOTE: The web installer will create a new config.php.${NC}"
    echo -e "${YELLOW}  The previous config.php was removed for a fresh install.${NC}"
    echo ""
}

#===============================================================================
# DEPLOYMENT CHECKLIST
#===============================================================================

run_deployment() {
    create_directories "${INSTALL_DIR}"

    if [[ "${RESTORE_CODE}" == true ]]; then
        restore_code_backup "${CODE_BACKUP}" "${INSTALL_DIR}/moodle"
        cleanup_install_files "${INSTALL_DIR}/moodle"
    else
        info "Skipping code restore. Creating empty moodle directory."
        mkdir -p "${INSTALL_DIR}/moodle"
    fi

    if [[ "${RESTORE_MOODLEDATA}" == true ]]; then
        restore_moodledata_backup "${MOODLEDATA_BACKUP}" "${INSTALL_DIR}/moodledata"
    else
        info "Skipping moodledata restore. Creating empty moodledata directory."
        mkdir -p "${INSTALL_DIR}/moodledata"
    fi

    setup_database "${DB_NAME}" "${DB_USER}" "${DB_PASS}" "${DB_BACKUP}"

    set_code_permissions "${INSTALL_DIR}/moodle" "${WEB_USER}"
    set_moodledata_permissions "${INSTALL_DIR}/moodledata" "${WEB_USER}"
    verify_permissions "${INSTALL_DIR}/moodle" "${INSTALL_DIR}/moodledata" "${WEB_USER}"

    configure_nginx \
        "${INSTANCE_NAME}" \
        "${INSTALL_DIR}" \
        "${HTTP_PORT}" \
        "${SERVER_NAME}" \
        "${PHP_VERSION}" \
        "${NGINX_AVAILABLE}" \
        "${NGINX_ENABLED}"

    configure_php "${PHP_VERSION}" "${PHP_CONF_D}"
}

#===============================================================================
# MAIN
#===============================================================================

main() {
    echo -e "${BOLD}${GREEN}"
    echo "  __  ___              _        ____             _            "
    echo " /  |/  /___ _      __| | ___  |  _ \  ___  _ __| | ___ _ __  "
    echo " / /|_/ // _ \ \ /\ / /| |/ _ \ | | | |/ _ \| '__| |/ _ \ '__| "
    echo "/ /  / /| (_) \ V  V / | |  __/ | |_| | (_) | |  | |  __/ |   "
    echo "/_/  /_/  \___/ \_/\_/  |_|\___| |____/ \___/|_|  |_|\___|_|   "
    echo -e "${NC}"
    echo -e "${BOLD}Production Moodle Deployment Tool${NC}"
    echo ""

    rollback_init

    gather_info

    validate_all \
        "${INSTANCE_NAME}" \
        "${INSTALL_DIR}" \
        "${HTTP_PORT}" \
        "${PHP_VERSION}" \
        "${DB_NAME}" \
        "${CODE_BACKUP}" \
        "${DB_BACKUP}" \
        "${MOODLEDATA_BACKUP}" \
        "${NGINX_AVAILABLE}/${INSTANCE_NAME}.conf"

    if [[ $? -ne 0 ]]; then
        error "Pre-flight checks failed. Aborting."
        rollback_execute 1
    fi

    run_deployment

    ROLLBACK_REQUIRED=false

    print_summary
}

main "$@"
