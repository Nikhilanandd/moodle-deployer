#!/bin/bash
# Moodle Deployer - File permissions
# Sets secure permissions for Moodle code and moodledata directories

set_code_permissions() {
    local moodle_dir="$1"
    local web_user="${2:-www-data}"

    header "SETTING CODE PERMISSIONS"

    if [[ ! -d "${moodle_dir}" ]]; then
        error "Moodle directory not found: ${moodle_dir}"
        return 1
    fi

    info "Setting ownership to ${web_user}:${web_user}"
    chown -R "${web_user}:${web_user}" "${moodle_dir}"

    info "Setting directory permissions to 755"
    find "${moodle_dir}" -type d -exec chmod 755 {} \;

    info "Setting file permissions to 644"
    find "${moodle_dir}" -type f -exec chmod 644 {} \;

    chmod 644 "${moodle_dir}/index.php" 2>/dev/null || true

    ok "Code permissions set successfully"
}

set_moodledata_permissions() {
    local moodledata_dir="$1"
    local web_user="${2:-www-data}"

    header "SETTING MOODLEDATA PERMISSIONS"

    if [[ ! -d "${moodledata_dir}" ]]; then
        warn "Moodledata directory not found: ${moodledata_dir}. Creating..."
        mkdir -p "${moodledata_dir}"
    fi

    info "Setting ownership to ${web_user}:${web_user}"
    chown -R "${web_user}:${web_user}" "${moodledata_dir}"

    info "Setting directory permissions to 770"
    find "${moodledata_dir}" -type d -exec chmod 770 {} \;

    info "Setting file permissions to 660"
    find "${moodledata_dir}" -type f -exec chmod 660 {} \;

    ok "Moodledata permissions set successfully"
}

verify_permissions() {
    local moodle_dir="$1"
    local moodledata_dir="$2"
    local web_user="${3:-www-data}"

    header "VERIFYING PERMISSIONS"

    local issues=0

    local owner
    owner="$(stat -c '%U:%G' "${moodle_dir}" 2>/dev/null)"
    if [[ "${owner}" != "${web_user}:${web_user}" ]]; then
        warn "Code directory owner is ${owner}, expected ${web_user}:${web_user}"
        issues=$((issues + 1))
    fi

    if [[ -d "${moodledata_dir}" ]]; then
        owner="$(stat -c '%U:%G' "${moodledata_dir}" 2>/dev/null)"
        if [[ "${owner}" != "${web_user}:${web_user}" ]]; then
            warn "Moodledata directory owner is ${owner}, expected ${web_user}:${web_user}"
            issues=$((issues + 1))
        fi
    fi

    if sudo -u "${web_user}" test -r "${moodle_dir}/index.php" 2>/dev/null; then
        ok "${web_user} can read code files"
    else
        warn "${web_user} cannot read code files"
        issues=$((issues + 1))
    fi

    if [[ -d "${moodledata_dir}" ]]; then
        if sudo -u "${web_user}" test -w "${moodledata_dir}" 2>/dev/null; then
            ok "${web_user} can write to moodledata"
        else
            warn "${web_user} cannot write to moodledata"
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
