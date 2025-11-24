package catalog

import (
	"regexp"
	"strings"

	"github.com/eduardocarezia/hostfy-cli/internal/storage"
)

type TemplateContext struct {
	AppName          string
	AppDomain        string
	AppDatabase      string
	Secrets          *storage.Secrets
	ServiceHosts     map[string]string
	PreservedSecrets map[string]string // Secrets de instalações anteriores
	generatedCache   map[string]string // Cache de secrets geradas nesta sessão
}

func NewTemplateContext(appName, domain string, secrets *storage.Secrets) *TemplateContext {
	return &TemplateContext{
		AppName:          appName,
		AppDomain:        domain,
		AppDatabase:      strings.ReplaceAll(appName, "-", "_") + "_db",
		Secrets:          secrets,
		PreservedSecrets: make(map[string]string),
		generatedCache:   make(map[string]string),
		ServiceHosts: map[string]string{
			"postgres": "hostfy_postgres",
			"redis":    "hostfy_redis",
		},
	}
}

// SetPreservedSecrets define secrets de instalações anteriores para reutilização
func (tc *TemplateContext) SetPreservedSecrets(secrets map[string]string) {
	tc.PreservedSecrets = secrets
}

func (tc *TemplateContext) ResolveEnv(env map[string]string) map[string]string {
	resolved := make(map[string]string)

	// Primeira passada: resolver variáveis básicas (que não dependem de outras do env)
	for key, value := range env {
		if preserved, ok := tc.PreservedSecrets[key]; ok {
			resolved[key] = preserved
		} else {
			resolved[key] = tc.resolveValueForKey(key, value)
		}
	}

	// Segunda passada: resolver referências a variáveis do próprio env
	for key, value := range resolved {
		resolved[key] = tc.resolveEnvReferences(value, resolved)
	}

	return resolved
}

// resolveEnvReferences resolve referências a variáveis do próprio env map
func (tc *TemplateContext) resolveEnvReferences(value string, env map[string]string) string {
	re := regexp.MustCompile(`\{\{([^}]+)\}\}`)
	return re.ReplaceAllStringFunc(value, func(match string) string {
		key := strings.Trim(match, "{}")
		if val, ok := env[key]; ok {
			return val
		}
		return match // Mantém o placeholder se não encontrar
	})
}

// resolveValueForKey resolve o valor e armazena em cache para keys que geram secrets
func (tc *TemplateContext) resolveValueForKey(key, value string) string {
	resolved := tc.resolveValue(value)
	// Se o valor original continha template de secret, armazena no cache
	if strings.Contains(value, "GENERATE_SECRET") || strings.Contains(value, "SYSTEM_GENERATE") {
		tc.generatedCache[key] = resolved
	}
	return resolved
}

func (tc *TemplateContext) ResolveVolumes(volumes []string) []string {
	resolved := make([]string, len(volumes))
	for i, vol := range volumes {
		resolved[i] = tc.resolveValue(vol)
	}
	return resolved
}

func (tc *TemplateContext) resolveValue(value string) string {
	re := regexp.MustCompile(`\{\{([^}]+)\}\}`)
	return re.ReplaceAllStringFunc(value, func(match string) string {
		key := strings.Trim(match, "{}")
		return tc.resolveTemplate(key)
	})
}

func (tc *TemplateContext) resolveTemplate(key string) string {
	switch key {
	case "APP_NAME":
		return tc.AppName
	case "APP_DOMAIN":
		return tc.AppDomain
	case "APP_DATABASE":
		return tc.AppDatabase
	case "SERVICE_postgres_HOST":
		return tc.ServiceHosts["postgres"]
	case "SERVICE_postgres_USER":
		return "hostfy"
	case "SERVICE_postgres_PASSWORD":
		if tc.Secrets != nil {
			return tc.Secrets.PostgresPassword
		}
		return ""
	case "SERVICE_redis_HOST":
		return tc.ServiceHosts["redis"]
	case "SYSTEM_GENERATE":
		return storage.GeneratePassword(24)
	}

	if strings.HasPrefix(key, "GENERATE_SECRET_") {
		lengthStr := strings.TrimPrefix(key, "GENERATE_SECRET_")
		length := 16
		if lengthStr == "32" {
			length = 32
		} else if lengthStr == "64" {
			length = 64
		}
		return storage.GenerateSecret(length)
	}

	return "{{" + key + "}}"
}
