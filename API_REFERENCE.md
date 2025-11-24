# hostfy CLI - API Reference

**Version**: 0.1.0
**Language**: Go
**Framework**: Cobra CLI

---

## Table of Contents

1. [Overview](#overview)
2. [Installation](#installation)
3. [Architecture](#architecture)
4. [Commands Reference](#commands-reference)
5. [Data Models](#data-models)
6. [Storage Structure](#storage-structure)
7. [Catalog Format](#catalog-format)
8. [Response Formats](#response-formats)
9. [Error Codes](#error-codes)

---

## Overview

hostfy is a CLI tool for simplified self-hosted app deployment. It manages Docker containers, configures Traefik for SSL/routing, and handles dependencies like PostgreSQL and Redis automatically.

### Key Features

- One-command app installation from catalog
- Automatic SSL via Traefik + Let's Encrypt
- Dependency management (PostgreSQL, Redis)
- Multi-container stack support
- Secret management and preservation
- Database lifecycle management

---

## Installation

```bash
curl -fsSL https://raw.githubusercontent.com/eduardocarezia/hostfy-cli/main/scripts/install.sh | sudo bash
```

### Requirements

- Linux (Ubuntu 20.04+, Debian 11+)
- Root access
- Ports 80 and 443 available
- Domain configured in DNS

---

## Architecture

```
/etc/hostfy/
├── config.json          # Global configuration
├── secrets.json         # System secrets (postgres password, etc)
├── secrets_backup/      # App secrets backup for reinstallation
│   └── <app>.json
└── apps/
    └── <app>.json       # Installed app configuration
```

### Docker Network

All containers run on `hostfy_network` (Docker bridge network).

### Managed Services

| Service | Container Name | Default Port |
|---------|---------------|--------------|
| Traefik | `hostfy_traefik` | 80, 443 |
| PostgreSQL | `hostfy_postgres` | 5432 |
| Redis | `hostfy_redis` | 6379 |

---

## Commands Reference

### `hostfy init`

Initializes hostfy on the server.

**Syntax:**
```bash
hostfy init [--catalog-url <URL>]
```

**Flags:**
| Flag | Type | Default | Description |
|------|------|---------|-------------|
| `--catalog-url` | string | GitHub catalog URL | Custom catalog URL |

**Actions:**
1. Creates directories (`/etc/hostfy/`, `/etc/hostfy/apps/`)
2. Generates system secrets (PostgreSQL password, system key)
3. Creates Docker network (`hostfy_network`)
4. Starts Traefik container

**Exit Codes:**
- `0`: Success
- `1`: Docker connection error, directory creation error, Traefik start error

---

### `hostfy catalog`

Lists available apps from the catalog.

**Syntax:**
```bash
hostfy catalog [--refresh]
```

**Flags:**
| Flag | Type | Default | Description |
|------|------|---------|-------------|
| `--refresh` | bool | false | Force catalog update |

**Output:**
Lists all apps with name, description, and dependencies.

---

### `hostfy install`

Installs an app from the catalog.

**Syntax:**
```bash
hostfy install <app> --domain <domain> [--name <stack-name>] [--env KEY=VALUE...]
```

**Arguments:**
| Argument | Required | Description |
|----------|----------|-------------|
| `<app>` | Yes | App ID from catalog |

**Flags:**
| Flag | Type | Required | Description |
|------|------|----------|-------------|
| `--domain` | string | Yes | Domain for the app |
| `--name` | string | No | Custom stack name (defaults to app ID) |
| `--env` | string[] | No | Additional environment variables |

**Actions:**
1. Validates app doesn't already exist
2. Fetches app definition from catalog
3. Ensures dependencies (postgres, redis)
4. Creates database if needed
5. Resolves template variables
6. Pulls Docker image(s)
7. Creates and starts container(s)
8. Configures Traefik labels for routing
9. Saves app configuration

**Template Variables:**
| Variable | Description |
|----------|-------------|
| `{{APP_NAME}}` | Stack/app name |
| `{{APP_DOMAIN}}` | Primary domain |
| `{{APP_DATABASE}}` | Generated database name |
| `{{SERVICE_postgres_HOST}}` | PostgreSQL container name |
| `{{SERVICE_postgres_USER}}` | PostgreSQL username |
| `{{SERVICE_postgres_PASSWORD}}` | PostgreSQL password |
| `{{SERVICE_redis_HOST}}` | Redis container name |
| `{{GENERATE_SECRET_N}}` | Random secret of N characters |

**Exit Codes:**
- `0`: Success
- `1`: App already exists, catalog error, Docker error, dependency error

---

### `hostfy remove`

Removes an installed app.

**Syntax:**
```bash
hostfy remove <app> [--keep-data]
```

**Arguments:**
| Argument | Required | Description |
|----------|----------|-------------|
| `<app>` | Yes | Installed app name |

**Flags:**
| Flag | Type | Default | Description |
|------|------|---------|-------------|
| `--keep-data` | bool | false | Keep volumes and secrets for reinstallation |

**Actions (default):**
1. Stops all containers
2. Removes all containers
3. Drops database (if exists)
4. Removes Docker volumes
5. Removes secrets backup
6. Removes app configuration file

**Actions (--keep-data):**
1. Stops all containers
2. Removes all containers
3. Saves secrets backup
4. Removes app configuration file
5. Keeps volumes and database

---

### `hostfy uninstall`

Alias for `hostfy remove`.

**Syntax:**
```bash
hostfy uninstall <app> [--keep-data]
```

---

### `hostfy update`

Updates configuration of an installed app.

**Syntax:**
```bash
hostfy update <app> [--env KEY=VALUE...] [--domain <new-domain>]
```

**Arguments:**
| Argument | Required | Description |
|----------|----------|-------------|
| `<app>` | Yes | Installed app name |

**Flags:**
| Flag | Type | Description |
|------|------|-------------|
| `--env` | string[] | Environment variables to change |
| `--domain` | string | New domain |

**Actions:**
1. Loads current app configuration
2. Applies environment variable changes
3. Updates domain (and related env vars)
4. Stops and removes old container
5. Creates new container with updated config
6. Starts new container
7. Saves updated configuration

---

### `hostfy config`

Alias for `hostfy update --domain`.

**Syntax:**
```bash
hostfy config <app> --domain <new-domain>
```

---

### `hostfy pull`

Updates catalog and/or app image.

**Syntax:**
```bash
hostfy pull [app]
```

**Arguments:**
| Argument | Required | Description |
|----------|----------|-------------|
| `[app]` | No | App name (if omitted, only updates catalog) |

**Actions (no app):**
1. Fetches and updates local catalog cache

**Actions (with app):**
1. Fetches updated catalog
2. Compares current image with catalog image
3. Identifies new environment variables from catalog
4. Pulls new Docker image
5. Updates container with new image
6. Merges new env vars (preserves user customizations)
7. Saves updated configuration

---

### `hostfy list`

Lists installed apps with status.

**Syntax:**
```bash
hostfy list
```

**Output Format:**
```
Apps instalados:

  ● app-name  rodando
    URL:    https://domain.com
    Imagem: image:tag

  ○ app-name  parado
    URL:    https://domain.com
    Imagem: image:tag
```

---

### `hostfy status`

Returns complete system status as JSON.

**Syntax:**
```bash
hostfy status
```

**Response Schema:**
```json
{
  "hostfy_version": "string",
  "system": {
    "docker": "string",
    "os": "string",
    "arch": "string"
  },
  "services": {
    "traefik": {
      "status": "running|stopped",
      "image": "string"
    },
    "postgres": {
      "status": "running|stopped",
      "image": "string",
      "databases": ["string"]
    },
    "redis": {
      "status": "running|stopped",
      "image": "string"
    }
  },
  "apps": [
    {
      "name": "string",
      "domain": "string",
      "status": "running|stopped|partial",
      "image": "string",
      "is_stack": "boolean",
      "containers": [
        {
          "name": "string",
          "status": "running|stopped",
          "domain": "string",
          "is_main": "boolean"
        }
      ]
    }
  ]
}
```

---

### `hostfy logs`

Shows logs from an app container.

**Syntax:**
```bash
hostfy logs <app> [-f] [--tail <N>] [-c <container>]
```

**Arguments:**
| Argument | Required | Description |
|----------|----------|-------------|
| `<app>` | Yes | App name |

**Flags:**
| Flag | Type | Default | Description |
|------|------|---------|-------------|
| `-f, --follow` | bool | false | Follow logs in real-time |
| `--tail` | string | "100" | Number of lines to show |
| `-c, --container` | string | main | Container name (for stacks) |

**Stack Behavior:**
- Without `-c`: shows logs from main container
- With `-c <name>`: shows logs from specified container

---

### `hostfy secrets`

Shows credentials and sensitive environment variables.

**Syntax:**
```bash
hostfy secrets <app>
```

**Output Format:**
```
Credenciais de app-name

  URL: https://domain.com

  Variáveis de ambiente:
    KEY=value
    ...

  Database:
    Host:     hostfy_postgres
    Port:     5432
    Database: app_db
    User:     hostfy
    Password: ****
```

---

### `hostfy start`

Starts an app or all services.

**Syntax:**
```bash
hostfy start <app|all>
```

**Arguments:**
| Argument | Values | Description |
|----------|--------|-------------|
| `<target>` | app name or "all" | What to start |

**Actions (app):**
1. Starts all containers in the stack

**Actions (all):**
1. Starts Traefik
2. Starts PostgreSQL
3. Starts Redis
4. Starts all installed apps

---

### `hostfy stop`

Stops an app.

**Syntax:**
```bash
hostfy stop <app>
```

**Actions:**
1. Stops all containers in the stack

---

### `hostfy restart`

Restarts an app or all services.

**Syntax:**
```bash
hostfy restart <app|all>
```

**Arguments:**
| Argument | Values | Description |
|----------|--------|-------------|
| `<target>` | app name or "all" | What to restart |

---

### `hostfy db`

Database management commands.

#### `hostfy db list`

Lists all databases in PostgreSQL.

**Syntax:**
```bash
hostfy db list
```

**Output Format:**
```
Databases no PostgreSQL:

  • n8n_db (usado por n8n)
  • orphan_db (órfão)
```

#### `hostfy db remove`

Removes an orphan database.

**Syntax:**
```bash
hostfy db remove <database> [--force]
```

**Flags:**
| Flag | Type | Default | Description |
|------|------|---------|-------------|
| `--force` | bool | false | Skip confirmation prompt |

**Validation:**
- Fails if database is in use by an app
- Requires confirmation (unless --force)

---

### `hostfy cleanup`

Removes orphan containers and databases.

**Syntax:**
```bash
hostfy cleanup [--force]
```

**Flags:**
| Flag | Type | Default | Description |
|------|------|---------|-------------|
| `--force` | bool | false | Remove without confirmation |

**Actions (without --force):**
1. Lists orphan containers (with `hostfy.managed=true` label)
2. Lists orphan databases
3. Shows what would be removed

**Actions (with --force):**
1. Stops and removes orphan containers
2. Drops orphan databases

---

### `hostfy upgrade`

Updates hostfy CLI to latest version.

**Syntax:**
```bash
hostfy upgrade [--force]
```

**Flags:**
| Flag | Type | Default | Description |
|------|------|---------|-------------|
| `--force` | bool | false | Reinstall even if already latest |

**Actions:**
1. Checks current version
2. Fetches latest version from GitHub
3. Clones repository
4. Compiles new binary
5. Replaces current binary

**Requirements:**
- Go installed on system

---

### `hostfy version`

Shows hostfy version.

**Syntax:**
```bash
hostfy version
```

**Output:**
```
hostfy version 0.1.0
```

---

## Data Models

### AppConfig (Stored in /etc/hostfy/apps/<name>.json)

```typescript
interface AppConfig {
  name: string;              // Stack name
  catalog_app: string;       // App ID from catalog
  domain: string;            // Primary domain
  installed_at: string;      // ISO 8601 timestamp
  updated_at: string;        // ISO 8601 timestamp
  image: string;             // Docker image (single container mode)
  image_pulled_at: string;   // ISO 8601 timestamp
  container_id?: string;     // Docker container ID (single mode)
  database?: string;         // Database name if created
  env: Record<string, string>;  // Resolved environment variables
  volumes?: string[];        // Resolved volume mounts
  command?: string;          // Container command
  port?: number;             // Container port

  // Stack mode (multi-container)
  is_stack?: boolean;
  containers?: ContainerConfig[];
  shared_env?: Record<string, string>;
}

interface ContainerConfig {
  name: string;              // Container suffix (e.g., "editor", "worker")
  container_id: string;      // Docker container ID
  image: string;             // Docker image
  domain?: string;           // Domain (if exposed via Traefik)
  port?: number;             // Container port
  command?: string;          // Container command
  env?: Record<string, string>;
  volumes?: string[];
  is_main?: boolean;         // Main container receives primary domain
}
```

### System Config (/etc/hostfy/config.json)

```typescript
interface Config {
  version: string;           // Config version
  catalog_url: string;       // Catalog JSON URL
  catalog_updated_at?: string;
  network: string;           // Docker network name
  traefik: {
    dashboard: boolean;
  };
}
```

### System Secrets (/etc/hostfy/secrets.json)

```typescript
interface Secrets {
  postgres_password: string;
  redis_password?: string;
  system_key: string;
}
```

---

## Storage Structure

```
/etc/hostfy/
├── config.json              # Global config
├── secrets.json             # System passwords (0600 permissions)
├── secrets_backup/          # Preserved secrets for reinstall
│   └── <app>.json          # Per-app sensitive secrets backup
└── apps/
    └── <app>.json          # Installed app config
```

### Preserved Secrets

When using `--keep-data`, these environment variables are backed up:
- `N8N_ENCRYPTION_KEY`
- `SECRET_KEY_BASE`
- `KEY`
- `SECRET`
- `AUTHENTICATION_API_KEY`
- `MINIO_ROOT_USER`
- `MINIO_ROOT_PASSWORD`

---

## Catalog Format

### Catalog Structure

```typescript
interface Catalog {
  version: string;
  updated_at: string;
  services: Record<string, Service>;
  apps: Record<string, App>;
}

interface Service {
  image: string;
  restart?: string;
  command?: string;
  env?: Record<string, string>;
  volumes?: string[];
  ports?: string[];
  healthcheck?: {
    test: string[];
    interval: string;
    retries: number;
  };
}

interface App {
  name: string;
  description: string;
  dependencies?: string[];   // ["postgres", "redis"]

  // Single container mode (legacy)
  image?: string;
  port?: number;
  console_port?: number;
  command?: string;
  env?: Record<string, string>;
  volumes?: string[];
  traefik?: TraefikConfig;

  // Stack mode (multi-container)
  containers?: Container[];
  shared_env?: Record<string, string>;

  // User-configurable vars
  user_env?: UserEnvVar[];
}

interface Container {
  name: string;              // Container suffix
  image: string;
  port?: number;
  command?: string;
  env?: Record<string, string>;
  volumes?: string[];
  traefik?: TraefikConfig;
  is_main?: boolean;
  user_env?: UserEnvVar[];
}

interface UserEnvVar {
  key: string;
  prompt: string;
  default: string;
}

interface TraefikConfig {
  routes?: {
    subdomain: string;
    port: number;
  }[];
}
```

### Available Apps in Default Catalog

| App ID | Name | Dependencies | Type |
|--------|------|--------------|------|
| `n8n` | n8n Workflow Automation | postgres, redis | Stack (3 containers) |
| `uptime-kuma` | Uptime Kuma | - | Single |
| `minio` | MinIO Object Storage | - | Single |
| `portainer` | Portainer Docker UI | - | Single |
| `nocodb` | NocoDB | postgres | Single |
| `ghost` | Ghost CMS | - | Single |
| `gitea` | Gitea Git Server | postgres | Single |
| `plausible` | Plausible Analytics | postgres | Single |
| `metabase` | Metabase BI | postgres | Single |
| `directus` | Directus Headless CMS | postgres, redis | Single |
| `chatwoot` | Chatwoot Support | postgres, redis | Single |
| `evolution-api` | Evolution WhatsApp API | postgres, redis | Single |

---

## Response Formats

### Success Messages

CLI uses colored output for user feedback:
- Green checkmark for success
- Yellow warning for non-critical issues
- Red X for errors

### Status Command JSON

The `hostfy status` command outputs structured JSON suitable for API consumption.

Example:
```json
{
  "hostfy_version": "1.0.0",
  "system": {
    "docker": "24.0.7",
    "os": "linux",
    "arch": "amd64"
  },
  "services": {
    "traefik": {
      "status": "running",
      "image": "traefik:v2.10"
    },
    "postgres": {
      "status": "running",
      "image": "postgres:15-alpine",
      "databases": ["n8n_db", "nocodb_db"]
    },
    "redis": {
      "status": "running",
      "image": "redis:7-alpine"
    }
  },
  "apps": [
    {
      "name": "n8n",
      "domain": "n8n.example.com",
      "status": "running",
      "image": "n8nio/n8n:latest",
      "is_stack": true,
      "containers": [
        {
          "name": "editor",
          "status": "running",
          "domain": "n8n.example.com",
          "is_main": true
        },
        {
          "name": "webhook",
          "status": "running",
          "domain": "n8n.example.com"
        },
        {
          "name": "worker",
          "status": "running"
        }
      ]
    }
  ]
}
```

---

## Error Codes

| Exit Code | Meaning |
|-----------|---------|
| 0 | Success |
| 1 | General error (Docker, file system, validation) |

### Common Error Scenarios

| Error | Cause | Resolution |
|-------|-------|------------|
| "App already exists" | Trying to install with same name | Use `--name` for different stack name |
| "App not found" | App ID not in catalog | Run `hostfy catalog` to see available apps |
| "Docker connection error" | Docker daemon not running | Start Docker service |
| "Database in use" | Trying to remove DB used by app | Remove app first |
| "Container not found" | Invalid container name for stack | Check `hostfy logs <app>` for available containers |

---

## Docker Labels

hostfy adds the following labels to managed containers:

| Label | Value | Purpose |
|-------|-------|---------|
| `hostfy.managed` | `true` | Identifies hostfy-managed containers |
| `traefik.enable` | `true` | Enables Traefik routing |
| `traefik.http.routers.<name>.rule` | `Host(\`domain\`)` | Domain routing |
| `traefik.http.routers.<name>.entrypoints` | `websecure` | HTTPS entrypoint |
| `traefik.http.routers.<name>.tls.certresolver` | `letsencrypt` | SSL certificate |
| `traefik.http.services.<name>.loadbalancer.server.port` | Port number | Container port |

---

## API Integration Notes

### For Building an HTTP API Wrapper

1. **Command Execution**: Each CLI command can be wrapped as an API endpoint
2. **JSON Output**: Use `hostfy status` for structured data
3. **Configuration Reading**: Parse `/etc/hostfy/apps/*.json` for app details
4. **Real-time Logs**: Use `hostfy logs -f` with streaming
5. **Authentication**: Add your own auth layer (CLI has none)

### Suggested API Endpoints Mapping

| HTTP Method | Endpoint | CLI Command |
|-------------|----------|-------------|
| POST | `/api/init` | `hostfy init` |
| GET | `/api/catalog` | `hostfy catalog` |
| POST | `/api/apps` | `hostfy install` |
| DELETE | `/api/apps/:name` | `hostfy remove` |
| PATCH | `/api/apps/:name` | `hostfy update` |
| GET | `/api/apps` | `hostfy list` |
| GET | `/api/status` | `hostfy status` |
| GET | `/api/apps/:name/logs` | `hostfy logs` |
| GET | `/api/apps/:name/secrets` | `hostfy secrets` |
| POST | `/api/apps/:name/start` | `hostfy start` |
| POST | `/api/apps/:name/stop` | `hostfy stop` |
| POST | `/api/apps/:name/restart` | `hostfy restart` |
| GET | `/api/databases` | `hostfy db list` |
| DELETE | `/api/databases/:name` | `hostfy db remove` |
| POST | `/api/cleanup` | `hostfy cleanup` |
| POST | `/api/upgrade` | `hostfy upgrade` |

---

## Version History

| Version | Date | Changes |
|---------|------|---------|
| 0.1.0 | 2024 | Initial release |
