package catalog

import (
	"regexp"
	"strings"

	"github.com/hostfy/cli/internal/storage"
)

type TemplateContext struct {
	AppName      string
	AppDomain    string
	AppDatabase  string
	Secrets      *storage.Secrets
	ServiceHosts map[string]string
}

func NewTemplateContext(appName, domain string, secrets *storage.Secrets) *TemplateContext {
	return &TemplateContext{
		AppName:     appName,
		AppDomain:   domain,
		AppDatabase: strings.ReplaceAll(appName, "-", "_") + "_db",
		Secrets:     secrets,
		ServiceHosts: map[string]string{
			"postgres": "hostfy_postgres",
			"redis":    "hostfy_redis",
		},
	}
}

func (tc *TemplateContext) ResolveEnv(env map[string]string) map[string]string {
	resolved := make(map[string]string)
	for key, value := range env {
		resolved[key] = tc.resolveValue(value)
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
