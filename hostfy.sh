#!/bin/bash
# commands/hostfy.sh
# Main CLI for Hostfy Container Management System

set -euo pipefail

# ========================================
# Configuration
# ========================================
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB_DIR="$SCRIPT_DIR/lib"

# Load libraries
source "$LIB_DIR/utils.sh"
source "$LIB_DIR/network-manager.sh"
source "$LIB_DIR/template-engine.sh"
source "$LIB_DIR/domain-manager.sh"
source "$LIB_DIR/container-manager.sh"
source "$LIB_DIR/catalog-manager.sh"

VERSION="1.0.0"

# ========================================
# Container Operations Commands
# ========================================

cmd_install() {
    local container_name="${1:-}"

    if [[ -z "$container_name" ]]; then
        log_error "Container name is required"
        log_info "Usage: hostfy install <container-name> [options]"
        return 1
    fi

    shift

    # Check if installing from catalog
    local from_catalog=false
    if catalog_exists "$container_name" 2>/dev/null; then
        from_catalog=true
    fi

    if [[ "$from_catalog" == "true" ]]; then
        # Install from catalog
        catalog_install "$container_name" "$@"
    else
        # Install custom container
        container_install "$container_name" "$@"
    fi
}

cmd_update() {
    local container_name="${1:-}"

    if [[ -z "$container_name" ]]; then
        log_error "Container name is required"
        log_info "Usage: hostfy update <container-name> [options]"
        return 1
    fi

    shift
    container_update "$container_name" "$@"
}

cmd_delete() {
    local container_name="${1:-}"

    if [[ -z "$container_name" ]]; then
        log_error "Container name is required"
        log_info "Usage: hostfy delete <container-name> [--volumes]"
        return 1
    fi

    shift

    local remove_volumes=false

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --volumes|-v)
                remove_volumes=true
                shift
                ;;
            *)
                log_error "Unknown option: $1"
                return 1
                ;;
        esac
    done

    container_delete "$container_name" "$remove_volumes"
}

cmd_restart() {
    local container_name="${1:-}"

    if [[ -z "$container_name" ]]; then
        log_error "Container name is required"
        log_info "Usage: hostfy restart <container-name>"
        return 1
    fi

    container_restart "$container_name"
}

cmd_pause() {
    local container_name="${1:-}"

    if [[ -z "$container_name" ]]; then
        log_error "Container name is required"
        log_info "Usage: hostfy pause <container-name>"
        return 1
    fi

    container_pause "$container_name"
}

cmd_resume() {
    local container_name="${1:-}"

    if [[ -z "$container_name" ]]; then
        log_error "Container name is required"
        log_info "Usage: hostfy resume <container-name>"
        return 1
    fi

    container_resume "$container_name"
}

cmd_list() {
    container_list
}

cmd_status() {
    local container_name="${1:-}"

    if [[ -z "$container_name" ]]; then
        log_error "Container name is required"
        log_info "Usage: hostfy status <container-name>"
        return 1
    fi

    container_status "$container_name"
}

cmd_logs() {
    local container_name="${1:-}"

    if [[ -z "$container_name" ]]; then
        log_error "Container name is required"
        log_info "Usage: hostfy logs <container-name> [--follow] [--tail <lines>]"
        return 1
    fi

    shift

    local follow=false
    local tail=50

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --follow|-f)
                follow=true
                shift
                ;;
            --tail|-n)
                tail="$2"
                shift 2
                ;;
            *)
                log_error "Unknown option: $1"
                return 1
                ;;
        esac
    done

    container_logs "$container_name" "$follow" "$tail"
}

# ========================================
# Domain Operations Commands
# ========================================

cmd_domain() {
    local container_name="${1:-}"

    if [[ -z "$container_name" ]]; then
        log_error "Container name is required"
        log_info "Usage: hostfy domain <container-name> [--add|--remove|--list] <domain>"
        return 1
    fi

    shift

    local action=""
    local domain=""
    local port="80"

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --add)
                action="add"
                domain="$2"
                shift 2
                ;;
            --remove)
                action="remove"
                domain="$2"
                shift 2
                ;;
            --list)
                action="list"
                shift
                ;;
            --port)
                port="$2"
                shift 2
                ;;
            *)
                log_error "Unknown option: $1"
                return 1
                ;;
        esac
    done

    case "$action" in
        add)
            if [[ -z "$domain" ]]; then
                log_error "Domain is required"
                return 1
            fi
            domain_add "$container_name" "$domain" "$port"
            ;;
        remove)
            if [[ -z "$domain" ]]; then
                log_error "Domain is required"
                return 1
            fi
            domain_remove "$container_name" "$domain"
            ;;
        list)
            domain_list "$container_name"
            ;;
        *)
            log_error "Action is required: --add, --remove, or --list"
            return 1
            ;;
    esac
}

# ========================================
# Catalog Operations Commands
# ========================================

