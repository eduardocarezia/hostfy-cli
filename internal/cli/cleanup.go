package cli

import (
	"fmt"
	"strings"

	"github.com/eduardocarezia/hostfy-cli/internal/docker"
	"github.com/eduardocarezia/hostfy-cli/internal/services"
	"github.com/eduardocarezia/hostfy-cli/internal/storage"
	"github.com/eduardocarezia/hostfy-cli/internal/ui"
	"github.com/spf13/cobra"
)

var cleanupCmd = &cobra.Command{
	Use:   "cleanup",
	Short: "Remove containers e databases órfãos",
	Long: `Remove containers e databases que não estão associados a nenhum app.

Útil para limpar recursos deixados por instalações que falharam.

Exemplos:
  hostfy cleanup           # Mostra o que seria removido
  hostfy cleanup --force   # Remove sem confirmação`,
	RunE: runCleanup,
}

var (
	cleanupForce bool
)

func init() {
	cleanupCmd.Flags().BoolVar(&cleanupForce, "force", false, "Remove sem confirmação")
}

func runCleanup(cmd *cobra.Command, args []string) error {
	dockerClient, err := docker.NewClient()
	if err != nil {
		ui.Error("Erro ao conectar ao Docker: " + err.Error())
		return err
	}
	defer dockerClient.Close()

	// Carregar apps instalados
	apps, _ := storage.ListApps()

	// Criar mapa de containers válidos
	validContainers := make(map[string]bool)
	validDatabases := make(map[string]bool)

	for _, app := range apps {
		if app.IsStack && len(app.Containers) > 0 {
			for _, c := range app.Containers {
				validContainers[fmt.Sprintf("%s-%s", app.Name, c.Name)] = true
			}
		} else {
			validContainers[app.Name] = true
		}
		if app.Database != "" {
			validDatabases[app.Database] = true
		}
	}

	// Encontrar containers órfãos (com label hostfy.managed)
	orphanContainers, err := findOrphanContainers(dockerClient, validContainers)
	if err != nil {
		ui.Warning("Erro ao buscar containers órfãos: " + err.Error())
	}

	// Encontrar databases órfãos
	var orphanDatabases []string
	secrets, err := storage.LoadSecrets()
	if err == nil {
		pgManager := services.NewPostgresManager(dockerClient, secrets)
		running, _ := pgManager.IsRunning()
		if running {
			dbs, err := pgManager.ListDatabases()
			if err == nil {
				for _, db := range dbs {
					if !validDatabases[db] {
						orphanDatabases = append(orphanDatabases, db)
					}
				}
			}
		}
	}

	// Mostrar o que foi encontrado
	if len(orphanContainers) == 0 && len(orphanDatabases) == 0 {
		ui.Success("Nenhum recurso órfão encontrado!")
		return nil
	}

	ui.Info("Recursos órfãos encontrados:")
	fmt.Println()

	if len(orphanContainers) > 0 {
		fmt.Printf("  %s Containers:\n", ui.Yellow("⚠"))
		for _, c := range orphanContainers {
			fmt.Printf("     • %s\n", c)
		}
	}

	if len(orphanDatabases) > 0 {
		fmt.Printf("  %s Databases:\n", ui.Yellow("⚠"))
		for _, db := range orphanDatabases {
			fmt.Printf("     • %s\n", db)
		}
	}
	fmt.Println()

	// Se não for force, apenas mostra
	if !cleanupForce {
		ui.Info("Execute 'hostfy cleanup --force' para remover estes recursos.")
		return nil
	}

	// Remover containers
	if len(orphanContainers) > 0 {
		ui.Info("Removendo containers órfãos...")
		for _, containerName := range orphanContainers {
			// Parar primeiro
			dockerClient.StopContainer(containerName)
			// Remover
			if err := dockerClient.RemoveContainer(containerName, true); err != nil {
				ui.Warning(fmt.Sprintf("Erro ao remover %s: %s", containerName, err.Error()))
			} else {
				ui.Success(fmt.Sprintf("  %s removido", containerName))
			}
		}
	}

	// Remover databases
	if len(orphanDatabases) > 0 && secrets != nil {
		ui.Info("Removendo databases órfãos...")
		pgManager := services.NewPostgresManager(dockerClient, secrets)
		for _, db := range orphanDatabases {
			if err := pgManager.DropDatabase(db); err != nil {
				ui.Warning(fmt.Sprintf("Erro ao remover %s: %s", db, err.Error()))
			} else {
				ui.Success(fmt.Sprintf("  %s removido", db))
			}
		}
	}

	fmt.Println()
	ui.Success("Limpeza concluída!")
	return nil
}

// findOrphanContainers encontra containers com label hostfy.managed que não estão em uso
func findOrphanContainers(dockerClient *docker.Client, validContainers map[string]bool) ([]string, error) {
	containers, err := dockerClient.ListContainersByLabel("hostfy.managed", "true")
	if err != nil {
		return nil, err
	}

	var orphans []string
	for _, c := range containers {
		// Remover / do início do nome
		name := strings.TrimPrefix(c, "/")
		if !validContainers[name] {
			orphans = append(orphans, name)
		}
	}
	return orphans, nil
}
