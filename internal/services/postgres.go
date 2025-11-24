package services

import (
	"fmt"
	"os/exec"
	"strings"
	"time"

	"github.com/hostfy/cli/internal/docker"
	"github.com/hostfy/cli/internal/storage"
)

const (
	PostgresContainerName = "hostfy_postgres"
	PostgresImage         = "postgres:15-alpine"
	PostgresPort          = "5432"
)

type PostgresManager struct {
	docker  *docker.Client
	secrets *storage.Secrets
}

func NewPostgresManager(dockerClient *docker.Client, secrets *storage.Secrets) *PostgresManager {
	return &PostgresManager{
		docker:  dockerClient,
		secrets: secrets,
	}
}

func (m *PostgresManager) IsRunning() (bool, error) {
	return m.docker.ContainerRunning(PostgresContainerName)
}

func (m *PostgresManager) EnsureRunning() error {
	running, err := m.IsRunning()
	if err != nil {
		return err
	}
	if running {
		return nil
	}

	exists, err := m.docker.ContainerExists(PostgresContainerName)
	if err != nil {
		return err
	}

	if exists {
		if err := m.docker.StartContainer(PostgresContainerName); err != nil {
			return err
		}
		return m.docker.WaitForHealthy(PostgresContainerName, 60*time.Second)
	}

	if err := m.docker.PullImage(PostgresImage); err != nil {
		return err
	}

	cfg := &docker.ContainerConfig{
		Name:  PostgresContainerName,
		Image: PostgresImage,
		Env: map[string]string{
			"POSTGRES_USER":     "hostfy",
			"POSTGRES_PASSWORD": m.secrets.PostgresPassword,
			"POSTGRES_DB":       "hostfy",
		},
		Volumes: []string{
			"hostfy_postgres_data:/var/lib/postgresql/data",
		},
		Ports: map[string]string{
			PostgresPort: PostgresPort,
		},
		Labels: map[string]string{
			"hostfy.managed": "true",
			"hostfy.service": "postgres",
		},
		Restart: "always",
	}

	id, err := m.docker.CreateContainer(cfg)
	if err != nil {
		return fmt.Errorf("erro ao criar container Postgres: %w", err)
	}

	if err := m.docker.StartContainer(id); err != nil {
		return err
	}

	return m.docker.WaitForHealthy(PostgresContainerName, 60*time.Second)
}

func (m *PostgresManager) CreateDatabase(dbName string) error {
	cmd := exec.Command("docker", "exec", PostgresContainerName, "psql",
		"-U", "hostfy",
		"-c", fmt.Sprintf("CREATE DATABASE %s;", dbName))

	output, err := cmd.CombinedOutput()
	if err != nil {
		if strings.Contains(string(output), "already exists") {
			return nil
		}
		return fmt.Errorf("erro ao criar database: %s", string(output))
	}
	return nil
}

func (m *PostgresManager) DropDatabase(dbName string) error {
	cmd := exec.Command("docker", "exec", PostgresContainerName, "psql",
		"-U", "hostfy",
		"-c", fmt.Sprintf("DROP DATABASE IF EXISTS %s;", dbName))

	output, err := cmd.CombinedOutput()
	if err != nil {
		return fmt.Errorf("erro ao dropar database: %s", string(output))
	}
	return nil
}

func (m *PostgresManager) ListDatabases() ([]string, error) {
	cmd := exec.Command("docker", "exec", PostgresContainerName, "psql",
		"-U", "hostfy",
		"-t", "-c", "SELECT datname FROM pg_database WHERE datistemplate = false AND datname != 'hostfy' AND datname != 'postgres';")

	output, err := cmd.Output()
	if err != nil {
		return nil, err
	}

	var dbs []string
	for _, line := range strings.Split(string(output), "\n") {
		db := strings.TrimSpace(line)
		if db != "" {
			dbs = append(dbs, db)
		}
	}
	return dbs, nil
}

func (m *PostgresManager) Stop() error {
	return m.docker.StopContainer(PostgresContainerName)
}
