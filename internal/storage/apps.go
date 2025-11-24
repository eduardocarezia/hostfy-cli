package storage

import (
	"encoding/json"
	"os"
	"path/filepath"
	"time"
)

type AppConfig struct {
	Name          string            `json:"name"`
	CatalogApp    string            `json:"catalog_app"`
	Domain        string            `json:"domain"`
	InstalledAt   string            `json:"installed_at"`
	UpdatedAt     string            `json:"updated_at"`
	Image         string            `json:"image"`
	ImagePulledAt string            `json:"image_pulled_at"`
	ContainerID   string            `json:"container_id,omitempty"`
	Database      string            `json:"database,omitempty"`
	Env           map[string]string `json:"env"`
	Volumes       []string          `json:"volumes,omitempty"`
	Command       string            `json:"command,omitempty"`
	Port          int               `json:"port,omitempty"`

	// Stack mode - múltiplos containers
	IsStack    bool                     `json:"is_stack,omitempty"`
	Containers []ContainerConfig        `json:"containers,omitempty"`
	SharedEnv  map[string]string        `json:"shared_env,omitempty"`
}

// ContainerConfig armazena configuração de um container individual numa Stack
type ContainerConfig struct {
	Name        string            `json:"name"`
	ContainerID string            `json:"container_id"`
	Image       string            `json:"image"`
	Domain      string            `json:"domain,omitempty"`
	Port        int               `json:"port,omitempty"`
	Command     string            `json:"command,omitempty"`
	Env         map[string]string `json:"env,omitempty"`
	Volumes     []string          `json:"volumes,omitempty"`
	IsMain      bool              `json:"is_main,omitempty"`
}

func NewAppConfig(name, catalogApp, domain, image string) *AppConfig {
	now := time.Now().UTC().Format(time.RFC3339)
	return &AppConfig{
		Name:          name,
		CatalogApp:    catalogApp,
		Domain:        domain,
		InstalledAt:   now,
		UpdatedAt:     now,
		Image:         image,
		ImagePulledAt: now,
		Env:           make(map[string]string),
	}
}

func LoadApp(name string) (*AppConfig, error) {
	data, err := os.ReadFile(GetAppPath(name))
	if err != nil {
		return nil, err
	}

	var app AppConfig
	if err := json.Unmarshal(data, &app); err != nil {
		return nil, err
	}
	return &app, nil
}

func SaveApp(app *AppConfig) error {
	if err := EnsureDirectories(); err != nil {
		return err
	}

	app.UpdatedAt = time.Now().UTC().Format(time.RFC3339)

	data, err := json.MarshalIndent(app, "", "  ")
	if err != nil {
		return err
	}
	return os.WriteFile(GetAppPath(app.Name), data, 0644)
}

func DeleteApp(name string) error {
	return os.Remove(GetAppPath(name))
}

func ListApps() ([]AppConfig, error) {
	appsDir := GetAppsDir()
	entries, err := os.ReadDir(appsDir)
	if err != nil {
		if os.IsNotExist(err) {
			return []AppConfig{}, nil
		}
		return nil, err
	}

	var apps []AppConfig
	for _, entry := range entries {
		if entry.IsDir() || filepath.Ext(entry.Name()) != ".json" {
			continue
		}

		name := entry.Name()[:len(entry.Name())-5] // remove .json
		app, err := LoadApp(name)
		if err != nil {
			continue
		}
		apps = append(apps, *app)
	}
	return apps, nil
}

func AppExists(name string) bool {
	_, err := os.Stat(GetAppPath(name))
	return err == nil
}

// AppSecretsBackup armazena secrets sensíveis para reutilização em reinstalações
type AppSecretsBackup struct {
	Name       string            `json:"name"`
	CatalogApp string            `json:"catalog_app"`
	Secrets    map[string]string `json:"secrets"` // Keys como N8N_ENCRYPTION_KEY, etc.
	BackupedAt string            `json:"backuped_at"`
}

// BackupAppSecrets salva as secrets sensíveis de um app antes de removê-lo
func BackupAppSecrets(app *AppConfig) error {
	if err := EnsureDirectories(); err != nil {
		return err
	}

	// Lista de keys sensíveis que devem ser preservadas
	sensitiveKeys := []string{
		"N8N_ENCRYPTION_KEY",
		"SECRET_KEY_BASE",
		"KEY",
		"SECRET",
		"AUTHENTICATION_API_KEY",
		"MINIO_ROOT_USER",
		"MINIO_ROOT_PASSWORD",
	}

	secrets := make(map[string]string)
	for _, key := range sensitiveKeys {
		if val, ok := app.Env[key]; ok {
			secrets[key] = val
		}
	}

	// Se não há secrets para backup, não cria arquivo
	if len(secrets) == 0 {
		return nil
	}

	backup := &AppSecretsBackup{
		Name:       app.Name,
		CatalogApp: app.CatalogApp,
		Secrets:    secrets,
		BackupedAt: time.Now().UTC().Format(time.RFC3339),
	}

	data, err := json.MarshalIndent(backup, "", "  ")
	if err != nil {
		return err
	}
	return os.WriteFile(GetAppSecretsBackupPath(app.Name), data, 0600) // 0600 para proteger secrets
}

// LoadAppSecretsBackup carrega secrets de backup de um app
func LoadAppSecretsBackup(name string) (*AppSecretsBackup, error) {
	data, err := os.ReadFile(GetAppSecretsBackupPath(name))
	if err != nil {
		return nil, err
	}

	var backup AppSecretsBackup
	if err := json.Unmarshal(data, &backup); err != nil {
		return nil, err
	}
	return &backup, nil
}

// DeleteAppSecretsBackup remove o backup de secrets de um app
func DeleteAppSecretsBackup(name string) error {
	path := GetAppSecretsBackupPath(name)
	if _, err := os.Stat(path); os.IsNotExist(err) {
		return nil // Arquivo não existe, nada para deletar
	}
	return os.Remove(path)
}

// AppSecretsBackupExists verifica se existe backup de secrets para um app
func AppSecretsBackupExists(name string) bool {
	_, err := os.Stat(GetAppSecretsBackupPath(name))
	return err == nil
}
