package storage

import (
	"encoding/json"
	"os"
	"path/filepath"
)

const (
	HostfyDir    = "/etc/hostfy"
	ConfigFile   = "config.json"
	SecretsFile  = "secrets.json"
	AppsDir      = "apps"
)

type Config struct {
	Version       string        `json:"version"`
	CatalogURL    string        `json:"catalog_url"`
	CatalogUpdatedAt string     `json:"catalog_updated_at,omitempty"`
	Network       string        `json:"network"`
	Traefik       TraefikConfig `json:"traefik"`
}

type TraefikConfig struct {
	Dashboard bool `json:"dashboard"`
}

func DefaultConfig() *Config {
	return &Config{
		Version:    "1.0",
		CatalogURL: "https://raw.githubusercontent.com/hostfy/catalog/main/catalog.json",
		Network:    "hostfy_network",
		Traefik: TraefikConfig{
			Dashboard: false,
		},
	}
}

func GetConfigPath() string {
	return filepath.Join(HostfyDir, ConfigFile)
}

func GetSecretsPath() string {
	return filepath.Join(HostfyDir, SecretsFile)
}

func GetAppsDir() string {
	return filepath.Join(HostfyDir, AppsDir)
}

func GetAppPath(name string) string {
	return filepath.Join(GetAppsDir(), name+".json")
}

func EnsureDirectories() error {
	dirs := []string{
		HostfyDir,
		GetAppsDir(),
	}
	for _, dir := range dirs {
		if err := os.MkdirAll(dir, 0755); err != nil {
			return err
		}
	}
	return nil
}

func LoadConfig() (*Config, error) {
	data, err := os.ReadFile(GetConfigPath())
	if err != nil {
		if os.IsNotExist(err) {
			return DefaultConfig(), nil
		}
		return nil, err
	}

	var cfg Config
	if err := json.Unmarshal(data, &cfg); err != nil {
		return nil, err
	}
	return &cfg, nil
}

func SaveConfig(cfg *Config) error {
	if err := EnsureDirectories(); err != nil {
		return err
	}

	data, err := json.MarshalIndent(cfg, "", "  ")
	if err != nil {
		return err
	}
	return os.WriteFile(GetConfigPath(), data, 0644)
}