cmd_catalog() {
    local subcommand="${1:-list}"

    if [[ $# -gt 0 ]]; then
        shift
    fi

    case "$subcommand" in
        update)
            catalog_update true
            ;;
        list)
            local category=""
            local tag=""

            while [[ $# -gt 0 ]]; do
                case "$1" in
                    --category)
                        category="$2"
                        shift 2
                        ;;
                    --tag)
                        tag="$2"
                        shift 2
                        ;;
                    *)
                        log_error "Unknown option: $1"
                        return 1
                        ;;
                esac
            done

            if [[ -n "$category" ]]; then
                echo "Available containers in '$category':"
            elif [[ -n "$tag" ]]; then
                echo "Available containers tagged '$tag':"
            else
                echo "Available containers:"
            fi
            echo ""
            catalog_list "$category" "$tag"
            ;;
        search)
            if [[ $# -eq 0 ]]; then
                log_error "Search term is required"
                log_info "Usage: hostfy catalog search <term>"
                return 1
            fi
            catalog_search "$1"
            ;;
        info)
            if [[ $# -eq 0 ]]; then
                log_error "Container ID is required"
                log_info "Usage: hostfy catalog info <container-id>"
                return 1
            fi
            catalog_info "$1"
            ;;
        versions)
            if [[ $# -eq 0 ]]; then
                log_error "Container ID is required"
                log_info "Usage: hostfy catalog versions <container-id>"
                return 1
            fi
            catalog_versions "$1"
            ;;
        categories)
            catalog_categories
            ;;
        stats)
            catalog_stats
            ;;
        *)
            log_error "Unknown catalog subcommand: $subcommand"
            echo ""
            echo "Available subcommands:"
            echo "  update       - Update catalog from repository"
            echo "  list         - List all available containers"
            echo "  search       - Search containers by term"
            echo "  info         - Show container details"
            echo "  versions     - Show available versions"
            echo "  categories   - List all categories"
            echo "  stats        - Show catalog statistics"
            return 1
            ;;
    esac
}

# ========================================
# System Operations Commands
# ========================================

cmd_init() {
    log_info "Initializing Hostfy system..."
    bash "$SCRIPT_DIR/initialize.sh"
}

cmd_version() {
    echo "Hostfy v$VERSION"
}

# ========================================
# Help System
# ========================================

show_help() {
    cat <<EOF
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
   HOSTFY - Container Management System v$VERSION
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

USAGE:
    hostfy <command> [options]

CONTAINER OPERATIONS:
    install <name>         Install a container (from catalog or custom)
    update <name>          Update existing container
    delete <name>          Remove container
      --volumes, -v        Also remove volumes
    restart <name>         Restart container
    pause <name>           Pause container
    resume <name>          Resume paused container
    list                   List all containers
    status <name>          Show container status
    logs <name>            View container logs
      --follow, -f         Follow log output
      --tail, -n <lines>   Number of lines to show (default: 50)

DOMAIN OPERATIONS:
    domain <name>          Manage container domains
      --add <domain>       Add domain to container
      --remove <domain>    Remove domain from container
      --list               List all domains for container
      --port <port>        Port for domain (default: 80)

CATALOG OPERATIONS:
    catalog update         Update catalog from Git repository
    catalog list           List all available containers
      --category <cat>     Filter by category
      --tag <tag>          Filter by tag
    catalog search <term>  Search containers
    catalog info <id>      Show container details
    catalog versions <id>  List available versions
    catalog categories     List all categories
    catalog stats          Show catalog statistics

INSTALLATION OPTIONS:
    --image <image:tag>    Container image (required for custom)
    --port <port>          Expose port (default: 80)
    --domain <domain>      Configure domain (requires Traefik)
    --env KEY=VALUE        Set environment variable
    --env-file <path>      Load environment from file
    --volume <vol>         Mount volume
    --with-deps            Install dependencies automatically
    --interactive          Interactive configuration wizard
    --version <tag>        Specify container version (catalog)

SYSTEM OPERATIONS:
    init                   Initialize Hostfy system
    version                Show version
    help, --help, -h       Show this help

EXAMPLES:
    # Initialize system
    hostfy init

    # Install from catalog
    hostfy catalog list --category database
    hostfy install postgres --with-deps
    hostfy install n8n --domain n8n.example.com --interactive

    # Custom container
    hostfy install myapp --image nginx:latest --port 80 --domain api.example.com

    # Manage domains
    hostfy domain myapp --add api2.example.com
    hostfy domain myapp --list

    # Lifecycle
    hostfy restart postgres
    hostfy logs myapp --follow

GLOBAL OPTIONS:
    --verbose, -v          Verbose output (set HOSTFY_DEBUG=true)
    --force, -f            Force operation (set HOSTFY_FORCE=true)

ENVIRONMENT VARIABLES:
    HOSTFY_DEBUG           Enable debug logging
    HOSTFY_FORCE           Skip confirmation prompts
    HOSTFY_NETWORK         Docker network name (default: hostfy-network)
    CATALOG_URL            Custom catalog URL

For more information, visit: https://github.com/your-org/hostfy
EOF
}

# ========================================
# Main Command Router
# ========================================

main() {
    local command="${1:-}"

    if [[ -z "$command" ]]; then
        show_help
        exit 0
    fi

    shift

    # Check dependencies before running commands (except help and version)
    if [[ "$command" != "help" && "$command" != "--help" && "$command" != "-h" && "$command" != "version" ]]; then
        if ! check_dependencies; then
            exit 1
        fi
    fi

    case "$command" in
        # Container operations
        install)
            cmd_install "$@"
            ;;
        update)
            cmd_update "$@"
            ;;
        delete)
            cmd_delete "$@"
            ;;
        restart)
            cmd_restart "$@"
            ;;
        pause)
            cmd_pause "$@"
            ;;
        resume)
            cmd_resume "$@"
            ;;
        list)
            cmd_list "$@"
            ;;
        status)
            cmd_status "$@"
            ;;
        logs)
            cmd_logs "$@"
            ;;

        # Domain operations
        domain)
            cmd_domain "$@"
            ;;

        # Catalog operations
        catalog)
            cmd_catalog "$@"
            ;;

        # System operations
        init)
            cmd_init "$@"
            ;;
        version)
            cmd_version
            ;;
        help|--help|-h)
            show_help
            ;;

        # Unknown command
        *)
            log_error "Unknown command: $command"
            echo ""
            show_help
            exit 1
            ;;
    esac
}

# Run main function
main "$@"
