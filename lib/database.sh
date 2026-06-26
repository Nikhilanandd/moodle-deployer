#!/bin/bash
# Moodle Deployer - Database operations
# Creates MariaDB database, user, grants privileges, and imports backups

setup_database() {
    local db_name="$1"
    local db_user="$2"
    local db_pass="$3"
    local db_backup="$4"

    header "DATABASE SETUP"

    info "Creating database: ${db_name}"
    mysql -e "CREATE DATABASE IF NOT EXISTS \`${db_name}\` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;"
    ok "Database '${db_name}' created with utf8mb4 character set"

    rollback_add "mysql -e \"DROP DATABASE IF EXISTS \\\`${db_name}\\\`;\""

    info "Creating database user: ${db_user}"
    mysql -e "CREATE USER IF NOT EXISTS '${db_user}'@'localhost' IDENTIFIED BY '${db_pass}';"
    ok "Database user '${db_user}' created"

    rollback_add "mysql -e \"DROP USER IF EXISTS '${db_user}'@'localhost';\""

    info "Granting privileges to ${db_user} on ${db_name}"
    mysql -e "GRANT ALL PRIVILEGES ON \`${db_name}\`.* TO '${db_user}'@'localhost';"
    mysql -e "FLUSH PRIVILEGES;"
    ok "Privileges granted"

    if [[ -n "${db_backup}" ]]; then
        restore_db_backup "${db_backup}" "${db_name}" "${db_user}" "${db_pass}"
    else
        ok "Database created. Ready for fresh Moodle installation."
    fi

    # Verify database exists with proper charset
    local charset
    charset="$(mysql -e "SELECT DEFAULT_CHARACTER_SET_NAME, DEFAULT_COLLATION_NAME FROM INFORMATION_SCHEMA.SCHEMATA WHERE SCHEMA_NAME = '${db_name}';" 2>/dev/null | tail -1)"
    info "Database verification: ${charset}"

    ok "Database setup complete"
}

verify_database_connection() {
    local db_name="$1"
    local db_user="$2"
    local db_pass="$3"

    if ! mysql -u "${db_user}" -p"${db_pass}" "${db_name}" -e "SELECT 1;" &>/dev/null; then
        error "Cannot connect to database '${db_name}' as '${db_user}'."
        return 1
    fi
    ok "Database connection verified"
}

drop_database() {
    local db_name="$1"
    info "Dropping database: ${db_name}"
    mysql -e "DROP DATABASE IF EXISTS \`${db_name}\`;" || warn "Could not drop database '${db_name}'"
}

drop_user() {
    local db_user="$1"
    info "Dropping database user: ${db_user}"
    mysql -e "DROP USER IF EXISTS '${db_user}'@'localhost';" || warn "Could not drop user '${db_user}'"
}
