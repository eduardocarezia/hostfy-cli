# hostfy CLI

Self-hosted app deployment made simple. Deploy apps com um comando, configure domínios automaticamente e deixe o hostfy cuidar das dependências.

## Instalação

```bash
curl -fsSL https://raw.githubusercontent.com/eduardocarezia/hostfy-cli/main/scripts/install.sh | sudo bash
```

## Quick Start

```bash
# 1. Inicialize o hostfy
hostfy init

# 2. Veja apps disponíveis
hostfy catalog

# 3. Instale seu primeiro app
hostfy install n8n --domain n8n.seudominio.com

# 4. Configure o DNS na Cloudflare
# Aponte n8n.seudominio.com para o IP do servidor
```

## Comandos

### Setup
```bash
hostfy init [--catalog-url URL]     # Inicializa o hostfy
```

### Catálogo
```bash
hostfy catalog                      # Lista apps disponíveis
hostfy catalog --refresh            # Força atualização do catálogo
hostfy pull                         # Atualiza catálogo local
hostfy pull <app>                   # Atualiza imagem + merge configs de um app
```

### Gestão de Apps
```bash
hostfy install <app> --domain <dom> [--name <stack>] [--env KEY=VAL]
hostfy remove <app> [--purge]       # Remove app (--purge remove dados)
hostfy update <app> [--env KEY=VAL] [--domain <dom>]
hostfy config <app> --domain <dom>  # Alias para update --domain
```

### Status e Informações
```bash
hostfy list                         # Lista apps instalados
hostfy status                       # JSON completo do sistema
hostfy logs <app> [-f] [--tail N]   # Logs do container
hostfy secrets <app>                # Mostra credenciais
```

### Controle
```bash
hostfy start <app|all>              # Inicia container(s)
hostfy stop <app>                   # Para container
hostfy restart <app|all>            # Reinicia container(s)
```

## Arquitetura

```
┌─────────────────────────────────────────────────────┐
│  Servidor Linux                                     │
│                                                     │
│  ┌─────────────────────────────────────────────┐   │
│  │  hostfy CLI                                 │   │
│  │  • Instala Docker automaticamente           │   │
│  │  • Configura Traefik (SSL + routing)        │   │
│  │  • Gerencia apps do catálogo                │   │
│  └─────────────────────────────────────────────┘   │
│                                                     │
│  ┌──────────┐ ┌──────────┐ ┌──────────┐           │
│  │ Traefik  │ │ Postgres │ │  Redis   │           │
│  │  :80/443 │ │  :5432   │ │  :6379   │           │
│  └──────────┘ └──────────┘ └──────────┘           │
│                                                     │
│  ┌──────────┐ ┌──────────┐ ┌──────────┐           │
│  │   n8n    │ │  minio   │ │  outros  │           │
│  └──────────┘ └──────────┘ └──────────┘           │
└─────────────────────────────────────────────────────┘
```

## Storage

```
/etc/hostfy/
├── config.json          # Configurações globais
├── secrets.json         # Senhas do sistema (postgres, etc)
└── apps/
    ├── n8n.json         # Config do app instalado
    └── ...
```

## Catálogo

O catálogo é um arquivo JSON com definições de apps. Por padrão:
`https://raw.githubusercontent.com/eduardocarezia/hostfy-cli/main/catalog.json`

### Apps Disponíveis

- **n8n** - Workflow Automation
- **Uptime Kuma** - Monitoramento de uptime
- **MinIO** - S3-compatible storage
- **Portainer** - Docker management UI
- **NocoDB** - Airtable open source
- **Ghost** - Blog/CMS
- **Gitea** - Git server
- **Plausible** - Privacy-friendly analytics
- **Metabase** - Business Intelligence
- **Directus** - Headless CMS

## Configuração DNS (Cloudflare)

1. Vá em **DNS** no painel da Cloudflare
2. Adicione um registro **A** para cada app:
   - Nome: `n8n` (ou o subdomínio desejado)
   - Conteúdo: IP do seu servidor
   - Proxy: Pode deixar desativado (orange cloud off)
3. O Traefik cuida do SSL automaticamente via Let's Encrypt

## Build

```bash
# Instalar dependências
make deps

# Build para plataforma atual
make build

# Build para todas as plataformas
make build-all

# Instalar localmente
make install
```

## Requisitos

- Linux (Ubuntu 20.04+, Debian 11+, etc)
- Acesso root
- Portas 80 e 443 disponíveis
- Domínio configurado na Cloudflare

## Licença

MIT
