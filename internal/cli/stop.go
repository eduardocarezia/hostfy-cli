package cli

import (
	"fmt"

	"github.com/eduardocarezia/hostfy-cli/internal/docker"
	"github.com/eduardocarezia/hostfy-cli/internal/storage"
	"github.com/eduardocarezia/hostfy-cli/internal/ui"
	"github.com/spf13/cobra"
)

var stopCmd = &cobra.Command{
	Use:   "stop <app>",
	Short: "Para um app",
	Long:  `Para a execução de um app específico.`,
	Args:  cobra.ExactArgs(1),
	RunE:  runStop,
}

func runStop(cmd *cobra.Command, args []string) error {
	appName := args[0]

	// Verificar se existe
	if !storage.AppExists(appName) {
		ui.Error(fmt.Sprintf("App '%s' não encontrado", appName))
		return fmt.Errorf("app não encontrado")
	}

	dockerClient, err := docker.NewClient()
	if err != nil {
		ui.Error("Erro ao conectar ao Docker: " + err.Error())
		return err
	}
	defer dockerClient.Close()

	ui.Info(fmt.Sprintf("Parando %s...", appName))

	if err := dockerClient.StopContainer(appName); err != nil {
		ui.Error("Erro ao parar: " + err.Error())
		return err
	}

	ui.Success(fmt.Sprintf("%s parado!", appName))
	return nil
}
