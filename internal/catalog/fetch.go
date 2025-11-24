package catalog

import (
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"os"
	"path/filepath"
	"time"

	"github.com/eduardocarezia/hostfy-cli/internal/storage"
)

const (
	CacheFile = "catalog_cache.json"
	CacheTTL  = 1 * time.Hour
)

func getCachePath() string {
	return filepath.Join(storage.HostfyDir, CacheFile)
}

func Fetch(forceRefresh bool) (*Catalog, error) {
	cfg, err := storage.LoadConfig()
	if err != nil {
		return nil, fmt.Errorf("erro ao carregar config: %w", err)
	}

	if !forceRefresh {
		cached, err := loadFromCache()
		if err == nil && cached != nil {
			return cached, nil
		}
	}

	catalog, err := fetchFromURL(cfg.CatalogURL)
	if err != nil {
		return nil, err
	}

	saveToCache(catalog)

	cfg.CatalogUpdatedAt = time.Now().UTC().Format(time.RFC3339)
	storage.SaveConfig(cfg)

	return catalog, nil
}

func fetchFromURL(url string) (*Catalog, error) {
	resp, err := http.Get(url)
	if err != nil {
		return nil, fmt.Errorf("erro ao buscar catálogo: %w", err)
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		return nil, fmt.Errorf("erro ao buscar catálogo: status %d", resp.StatusCode)
	}

	body, err := io.ReadAll(resp.Body)
	if err != nil {
		return nil, fmt.Errorf("erro ao ler resposta: %w", err)
	}

	var catalog Catalog
	if err := json.Unmarshal(body, &catalog); err != nil {
		return nil, fmt.Errorf("erro ao parsear catálogo: %w", err)
	}

	return &catalog, nil
}

func loadFromCache() (*Catalog, error) {
	info, err := os.Stat(getCachePath())
	if err != nil {
		return nil, err
	}

	if time.Since(info.ModTime()) > CacheTTL {
		return nil, fmt.Errorf("cache expirado")
	}

	data, err := os.ReadFile(getCachePath())
	if err != nil {
		return nil, err
	}

	var catalog Catalog
	if err := json.Unmarshal(data, &catalog); err != nil {
		return nil, err
	}

	return &catalog, nil
}

func saveToCache(catalog *Catalog) error {
	data, err := json.MarshalIndent(catalog, "", "  ")
	if err != nil {
		return err
	}
	return os.WriteFile(getCachePath(), data, 0644)
}

func GetApp(name string) (*App, error) {
	catalog, err := Fetch(false)
	if err != nil {
		return nil, err
	}

	app, exists := catalog.Apps[name]
	if !exists {
		return nil, fmt.Errorf("app '%s' não encontrado no catálogo", name)
	}

	return &app, nil
}

func GetService(name string) (*Service, error) {
	catalog, err := Fetch(false)
	if err != nil {
		return nil, err
	}

	service, exists := catalog.Services[name]
	if !exists {
		return nil, fmt.Errorf("serviço '%s' não encontrado no catálogo", name)
	}

	return &service, nil
}

func ListApps() (map[string]App, error) {
	catalog, err := Fetch(false)
	if err != nil {
		return nil, err
	}
	return catalog.Apps, nil
}
