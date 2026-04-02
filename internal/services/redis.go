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
		// Verificar se está em modo slave (READONLY) ou com comando bugado
		needsFix := false
		if isSlaveMode, err := docker.IsRedisInSlaveMode(RedisContainerName); err == nil && isSlaveMode {
			needsFix = true
		}
		if hasBuggyCmd, err := m.docker.ContainerHasBuggyCommand(RedisContainerName, "--replicaof"); err == nil && hasBuggyCmd {
			needsFix = true
		}
		if needsFix {
			// Recriar container com configuração correta
			m.docker.StopContainer(RedisContainerName)
			m.docker.RemoveContainer(RedisContainerName, false) // manter volumes
			return m.create()
		}
		return nil
	}

	exists, err := m.docker.ContainerExists(RedisContainerName)
	if err != nil {
		return err
	}

	if exists {
		// Verificar se tem comando bugado antes de simplesmente iniciar
		if hasBuggyCmd, err := m.docker.ContainerHasBuggyCommand(RedisContainerName, "--replicaof"); err == nil && hasBuggyCmd {
			m.docker.RemoveContainer(RedisContainerName, false)
			return m.create()
		}
		if err := m.docker.StartContainer(RedisContainerName); err != nil {
			return err
		}
		return m.docker.WaitForHealthy(RedisContainerName, 30*time.Second)
	}

	return m.create()
}

func (m *RedisManager) create() error {
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
		Command:     []string{"redis-server", "--appendonly", "yes"},
		NetworkName: docker.NetworkName,
		Restart:     "always",
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
