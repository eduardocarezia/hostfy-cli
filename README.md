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

---

## Comandos

### Setup & Inicialização

| Comando | Descrição |
|---------|-----------|
| `hostfy init` | Inicializa o hostfy no servidor |
| `hostfy version` | Mostra a versão do CLI |
| `hostfy upgrade` | Atualiza o hostfy CLI para versão mais recente |

```bash
# Inicializar com URL de catálogo customizada
hostfy init --catalog-url https://meu.catalogo.com/catalog.json

# Atualizar CLI forçadamente
hostfy upgrade --force
```

### Catálogo

| Comando | Descrição |
|---------|-----------|
| `hostfy catalog` | Lista apps disponíveis no catálogo |
| `hostfy pull` | Atualiza apenas o catálogo local |
| `hostfy pull <app>` | Atualiza imagem + merge de configs |

```bash
# Forçar atualização do catálogo
hostfy catalog --refresh

# Atualizar catálogo e imagem de um app
hostfy pull n8n
```

### Instalação de Apps

| Comando | Descrição |
|---------|-----------|
| `hostfy install <app>` | Instala um app do catálogo |

**Flags:**
| Flag | Descrição | Obrigatório |
|------|-----------|-------------|
| `--domain <dom>` | Domínio para o app | Sim |
| `--name <nome>` | Nome customizado para a stack | Não |
| `--env KEY=VAL` | Variáveis de ambiente extras | Não |

```bash
# Instalação básica
hostfy install n8n --domain n8n.meudominio.com

# Com nome customizado (permite múltiplas instâncias)
hostfy install n8n --domain n8n-dev.meudominio.com --name n8n-dev

# Com variáveis de ambiente
hostfy install n8n --domain n8n.meudominio.com --env N8N_WEBHOOK_DOMAIN=webhook.meudominio.com
```

### Upgrade de Stacks

| Comando | Descrição |
|---------|-----------|
| `hostfy upgrade` | Atualiza o CLI (sem argumentos) |
| `hostfy upgrade <stack>` | Atualiza uma stack instalada |

**Flags:**
| Flag | Descrição |
|------|-----------|
| `--force` | Força atualização mesmo se já estiver na última versão |

```bash
# Atualizar o CLI
hostfy upgrade

# Atualizar uma stack para última versão do catálogo
hostfy upgrade n8n

# Forçar re-download das imagens
hostfy upgrade n8n --force
```

**O que o upgrade de stack faz:**
1. Atualiza o catálogo forçadamente
2. Compara versões das imagens (instalada vs catálogo)
3. Baixa novas imagens do Docker Hub
4. Recria containers com as novas imagens
5. Preserva todas as customizações (envs, volumes, configs)
6. Adiciona novas envs do catálogo que não existiam

### Remoção de Apps

| Comando | Descrição |
|---------|-----------|
| `hostfy remove <app>` | Remove um app completamente |
| `hostfy uninstall <app>` | Alias para `remove` |

**Flags:**
| Flag | Descrição |
|------|-----------|
| `--keep-data` | Mantém volumes e secrets para reinstalação futura |

```bash
# Remover completamente (container + volumes + database + secrets)
hostfy remove n8n

# Remover mas manter dados para reinstalação
hostfy remove n8n --keep-data
```

### Atualização de Configurações

| Comando | Descrição |
|---------|-----------|
| `hostfy update <app>` | Atualiza configurações de um app |
| `hostfy config <app>` | Alias para `update --domain` |

**Flags:**
| Flag | Descrição |
|------|-----------|
| `--env KEY=VAL` | Variáveis de ambiente para alterar |
| `--domain <dom>` | Novo domínio |

```bash
# Alterar domínio
hostfy update n8n --domain novo.dominio.com

# Alterar variável de ambiente
hostfy update n8n --env N8N_WEBHOOK_DOMAIN=webhook.novo.com

# Usando alias config
hostfy config n8n --domain novo.dominio.com
```

### Status e Informações

| Comando | Descrição |
|---------|-----------|
| `hostfy list` | Lista apps instalados com status |
| `hostfy status` | Retorna JSON completo do sistema |
| `hostfy logs <app>` | Mostra logs de um app |
| `hostfy secrets <app>` | Mostra credenciais e envs de um app |

**Flags do logs:**
| Flag | Descrição |
|------|-----------|
| `-f, --follow` | Segue os logs em tempo real |
| `--tail N` | Número de linhas a mostrar (padrão: 100) |
| `-c, --container` | Container específico (para Stacks) |

```bash
# Listar apps instalados
hostfy list

# Status completo em JSON
hostfy status

# Logs com follow
hostfy logs n8n -f

# Logs de um container específico em uma Stack
hostfy logs n8n -c worker
hostfy logs n8n -c webhook

# Ver credenciais
hostfy secrets n8n
```

