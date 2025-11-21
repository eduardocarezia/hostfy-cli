# Hostfy API Documentation

## Overview

The Hostfy API provides a RESTful interface to manage containers through HTTP requests. It runs on port `3000` by default.

## Authentication

All endpoints (except `/health`) require an API key to be passed in the `X-API-Key` header.

```bash
# Your API key is stored in:
# Linux/Server: /root/config/api.key
# macOS: ~/hostfy/config/api.key
```

### Example Request with Authentication
```bash
curl -X GET http://your-server:3000/containers \
  -H "X-API-Key: YOUR_API_KEY"
```

---

## Endpoints

### Health Check

Check if the API server is running.

| Method | Endpoint | Auth Required |
|--------|----------|---------------|
| GET | `/health` | No |

**Response:**
```json
{
  "status": "ok",
  "version": "1.0.0"
}
```

**Example:**
```bash
curl http://your-server:3000/health
```

---

### List Containers

Get all available and installed containers.

| Method | Endpoint | Auth Required |
|--------|----------|---------------|
| GET | `/containers` | Yes |

**Response:**
```json
{
  "available": [
    {
      "id": "postgres",
      "name": "PostgreSQL",
      "description": "Relational database",
      "image": "postgres:15",
      "category": "database"
    }
  ],
  "installed": [
    {
      "name": "my-postgres",
      "type": "catalog",
      "image": "postgres:15",
      "status": "running"
    }
  ]
}
```

**Example:**
```bash
curl -X GET http://your-server:3000/containers \
  -H "X-API-Key: YOUR_API_KEY"
```

---

### Install Container

Install a new container from catalog or custom image.

| Method | Endpoint | Auth Required |
|--------|----------|---------------|
| POST | `/containers/install` | Yes |

**Request Body:**
```json
{
  "name": "my-app",
  "options": {
    "image": "nginx:latest",
    "domain": "app.example.com",
    "port": "80"
  }
}
```

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `name` | string | Yes | Container name (alphanumeric, hyphens, underscores) |
| `options.image` | string | No* | Docker image (required for custom containers) |
| `options.domain` | string | No | Domain for Traefik routing |
| `options.port` | string | No | Container port (default: 80) |

*If installing from catalog, image is not required.

**Response:**
```json
{
  "success": true,
  "message": "Container installation started",
  "output": "..."
}
```

**Examples:**

Install from catalog:
```bash
curl -X POST http://your-server:3000/containers/install \
  -H "X-API-Key: YOUR_API_KEY" \
  -H "Content-Type: application/json" \
  -d '{"name": "postgres"}'
```

Install custom container with domain:
```bash
curl -X POST http://your-server:3000/containers/install \
  -H "X-API-Key: YOUR_API_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "name": "my-nginx",
    "options": {
      "image": "nginx:latest",
      "domain": "web.example.com",
      "port": "80"
    }
  }'
```

---

### Delete Container

Remove a container and optionally its volumes.

| Method | Endpoint | Auth Required |
|--------|----------|---------------|
| POST | `/containers/delete` | Yes |

**Request Body:**
```json
{
  "name": "my-app",
  "volumes": true
}
```

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `name` | string | Yes | Container name to delete |
| `volumes` | boolean | No | Also remove volumes (default: false) |

**Response:**
```json
{
  "success": true,
  "message": "Container deleted",
  "output": "..."
}
```

**Example:**
```bash
curl -X POST http://your-server:3000/containers/delete \
  -H "X-API-Key: YOUR_API_KEY" \
  -H "Content-Type: application/json" \
  -d '{"name": "my-nginx", "volumes": true}'
```

---

### Start Container

Start/restart a container.

| Method | Endpoint | Auth Required |
|--------|----------|---------------|
| POST | `/containers/:name/start` | Yes |

**URL Parameters:**
| Parameter | Description |
|-----------|-------------|
| `name` | Container name |

**Response:**
```json
{
  "success": true,
  "output": "..."
}
```

**Example:**
```bash
curl -X POST http://your-server:3000/containers/my-postgres/start \
  -H "X-API-Key: YOUR_API_KEY"
```

---

### Stop Container

Stop (pause) a running container.

| Method | Endpoint | Auth Required |
|--------|----------|---------------|
| POST | `/containers/:name/stop` | Yes |

**URL Parameters:**
| Parameter | Description |
|-----------|-------------|
| `name` | Container name |

**Response:**
```json
{
  "success": true,
  "output": "..."
}
```

**Example:**
```bash
curl -X POST http://your-server:3000/containers/my-postgres/stop \
  -H "X-API-Key: YOUR_API_KEY"
```

---

### Get Container Logs

Retrieve logs from a container.

| Method | Endpoint | Auth Required |
|--------|----------|---------------|
| GET | `/containers/:name/logs` | Yes |

**URL Parameters:**
| Parameter | Description |
|-----------|-------------|
| `name` | Container name |

**Query Parameters:**
| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `tail` | number | 50 | Number of log lines to retrieve |

**Response:**
```json
{
  "logs": "2024-01-15 10:30:00 Starting application...\n..."
}
```

**Example:**
```bash
# Get last 50 lines (default)
curl -X GET "http://your-server:3000/containers/my-postgres/logs" \
  -H "X-API-Key: YOUR_API_KEY"

# Get last 100 lines
curl -X GET "http://your-server:3000/containers/my-postgres/logs?tail=100" \
  -H "X-API-Key: YOUR_API_KEY"
```

---

## Error Responses

### 400 Bad Request
Missing required parameters.
```json
{
  "error": "Container name is required"
}
```

### 401 Unauthorized
Invalid or missing API key.
```json
{
  "error": "Unauthorized: Invalid API Key"
}
```

### 500 Internal Server Error
Operation failed.
```json
{
  "error": "Installation failed",
  "details": {
    "error": "...",
    "stderr": "...",
    "stdout": "..."
  }
}
```

---

## Quick Reference

| Action | Method | Endpoint | Body |
|--------|--------|----------|------|
| Health check | GET | `/health` | - |
| List containers | GET | `/containers` | - |
| Install container | POST | `/containers/install` | `{name, options}` |
| Delete container | POST | `/containers/delete` | `{name, volumes}` |
| Start container | POST | `/containers/:name/start` | - |
| Stop container | POST | `/containers/:name/stop` | - |
| Get logs | GET | `/containers/:name/logs?tail=N` | - |

---

## Starting the API Server

```bash
# Start API server
hostfy api start

# Check status
hostfy api status

# Stop API server
hostfy api stop

# View API logs
cat ~/hostfy/logs/api.log
```

## Environment Variables

| Variable | Description | Default |
|----------|-------------|---------|
| `PORT` | API server port | 3000 |
| `API_KEY` | Authentication key | Auto-generated |
| `HOSTFY_API_KEY` | Override API key | - |
