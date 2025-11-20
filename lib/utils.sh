#!/bin/bash
# lib/utils.sh
# Utility functions for Hostfy Container Management System

# ========================================
# Colors and Formatting
# ========================================
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color
BOLD='\033[1m'

# ========================================
# Configuration Paths
# ========================================
HOSTFY_ROOT="${HOSTFY_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"
COMMANDS_DIR="$HOSTFY_ROOT/commands"
DOCKER_DIR="$HOSTFY_ROOT/docker"
CONFIG_DIR="$HOSTFY_ROOT/config"
CATALOG_DIR="$COMMANDS_DIR/catalog"
LOGS_DIR="$HOSTFY_ROOT/logs"

CONTAINERS_REGISTRY="$CONFIG_DIR/containers.json"
DOMAINS_REGISTRY="$CONFIG_DIR/domains.json"
SETTINGS_FILE="$CONFIG_DIR/settings.json"
LOG_FILE="$LOGS_DIR/hostfy.log"

# ========================================
# Logging Functions
# ========================================

log_message() {
    local level="$1"
    local message="$2"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')

    # Log to file
    echo "[$timestamp] [$level] $message" >> "$LOG_FILE"
}

log_info() {
    local message="$1"
    echo -e "${BLUE}ℹ${NC} $message"
    log_message "INFO" "$message"
}

log_success() {
    local message="$1"
    echo -e "${GREEN}✅${NC} $message"
    log_message "SUCCESS" "$message"
}

log_warning() {
    local message="$1"
    echo -e "${YELLOW}⚠${NC}  $message"
    log_message "WARNING" "$message"
}

log_error() {
    local message="$1"
    echo -e "${RED}❌${NC} $message" >&2
    log_message "ERROR" "$message"
}

log_debug() {
    local message="$1"
    if [[ "${HOSTFY_DEBUG:-false}" == "true" ]]; then
        echo -e "${MAGENTA}🔍${NC} $message"
        log_message "DEBUG" "$message"
    fi
}

log_step() {
    local message="$1"
    echo -e "${CYAN}▶${NC}  $message"
    log_message "STEP" "$message"
}

# ========================================
# Validation Functions
# ========================================

validate_container_name() {
    local name="$1"

    # Must be lowercase alphanumeric with hyphens and underscores
    if [[ ! "$name" =~ ^[a-z0-9_-]+$ ]]; then
        log_error "Invalid container name: $name"
        log_error "Container names must be lowercase alphanumeric with hyphens and underscores only"
        return 1
    fi

    return 0
}

validate_domain() {
    local domain="$1"

    # Basic domain validation
    if [[ ! "$domain" =~ ^[a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?(\.[a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?)*$ ]]; then
        log_error "Invalid domain format: $domain"
        return 1
    fi

    return 0
}

validate_port() {
    local port="$1"

    if [[ ! "$port" =~ ^[0-9]+$ ]] || [[ "$port" -lt 1 ]] || [[ "$port" -gt 65535 ]]; then
        log_error "Invalid port number: $port (must be 1-65535)"
        return 1
    fi

    return 0
}

validate_image() {
    local image="$1"

    # Basic image format validation (registry/repo:tag or repo:tag)
    if [[ ! "$image" =~ ^[a-zA-Z0-9._/-]+:[a-zA-Z0-9._-]+$ ]] && [[ ! "$image" =~ ^[a-zA-Z0-9._/-]+$ ]]; then
        log_error "Invalid image format: $image"
        return 1
    fi

    return 0
}

# ========================================
# Docker Helper Functions
# ========================================

check_docker() {
    if ! command -v docker &> /dev/null; then
        log_error "Docker is not installed or not in PATH"
        return 1
    fi

    if ! docker info &> /dev/null; then
        log_error "Docker daemon is not running"
        return 1
    fi

    return 0
}

check_docker_compose() {
    if ! command -v docker &> /dev/null; then
        return 1
    fi

    # Check for docker compose (v2) or docker-compose (v1)
    if docker compose version &> /dev/null; then
        return 0
    elif command -v docker-compose &> /dev/null; then
        return 0
    fi

    log_error "Docker Compose is not installed"
    return 1
}

get_docker_compose_cmd() {
    if docker compose version &> /dev/null 2>&1; then
        echo "docker compose"
    elif command -v docker-compose &> /dev/null; then
        echo "docker-compose"
    else
        echo ""
    fi
}

container_exists() {
    local name="$1"
    docker ps -a --format '{{.Names}}' | grep -q "^${name}$"
}

container_is_running() {
    local name="$1"
    docker ps --format '{{.Names}}' | grep -q "^${name}$"
}

network_exists() {
    local network="$1"
    docker network ls --format '{{.Name}}' | grep -q "^${network}$"
}

# ========================================
# JSON Helper Functions
# ========================================

ensure_json_file() {
    local file="$1"
    local default_content="${2:-{}}"

    if [[ ! -f "$file" ]]; then
        mkdir -p "$(dirname "$file")"
        echo "$default_content" > "$file"
    fi
}

json_get() {
    local file="$1"
    local query="$2"

    if [[ ! -f "$file" ]]; then
        echo ""
        return 1
    fi

    jq -r "$query" "$file" 2>/dev/null || echo ""
}

json_set() {
    local file="$1"
    local query="$2"
    local value="$3"

    ensure_json_file "$file"

    local tmp_file=$(mktemp)
    jq "$query = $value" "$file" > "$tmp_file" && mv "$tmp_file" "$file"
}

json_append() {
    local file="$1"
    local query="$2"
    local value="$3"

    ensure_json_file "$file" '{"containers":[]}'

    local tmp_file=$(mktemp)
    jq "$query += [$value]" "$file" > "$tmp_file" && mv "$tmp_file" "$file"
}

json_delete() {
    local file="$1"
    local query="$2"

    if [[ ! -f "$file" ]]; then
        return 0
    fi

    local tmp_file=$(mktemp)
    jq "del($query)" "$file" > "$tmp_file" && mv "$tmp_file" "$file"
}

# ========================================
# Confirmation Functions
# ========================================

confirm() {
    local prompt="$1"
    local default="${2:-n}"

    if [[ "${HOSTFY_FORCE:-false}" == "true" ]]; then
        return 0
    fi

    local yn
    if [[ "$default" == "y" ]]; then
        read -p "$prompt [Y/n] " yn
        yn=${yn:-y}
    else
        read -p "$prompt [y/N] " yn
        yn=${yn:-n}
    fi

    case "$yn" in
        [Yy]* ) return 0;;
        [Nn]* ) return 1;;
        * ) confirm "$prompt" "$default";;
    esac
}

