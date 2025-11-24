package cli

import (
	"fmt"

	"github.com/eduardocarezia/hostfy-cli/internal/docker"
	"github.com/eduardocarezia/hostfy-cli/internal/storage"
	"github.com/eduardocarezia/hostfy-cli/internal/ui"
	"github.com/spf13/cobra"
)

var restartCmd = &cobra.Command{
	Use:   "restart <app|all>",
	Short: "Reinicia um app ou todos os serviços",
	Long:  `Reinicia um app específico ou todos os serviços do hostfy.`,
	Args:  cobra.ExactArgs(1),
	RunE:  runRestart,
}

func runRestart(cmd *cobra.Command, args []string) error {
	target := args[0]

	dockerClient, err := docker.NewClient()
	if err != nil {
		ui.Error("Erro ao conectar ao Docker: " + err.Error())
		return err
	}
	defer dockerClient.Close()

	if target == "all" {
		return restartAll(dockerClient)
	}

	// Verificar se existe
	if !storage.AppExists(target) {
		ui.Error(fmt.Sprintf("App '%s' não encontrado", target))
		return fmt.Errorf("app não encontrado")
	}

	ui.Info(fmt.Sprintf("Reiniciando %s...", target))

	if err := dockerClient.RestartContainer(target); err != nil {
		ui.Error("Erro ao reiniciar: " + err.Error())
		return err
	}

	ui.Success(fmt.Sprintf("%s reiniciado!", target))
	return nil
}

func restartAll(dockerClient *docker.Client) error {
	ui.Info("Reiniciando todos os serviços...")

	// Reiniciar apps
	apps, _ := storage.ListApps()
	for _, app := range apps {
		if err := dockerClient.RestartContainer(app.Name); err != nil {
			ui.Warning(fmt.Sprintf("Erro ao reiniciar %s: %s", app.Name, err.Error()))
		} else {
			ui.Success(fmt.Sprintf("%s reiniciado", app.Name))
		}
	}

	ui.Success("Todos os serviços reiniciados!")
	return nil
}
