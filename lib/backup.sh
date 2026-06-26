#!/bin/bash
# Moodle Deployer - Backup restoration
# Locates latest backups and extracts them to the deployment directories

BACKUP_ROOT="/srv/backups/moodlelms"

find_latest_backup() {
    local directory="$1"
    local pattern="${2:-*.tar.gz}"

    if [[ ! -d "${directory}" ]]; then
        echo ""
        return
    fi

    local latest
    latest="$(find "${directory}" -maxdepth 1 -type f -name "${pattern}" 2>/dev/null | sort | tail -1)"
    echo "${latest}"
}

detect_db_backup() {
    local db_dir="${BACKUP_ROOT}/db"

    if [[ ! -d "${db_dir}" ]]; then
        echo ""
        return
    fi

    # Try .sql first, then .sql.gz, then .tar.gz
    local backup
    backup="$(find_latest_backup "${db_dir}" "*.sql")"
    if [[ -n "${backup}" ]]; then
        echo "${backup}"
        return
    fi

    backup="$(find_latest_backup "${db_dir}" "*.sql.gz")"
    if [[ -n "${backup}" ]]; then
        echo "${backup}"
        return
    fi

    backup="$(find_latest_backup "${db_dir}" "*.tar.gz")"
    echo "${backup}"
}

extract_tar_gz() {
    local archive="$1"
    local target="$2"

    if [[ ! -f "${archive}" ]]; then
        error "Archive not found: ${archive}"
        return 1
    fi

    mkdir -p "${target}"

    tar -xzf "${archive}" -C "${target}" 2>/dev/null

    # Detect if extraction created a single top-level directory
    local entries=()
    shopt -s nullglob
    entries=("${target}"/* "${target}"/.*)
    shopt -u nullglob
    local real_entries=()
    local e
    for e in "${entries[@]}"; do
        [[ "${e}" == "${target}/." ]] || [[ "${e}" == "${target}/.." ]] && continue
        real_entries+=("${e}")
    done

    if [[ ${#real_entries[@]} -eq 1 ]] && [[ -d "${real_entries[0]}" ]]; then
        local subdir="${real_entries[0]}"
        info "Archive has top-level directory. Flattening..."
        shopt -s dotglob
        local f
        for f in "${subdir}"/* "${subdir}"/.*; do
            [[ "${f}" == "${subdir}/." ]] || [[ "${f}" == "${subdir}/.." ]] && continue
            mv "${f}" "${target}/" 2>/dev/null || true
        done
        shopt -u dotglob
        rmdir "${subdir}" 2>/dev/null || true
    fi

    ok "Extracted: $(basename "${archive}")"
}

extract_sql_backup() {
    local archive="$1"

    if [[ ! -f "${archive}" ]]; then
        error "Database backup not found: ${archive}"
        return 1
    fi

    local filename
    filename="$(basename "${archive}")"

    case "${filename}" in
        *.tar.gz)
            local tmp_dir
            tmp_dir="$(mktemp -d /tmp/moodle-db-extract.XXXXXX)"
            tar -xzf "${archive}" -C "${tmp_dir}"
            local sql_file
            sql_file="$(find "${tmp_dir}" -name "*.sql" -type f 2>/dev/null | head -1)"
            if [[ -z "${sql_file}" ]]; then
                rm -rf "${tmp_dir}"
                error "No SQL file found in ${archive}"
                return 1
            fi
            cat "${sql_file}"
            rm -rf "${tmp_dir}"
            ;;
        *.gz)
            zcat "${archive}"
            ;;
        *.sql)
            cat "${archive}"
            ;;
        *)
            error "Unsupported database backup format: ${filename}"
            return 1
            ;;
    esac
}

restore_code_backup() {
    local code_backup="$1"
    local moodle_dir="$2"

    if [[ -z "${code_backup}" ]]; then
        info "No code backup selected. Creating empty moodle directory."
        mkdir -p "${moodle_dir}"
        return 0
    fi

    header "RESTORING CODE BACKUP"

    if [[ ! -f "${code_backup}" ]]; then
        error "Code backup not found: ${code_backup}"
        return 1
    fi

    mkdir -p "${moodle_dir}"
    extract_tar_gz "${code_backup}" "${moodle_dir}"

    local file_count
    file_count="$(find "${moodle_dir}" -maxdepth 1 -type f -o -type d | wc -l)"
    if [[ "${file_count}" -le 1 ]]; then
        warn "Code backup appears empty or contains no files in expected location."
    fi

    rollback_add "safe_rm '${moodle_dir}'"
    ok "Code restored to ${moodle_dir}"
}

restore_db_backup() {
    local db_backup="$1"
    local db_name="$2"
    local db_user="$3"
    local db_pass="$4"

    if [[ -z "${db_backup}" ]]; then
        info "No database backup selected. Database will be empty for fresh installation."
        return 0
    fi

    header "RESTORING DATABASE BACKUP"

    if [[ ! -f "${db_backup}" ]]; then
        error "Database backup not found: ${db_backup}"
        return 1
    fi

    info "Importing database backup: $(basename "${db_backup}")"
    extract_sql_backup "${db_backup}" | mysql -u "${db_user}" -p"${db_pass}" "${db_name}" 2>&1

    local mysql_exit=$?
    if [[ ${mysql_exit} -ne 0 ]]; then
        error "Database import failed with exit code ${mysql_exit}."
        return 1
    fi

    ok "Database backup imported successfully"
}

restore_moodledata_backup() {
    local moodledata_backup="$1"
    local moodledata_dir="$2"

    if [[ -z "${moodledata_backup}" ]]; then
        info "No moodledata backup selected. Creating empty moodledata directory."
        mkdir -p "${moodledata_dir}"
        return 0
    fi

    header "RESTORING MOODLEDATA BACKUP"

    if [[ ! -f "${moodledata_backup}" ]]; then
        error "Moodledata backup not found: ${moodledata_backup}"
        return 1
    fi

    mkdir -p "${moodledata_dir}"
    extract_tar_gz "${moodledata_backup}" "${moodledata_dir}"

    rollback_add "safe_rm '${moodledata_dir}'"
    ok "Moodledata restored to ${moodledata_dir}"
}
