#!/bin/bash
# Moodle Deployer - File permissions
# Sets secure permissions for Moodle code and moodledata directories

set_code_permissions() {
    local moodle_dir="$1"

    header "SETTING CODE PERMISSIONS"

    if [[ ! -d "${moodle_dir}" ]]; then
        error "Moodle directory not found: ${moodle_dir}"
        return 1
    fi

    info "Setting ownership to www-data:www-data"
    chown -R www-data:www-data "${moodle_dir}"

    info "Setting directory permissions to 755"
    find "${moodle_dir}" -type d -exec chmod 755 {} \;

    info "Setting file permissions to 644"
    find "${moodle_dir}" -type f -exec chmod 644 {} \;

    # Ensure PHP scripts are readable
    chmod 644 "${moodle_dir}/index.php" 2>/dev/null || true

    ok "Code permissions set successfully"
}

set_moodledata_permissions() {
    local moodledata_dir="$1"

    header "SETTING MOODLEDATA PERMISSIONS"

    if [[ ! -d "${moodledata_dir}" ]]; then
        warn "Moodledata directory not found: ${moodledata_dir}. Creating..."
        mkdir -p "${moodledata_dir}"
    fi

    info "Setting ownership to www-data:www-data"
    chown -R www-data:www-data "${moodledata_dir}"

    info "Setting directory permissions to 770"
    find "${moodledata_dir}" -type d -exec chmod 770 {} \;

    info "Setting file permissions to 660"
    find "${moodledata_dir}" -type f -exec chmod 660 {} \;

    ok "Moodledata permissions set successfully"
}

verify_permissions() {
    local moodle_dir="$1"
    local moodledata_dir="$2"

    header "VERIFYING PERMISSIONS"

    local issues=0

    # Check code directory ownership
    local owner
    owner="$(stat -c '%U:%G' "${moodle_dir}" 2>/dev/null)"
    if [[ "${owner}" != "www-data:www-data" ]]; then
        warn "Code directory owner is ${owner}, expected www-data:www-data"
        issues=$((issues + 1))
    fi

    # Check moodledata directory ownership
    if [[ -d "${moodledata_dir}" ]]; then
        owner="$(stat -c '%U:%G' "${moodledata_dir}" 2>/dev/null)"
        if [[ "${owner}" != "www-data:www-data" ]]; then
            warn "Moodledata directory owner is ${owner}, expected www-data:www-data"
            issues=$((issues + 1))
        fi
    fi

    # Check if www-data can read code files
    if sudo -u www-data test -r "${moodle_dir}/index.php" 2>/dev/null; then
        ok "www-data can read code files"
    else
        warn "www-data cannot read code files"
        issues=$((issues + 1))
    fi

    # Check if www-data can write to moodledata
    if [[ -d "${moodledata_dir}" ]]; then
        if sudo -u www-data test -w "${moodledata_dir}" 2>/dev/null; then
            ok "www-data can write to moodledata"
        else
            warn "www-data cannot write to moodledata"
            issues=$((issues + 1))
        fi
    fi

    if [[ ${issues} -eq 0 ]]; then
        ok "All permissions verified"
    else
        warn "${issues} permission issue(s) found"
    fi

    return ${issues}
}
