package cli

import (
	"fmt"

	"github.com/eduardocarezia/hostfy-cli/internal/docker"
	"github.com/eduardocarezia/hostfy-cli/internal/services"
	"github.com/eduardocarezia/hostfy-cli/internal/storage"
	"github.com/eduardocarezia/hostfy-cli/internal/ui"
	"github.com/spf13/cobra"
)

var removeCmd = &cobra.Command{
	Use:   "remove <app>",
	Short: "Remove um app instalado",
	Long:  `Remove um app instalado. Por padrão mantém os dados (volumes).`,
	Args:  cobra.ExactArgs(1),
	RunE:  runRemove,
}

var removePurge bool

func init() {
	removeCmd.Flags().BoolVar(&removePurge, "purge", false, "Remove também os dados (volumes e database)")
}

func runRemove(cmd *cobra.Command, args []string) error {
	appName := args[0]

	// Verificar se existe
	appConfig, err := storage.LoadApp(appName)
	if err != nil {
		ui.Error(fmt.Sprintf("App '%s' não encontrado", appName))
		return err
	}

	steps := 3
	if removePurge && appConfig.Database != "" {
		steps = 4
	}
	progress := ui.NewProgress(steps)

	// 1. Conectar ao Docker
	dockerClient, err := docker.NewClient()
	if err != nil {
		ui.Error("Erro ao conectar ao Docker: " + err.Error())
		return err
	}
	defer dockerClient.Close()

	// 2. Parar container
	progress.Step("Parando container...")
	dockerClient.StopContainer(appName)

	// 3. Remover container
	progress.Step("Removendo container...")
	if err := dockerClient.RemoveContainer(appName, true); err != nil {
		ui.Warning("Container pode já ter sido removido")
	}

	// 4. Remover database se purge
	if removePurge && appConfig.Database != "" {
		progress.Step("Removendo database...")
		secrets, _ := storage.LoadSecrets()
		pgManager := services.NewPostgresManager(dockerClient, secrets)
		if err := pgManager.DropDatabase(appConfig.Database); err != nil {
			ui.Warning("Erro ao remover database: " + err.Error())
		}
	}

	// 5. Remover configuração
	progress.Step("Removendo configuração...")
	if err := storage.DeleteApp(appName); err != nil {
		ui.Warning("Erro ao remover configuração: " + err.Error())
	}

	ui.Success(fmt.Sprintf("%s removido!", appName))

	if !removePurge {
		ui.Info("Volumes mantidos. Use --purge para remover dados também.")
	}

	return nil
}
