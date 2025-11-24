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
