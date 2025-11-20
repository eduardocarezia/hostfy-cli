#!/bin/bash
# uninstall.sh
# Script to uninstall Hostfy and remove all related components

# Directories
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOSTFY_ROOT="$(dirname "$SCRIPT_DIR")"
DOCKER_DIR="$HOSTFY_ROOT/docker"
CONFIG_DIR="$HOSTFY_ROOT/config"
LOGS_DIR="$HOSTFY_ROOT/logs"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

log_info() { echo -e "${NC}ℹ $1${NC}"; }
log_success() { echo -e "${GREEN}✅ $1${NC}"; }
log_warning() { echo -e "${YELLOW}⚠  $1${NC}"; }
log_error() { echo -e "${RED}❌ $1${NC}"; }

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "   🗑️  Hostfy Uninstaller"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
log_warning "This script will remove Hostfy and all its components."
log_warning "Running containers will be stopped and removed."
echo ""
read -p "Are you sure you want to continue? (y/N) " -n 1 -r

if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    log_info "Uninstall cancelled."
    exit 0
fi

# 1. Stop API
log_info "Stopping API server..."
if [[ -f "$SCRIPT_DIR/hostfy.sh" ]]; then
    bash "$SCRIPT_DIR/hostfy.sh" api stop >/dev/null 2>&1
fi
# Fallback: kill by port 3000 if still running
if lsof -i :3000 | grep -q LISTEN; then
    log_info "Killing process on port 3000..."
    lsof -ti :3000 | xargs kill -9 2>/dev/null
fi

# 2. Stop and Remove Traefik
log_info "Stopping Traefik..."
if [[ -d "$DOCKER_DIR/traefik" ]]; then
    cd "$DOCKER_DIR/traefik"
    docker compose down >/dev/null 2>&1 || docker-compose down >/dev/null 2>&1
fi

# 3. Stop and Remove Managed Containers
log_info "Stopping managed containers..."
# Find all containers with label hostfy.managed=true
containers=$(docker ps -a --filter "label=hostfy.managed=true" --format "{{.Names}}")
if [[ -n "$containers" ]]; then
    echo "$containers" | while read -r container; do
        log_info "Removing container: $container"
        docker stop "$container" >/dev/null 2>&1
        docker rm "$container" >/dev/null 2>&1
    done
else
    log_info "No managed containers found."
fi

# 4. Remove Docker Network
log_info "Removing Docker network..."
if docker network ls | grep -q "hostfy-network"; then
    docker network rm hostfy-network >/dev/null 2>&1
    log_success "Network removed"
else
    log_info "Network not found"
fi

# 5. Remove Global CLI
log_info "Removing global CLI..."
if [[ -L "/usr/local/bin/hostfy" ]]; then
    rm "/usr/local/bin/hostfy"
    log_success "CLI link removed"
elif [[ -f "/usr/local/bin/hostfy" ]]; then
     # Try with sudo if permission denied
     if rm "/usr/local/bin/hostfy" 2>/dev/null; then
        log_success "CLI link removed"
     else
        sudo rm "/usr/local/bin/hostfy"
        log_success "CLI link removed (with sudo)"
     fi
fi

# 6. Remove Files
echo ""
log_warning "Do you want to delete all Hostfy files and data?"
log_warning "This includes configuration, logs, and database volumes in $HOSTFY_ROOT"
read -p "Delete files? (y/N) " -n 1 -r
echo ""
if [[ $REPLY =~ ^[Yy]$ ]]; then
    log_info "Removing files..."
    # Be careful not to delete system root if variables are empty
    if [[ -n "$HOSTFY_ROOT" && "$HOSTFY_ROOT" != "/" ]]; then
        rm -rf "$HOSTFY_ROOT"
        log_success "Files removed"
    else
        log_error "Safety check failed: HOSTFY_ROOT is empty or root."
    fi
else
    log_info "Files kept at $HOSTFY_ROOT"
fi

echo ""
log_success "Uninstallation complete."
