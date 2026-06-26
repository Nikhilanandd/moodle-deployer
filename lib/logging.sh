#!/bin/bash
# Moodle Deployer - Logging utilities
# Provides consistent logging with timestamps, colored output, and log file persistence

if [[ -z "${LOG_FILE:-}" ]]; then
    LOG_FILE="/var/log/moodle-deploy.log"
fi

# Ensure log directory exists
mkdir -p "$(dirname "${LOG_FILE}")" 2>/dev/null || true
touch "${LOG_FILE}" 2>/dev/null || true

log() {
    local level="$1"
    shift
    local ts
    ts="$(date '+%Y-%m-%d %H:%M:%S')"
    echo "${ts} [${level}] $*" >> "${LOG_FILE}"
}

info() {
    echo -e "${GREEN}[INFO]${NC} $*"
    log "INFO" "$@"
}

ok() {
    echo -e "${GREEN}[OK]${NC} $*"
    log "OK" "$@"
}

warn() {
    echo -e "${YELLOW}[WARN]${NC} $*"
    log "WARN" "$@"
}

error() {
    echo -e "${RED}[ERROR]${NC} $*" >&2
    log "ERROR" "$@"
}

header() {
    echo ""
    echo -e "${BOLD}${BLUE}═══════════════════════════════════════════${NC}"
    echo -e "${BOLD}${BLUE}  $*${NC}"
    echo -e "${BOLD}${BLUE}═══════════════════════════════════════════${NC}"
    echo ""
}

confirm() {
    local prompt="$1"
    local default="${2:-n}"
    local answer
    while true; do
        read -r -p "$(echo -e "${CYAN}${prompt}${NC}") [${default}] " answer
        answer="${answer:-${default}}"
        case "${answer}" in
            [yY]|[yY][eE][sS]) return 0 ;;
            [nN]|[nN][oO]) return 1 ;;
            *) warn "Please answer yes or no." ;;
        esac
    done
}
