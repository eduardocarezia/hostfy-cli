package services

import (
	"fmt"
	"time"

	"github.com/eduardocarezia/hostfy-cli/internal/docker"
)

const (
	RedisContainerName = "hostfy_redis"
	RedisImage         = "redis:7-alpine"
	RedisPort          = "6379"
)

type RedisManager struct {
	docker *docker.Client
}

func NewRedisManager(dockerClient *docker.Client) *RedisManager {
	return &RedisManager{docker: dockerClient}
}

func (m *RedisManager) IsRunning() (bool, error) {
	return m.docker.ContainerRunning(RedisContainerName)
}

func (m *RedisManager) EnsureRunning() error {
	running, err := m.IsRunning()
	if err != nil {
		return err
	}
	if running {
		return nil
	}

	exists, err := m.docker.ContainerExists(RedisContainerName)
	if err != nil {
		return err
	}

	if exists {
		if err := m.docker.StartContainer(RedisContainerName); err != nil {
			return err
		}
		return m.docker.WaitForHealthy(RedisContainerName, 30*time.Second)
	}

	if err := m.docker.PullImage(RedisImage); err != nil {
		return err
	}

	cfg := &docker.ContainerConfig{
		Name:  RedisContainerName,
		Image: RedisImage,
		Env:   map[string]string{},
		Volumes: []string{
			"hostfy_redis_data:/data",
		},
		Ports: map[string]string{
			RedisPort: RedisPort,
		},
		Labels: map[string]string{
			"hostfy.managed": "true",
			"hostfy.service": "redis",
		},
		Command: []string{"redis-server", "--appendonly", "yes"},
		Restart: "always",
	}

	id, err := m.docker.CreateContainer(cfg)
	if err != nil {
		return fmt.Errorf("erro ao criar container Redis: %w", err)
	}

	if err := m.docker.StartContainer(id); err != nil {
		return err
	}

	return m.docker.WaitForHealthy(RedisContainerName, 30*time.Second)
}

func (m *RedisManager) Stop() error {
	return m.docker.StopContainer(RedisContainerName)
}
