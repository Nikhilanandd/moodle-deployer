#!/bin/bash
# Moodle Deployer - Rollback management
# Tracks deployment steps and provides atomic rollback on failure

ROLLBACK_FILE=""

rollback_init() {
    ROLLBACK_FILE="$(mktemp /tmp/moodle-rollback.XXXXXX)"
}

rollback_add() {
    local cmd="$1"
    echo "${cmd}" >> "${ROLLBACK_FILE}"
}

rollback_execute() {
    local exit_code=${1:-1}

    if [[ ! -f "${ROLLBACK_FILE}" ]]; then
        return
    fi

    header "ROLLBACK"

    local steps=()
    while IFS= read -r line; do
        steps+=("${line}")
    done < "${ROLLBACK_FILE}"

    local i
    for ((i = ${#steps[@]} - 1; i >= 0; i--)); do
        info "Undoing: ${steps[i]}"
        eval "${steps[i]}" || warn "Rollback step failed (non-fatal): ${steps[i]}"
    done

    rm -f "${ROLLBACK_FILE}"
    warn "Rollback complete. System returned to previous state."
    exit "${exit_code}"
}