# ========================================
# Directory Management
# ========================================

ensure_directories() {
    mkdir -p "$CONFIG_DIR"
    mkdir -p "$DOCKER_DIR"
    mkdir -p "$CATALOG_DIR"
    mkdir -p "$LOGS_DIR"
    mkdir -p "$DOCKER_DIR/traefik"
    mkdir -p "$DOCKER_DIR/templates"
    mkdir -p "$DOCKER_DIR/containers"
    mkdir -p "$DOCKER_DIR/network"
}

# ========================================
# Port Management
# ========================================

is_port_available() {
    local port="$1"
    ! nc -z localhost "$port" 2>/dev/null
}

find_available_port() {
    local start_port="${1:-3000}"
    local port="$start_port"

    while ! is_port_available "$port"; do
        ((port++))
        if [[ $port -gt 65535 ]]; then
            log_error "No available ports found"
            return 1
        fi
    done

    echo "$port"
}

# ========================================
# String Manipulation
# ========================================

generate_random_string() {
    local length="${1:-32}"
    LC_ALL=C tr -dc 'a-zA-Z0-9' < /dev/urandom | head -c "$length"
}

generate_password() {
    local length="${1:-16}"
    LC_ALL=C tr -dc 'A-Za-z0-9!@#$%^&*' < /dev/urandom | head -c "$length"
}

slugify() {
    local string="$1"
    echo "$string" | tr '[:upper:]' '[:lower:]' | tr -cs '[:alnum:]' '-' | sed 's/^-//' | sed 's/-$//'
}

# ========================================
# Environment Variable Parsing
# ========================================

parse_env_file() {
    local env_file="$1"

    if [[ ! -f "$env_file" ]]; then
        log_error "Environment file not found: $env_file"
        return 1
    fi

    # Read env file and output as key=value pairs
    grep -v '^#' "$env_file" | grep -v '^[[:space:]]*$' | while IFS= read -r line; do
        echo "$line"
    done
}

# ========================================
# Time Functions
# ========================================

get_timestamp() {
    date -u +"%Y-%m-%dT%H:%M:%SZ"
}

# ========================================
# Registry Functions
# ========================================

registry_add_container() {
    local container_data="$1"

    ensure_json_file "$CONTAINERS_REGISTRY" '{"containers":[]}'

    local tmp_file=$(mktemp)
    jq ".containers += [$container_data]" "$CONTAINERS_REGISTRY" > "$tmp_file" && mv "$tmp_file" "$CONTAINERS_REGISTRY"
}

registry_get_container() {
    local name="$1"

    if [[ ! -f "$CONTAINERS_REGISTRY" ]]; then
        echo ""
        return 1
    fi

    jq -r ".containers[] | select(.name == \"$name\")" "$CONTAINERS_REGISTRY"
}

registry_delete_container() {
    local name="$1"

    if [[ ! -f "$CONTAINERS_REGISTRY" ]]; then
        return 0
    fi

    local tmp_file=$(mktemp)
    jq ".containers |= map(select(.name != \"$name\"))" "$CONTAINERS_REGISTRY" > "$tmp_file" && mv "$tmp_file" "$CONTAINERS_REGISTRY"
}

registry_list_containers() {
    if [[ ! -f "$CONTAINERS_REGISTRY" ]]; then
        echo "[]"
        return 0
    fi

    jq -r '.containers[]' "$CONTAINERS_REGISTRY"
}

# ========================================
# Cleanup Functions
# ========================================

cleanup_temp_files() {
    local pattern="${1:-/tmp/hostfy-*}"
    find /tmp -name "hostfy-*" -type f -mtime +1 -delete 2>/dev/null || true
}

# ========================================
# Dependency Checks
# ========================================

check_dependencies() {
    local missing_deps=()

    if ! command -v docker &> /dev/null; then
        missing_deps+=("docker")
    fi

    if ! command -v jq &> /dev/null; then
        missing_deps+=("jq")
    fi

    if [[ ${#missing_deps[@]} -gt 0 ]]; then
        log_error "Missing required dependencies: ${missing_deps[*]}"
        log_info "Please install missing dependencies and try again"
        return 1
    fi

    return 0
}

# ========================================
# Initialize Utils
# ========================================

init_utils() {
    ensure_directories

    # Initialize log file
    if [[ ! -f "$LOG_FILE" ]]; then
        touch "$LOG_FILE"
    fi

    # Initialize registries
    ensure_json_file "$CONTAINERS_REGISTRY" '{"containers":[]}'
    ensure_json_file "$DOMAINS_REGISTRY" '{"domains":[]}'
}

# Auto-initialize on source
init_utils
