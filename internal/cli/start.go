package cli

import (
	"fmt"

	"github.com/eduardocarezia/hostfy-cli/internal/docker"
	"github.com/eduardocarezia/hostfy-cli/internal/services"
	"github.com/eduardocarezia/hostfy-cli/internal/storage"
	"github.com/eduardocarezia/hostfy-cli/internal/traefik"
	"github.com/eduardocarezia/hostfy-cli/internal/ui"
	"github.com/spf13/cobra"
)

var startCmd = &cobra.Command{
	Use:   "start <app|all>",
	Short: "Inicia um app ou todos os serviços",
	Long:  `Inicia um app específico ou todos os serviços do hostfy.`,
	Args:  cobra.ExactArgs(1),
	RunE:  runStart,
}

func runStart(cmd *cobra.Command, args []string) error {
	target := args[0]

	dockerClient, err := docker.NewClient()
	if err != nil {
		ui.Error("Erro ao conectar ao Docker: " + err.Error())
		return err
	}
	defer dockerClient.Close()

	if target == "all" {
		return startAll(dockerClient)
	}

	// Verificar se existe
	if !storage.AppExists(target) {
		ui.Error(fmt.Sprintf("App '%s' não encontrado", target))
		return fmt.Errorf("app não encontrado")
	}

	ui.Info(fmt.Sprintf("Iniciando %s...", target))

	if err := dockerClient.StartContainer(target); err != nil {
		ui.Error("Erro ao iniciar: " + err.Error())
		return err
	}

	ui.Success(fmt.Sprintf("%s iniciado!", target))
	return nil
}

func startAll(dockerClient *docker.Client) error {
	progress := ui.NewProgress(4)

	// 1. Traefik
	progress.Step("Iniciando Traefik...")
	traefikManager := traefik.NewManager(dockerClient)
	if err := traefikManager.Start(); err != nil {
		ui.Warning("Erro ao iniciar Traefik: " + err.Error())
	}

	// 2. Postgres
	progress.Step("Iniciando Postgres...")
	secrets, _ := storage.EnsureSecrets()
	pgManager := services.NewPostgresManager(dockerClient, secrets)
	if err := pgManager.EnsureRunning(); err != nil {
		ui.Warning("Erro ao iniciar Postgres: " + err.Error())
	}

	// 3. Redis
	progress.Step("Iniciando Redis...")
	redisManager := services.NewRedisManager(dockerClient)
	if err := redisManager.EnsureRunning(); err != nil {
		ui.Warning("Erro ao iniciar Redis: " + err.Error())
	}

	// 4. Apps
	progress.Step("Iniciando apps...")
	apps, _ := storage.ListApps()
	for _, app := range apps {
		if err := dockerClient.StartContainer(app.Name); err != nil {
			ui.Warning(fmt.Sprintf("Erro ao iniciar %s: %s", app.Name, err.Error()))
		} else {
			progress.SubStep(fmt.Sprintf("%s iniciado", app.Name))
		}
	}

	ui.Success("Todos os serviços iniciados!")
	return nil
}