### Controle de Execução

| Comando | Descrição |
|---------|-----------|
| `hostfy start <app\|all>` | Inicia container(s) |
| `hostfy stop <app>` | Para container(s) |
| `hostfy restart <app\|all>` | Reinicia container(s) |

```bash
# Iniciar todos os serviços
hostfy start all

# Iniciar app específico
hostfy start n8n

# Parar app
hostfy stop n8n

# Reiniciar app
hostfy restart n8n

# Reiniciar todos
hostfy restart all
```

### Gerenciamento de Database

| Comando | Descrição |
|---------|-----------|
| `hostfy db list` | Lista todos os databases |
| `hostfy db remove <db>` | Remove um database |

**Flags:**
| Flag | Descrição |
|------|-----------|
| `--force` | Remove sem confirmação |

```bash
# Listar databases (mostra quais estão em uso e órfãos)
hostfy db list

# Remover database órfão
hostfy db remove n8n_db

# Remover sem confirmação
hostfy db remove n8n_db --force
```

### Limpeza

| Comando | Descrição |
|---------|-----------|
| `hostfy cleanup` | Lista recursos órfãos |
| `hostfy cleanup --force` | Remove recursos órfãos |

```bash
# Verificar o que seria removido
hostfy cleanup

# Remover containers e databases órfãos
hostfy cleanup --force
```

---

## Referência Rápida de Flags

| Flag Global | Descrição |
|-------------|-----------|
| `--force` | Força operação sem confirmação |
| `--keep-data` | Mantém dados ao remover |
| `-f, --follow` | Segue output em tempo real |
| `--tail N` | Limita número de linhas |
| `-c, --container` | Especifica container em Stacks |

---

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

### Estrutura de Stacks

Apps complexos são instalados como **Stacks** com múltiplos containers:

```
n8n Stack:
├── n8n-editor   (porta 5678, domínio principal)
├── n8n-webhook  (porta 5678, subdomínio webhook)
└── n8n-worker   (processamento em background)
```

---

## Storage

```
/etc/hostfy/
├── config.json          # Configurações globais
├── secrets.json         # Senhas do sistema (postgres, etc)
├── catalog_cache.json   # Cache do catálogo
└── apps/
    ├── n8n.json         # Config do app instalado
    └── ...
```

---

## Catálogo

O catálogo é um arquivo JSON com definições de apps. Por padrão:
`https://raw.githubusercontent.com/eduardocarezia/hostfy-cli/main/catalog.json`

### Apps Disponíveis

| App | Descrição |
|-----|-----------|
| **n8n** | Workflow Automation (Stack: Editor + Webhook + Worker) |
| **Uptime Kuma** | Monitoramento de uptime |
| **MinIO** | S3-compatible storage |
| **Portainer** | Docker management UI |
| **NocoDB** | Airtable open source |
| **Ghost** | Blog/CMS |
| **Gitea** | Git server |
| **Plausible** | Privacy-friendly analytics |
| **Metabase** | Business Intelligence |
| **Directus** | Headless CMS |

---

## Configuração DNS (Cloudflare)

1. Vá em **DNS** no painel da Cloudflare
2. Adicione um registro **A** para cada app:
   - Nome: `n8n` (ou o subdomínio desejado)
   - Conteúdo: IP do seu servidor
   - Proxy: Pode deixar desativado (orange cloud off)
3. O Traefik cuida do SSL automaticamente via Let's Encrypt

---

## Exemplos de Uso

### Fluxo Completo de Instalação

```bash
# 1. Inicializar
hostfy init

# 2. Instalar n8n com domínio customizado para webhooks
hostfy install n8n --domain n8n.empresa.com \
  --env N8N_WEBHOOK_DOMAIN=webhook.empresa.com

# 3. Verificar status
hostfy list
hostfy status

# 4. Ver credenciais
hostfy secrets n8n
```

### Atualização de Stack

```bash
# Atualizar para última versão
hostfy upgrade n8n

# Verificar se atualizou
hostfy logs n8n --tail 20
```

### Migração de Domínio

```bash
# Alterar domínio
hostfy update n8n --domain novo.dominio.com

# Atualizar DNS na Cloudflare
# Reiniciar para aplicar
hostfy restart n8n
```

### Backup e Reinstalação

```bash
# Remover mantendo dados
hostfy remove n8n --keep-data

# Reinstalar (secrets serão reutilizados)
hostfy install n8n --domain n8n.empresa.com
```

---

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

---

## Requisitos

- Linux (Ubuntu 20.04+, Debian 11+, etc)
- Acesso root
- Portas 80 e 443 disponíveis
- Domínio configurado na Cloudflare

---

## Licença

MIT
