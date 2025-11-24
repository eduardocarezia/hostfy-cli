package cli

import (
	"encoding/json"
	"fmt"
	"os/exec"
	"runtime"
	"strings"

	"github.com/eduardocarezia/hostfy-cli/internal/docker"
	"github.com/eduardocarezia/hostfy-cli/internal/services"
	"github.com/eduardocarezia/hostfy-cli/internal/storage"
	"github.com/eduardocarezia/hostfy-cli/internal/traefik"
	"github.com/spf13/cobra"
)

var statusCmd = &cobra.Command{
	Use:   "status",
	Short: "Mostra status completo do sistema",
	Long:  `Retorna um JSON com o estado completo do hostfy.`,
	RunE:  runStatus,
}

type SystemStatus struct {
	HostfyVersion string            `json:"hostfy_version"`
	System        SystemInfo        `json:"system"`
	Services      map[string]ServiceStatus `json:"services"`
	Apps          []AppStatus       `json:"apps"`
}

type SystemInfo struct {
	Docker string `json:"docker"`
	OS     string `json:"os"`
	Arch   string `json:"arch"`
}

type ServiceStatus struct {
	Status string   `json:"status"`
	Image  string   `json:"image,omitempty"`
	Databases []string `json:"databases,omitempty"`
}

type AppStatus struct {
	Name   string `json:"name"`
	Domain string `json:"domain"`
	Status string `json:"status"`
	Image  string `json:"image"`
}

func runStatus(cmd *cobra.Command, args []string) error {
	dockerClient, err := docker.NewClient()
	if err != nil {
		return err
	}
	defer dockerClient.Close()

	// Docker version
	dockerVersion := "unknown"
	out, err := exec.Command("docker", "--version").Output()
	if err == nil {
		parts := strings.Fields(string(out))
		if len(parts) >= 3 {
			dockerVersion = strings.TrimSuffix(parts[2], ",")
		}
	}

	status := SystemStatus{
		HostfyVersion: "1.0.0",
		System: SystemInfo{
			Docker: dockerVersion,
			OS:     runtime.GOOS,
			Arch:   runtime.GOARCH,
		},
		Services: make(map[string]ServiceStatus),
		Apps:     []AppStatus{},
	}

	// Traefik status
	traefikRunning, _ := dockerClient.ContainerRunning(traefik.ContainerName)
	traefikStatus := "stopped"
	if traefikRunning {
		traefikStatus = "running"
	}
	status.Services["traefik"] = ServiceStatus{
		Status: traefikStatus,
		Image:  traefik.Image,
	}

	// Postgres status
	pgRunning, _ := dockerClient.ContainerRunning(services.PostgresContainerName)
	pgStatus := "stopped"
	if pgRunning {
		pgStatus = "running"
	}
	secrets, _ := storage.LoadSecrets()
	pgManager := services.NewPostgresManager(dockerClient, secrets)
	dbs, _ := pgManager.ListDatabases()
	status.Services["postgres"] = ServiceStatus{
		Status:    pgStatus,
		Image:     services.PostgresImage,
		Databases: dbs,
	}

	// Redis status
	redisRunning, _ := dockerClient.ContainerRunning(services.RedisContainerName)
	redisStatus := "stopped"
	if redisRunning {
		redisStatus = "running"
	}
	status.Services["redis"] = ServiceStatus{
		Status: redisStatus,
		Image:  services.RedisImage,
	}

	// Apps status
	apps, _ := storage.ListApps()
	for _, app := range apps {
		running, _ := dockerClient.ContainerRunning(app.Name)
		appStatus := "stopped"
		if running {
			appStatus = "running"
		}
		status.Apps = append(status.Apps, AppStatus{
			Name:   app.Name,
			Domain: app.Domain,
			Status: appStatus,
			Image:  app.Image,
		})
	}

	// Output JSON
	jsonData, err := json.MarshalIndent(status, "", "  ")
	if err != nil {
		return err
	}

	fmt.Println(string(jsonData))
	return nil
}
