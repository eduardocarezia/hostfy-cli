package traefik

import (
	"fmt"

	"github.com/eduardocarezia/hostfy-cli/internal/docker"
)

const (
	ContainerName = "hostfy_traefik"
	Image         = "traefik:v3.2"
)

type Manager struct {
	docker *docker.Client
}

func NewManager(dockerClient *docker.Client) *Manager {
	return &Manager{docker: dockerClient}
}

func (m *Manager) IsRunning() (bool, error) {
	return m.docker.ContainerRunning(ContainerName)
}

func (m *Manager) Start() error {
	running, err := m.IsRunning()
	if err != nil {
		return err
	}
	if running {
		return nil
	}

	exists, err := m.docker.ContainerExists(ContainerName)
	if err != nil {
		return err
	}

	if exists {
		return m.docker.StartContainer(ContainerName)
	}

	if err := m.docker.PullImage(Image); err != nil {
		return err
	}

	cfg := &docker.ContainerConfig{
		Name:  ContainerName,
		Image: Image,
		Env: map[string]string{
			"DOCKER_API_VERSION": "1.44",
		},
		Volumes: []string{
			"/var/run/docker.sock:/var/run/docker.sock:ro",
			"hostfy_traefik_certs:/letsencrypt",
		},
		Ports: map[string]string{
			"80":   "80",
			"443":  "443",
			"8080": "8080",
		},
		Labels: map[string]string{
			"hostfy.managed": "true",
			"hostfy.service": "traefik",
		},
		Command: []string{
			"--api.insecure=true",
			"--providers.docker=true",
			"--providers.docker.exposedbydefault=false",
			"--providers.docker.network=hostfy_network",
			"--entrypoints.web.address=:80",
			"--entrypoints.websecure.address=:443",
			"--entrypoints.web.http.redirections.entryPoint.to=websecure",
			"--entrypoints.web.http.redirections.entryPoint.scheme=https",
			"--certificatesresolvers.hostfyresolver.acme.httpchallenge=true",
			"--certificatesresolvers.hostfyresolver.acme.httpchallenge.entrypoint=web",
			"--certificatesresolvers.hostfyresolver.acme.storage=/letsencrypt/acme.json",
		},
		Restart: "always",
	}

	id, err := m.docker.CreateContainer(cfg)
	if err != nil {
		return fmt.Errorf("erro ao criar container Traefik: %w", err)
	}

	return m.docker.StartContainer(id)
}

func (m *Manager) Stop() error {
	return m.docker.StopContainer(ContainerName)
}

func (m *Manager) Restart() error {
	return m.docker.RestartContainer(ContainerName)
}
