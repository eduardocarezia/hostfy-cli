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
	Long:  `Remove um app instalado completamente (container, volumes, database e secrets).`,
	Args:  cobra.ExactArgs(1),
	RunE:  runRemove,
}

var (
	removePurge    bool // deprecated, mantido para compatibilidade
	removeKeepData bool
)

func init() {
	removeCmd.Flags().BoolVar(&removeKeepData, "keep-data", false, "Mantém volumes e secrets para reinstalação futura")
	removeCmd.Flags().BoolVar(&removePurge, "purge", false, "Deprecated: agora o padrão já remove tudo")
	removeCmd.Flags().MarkHidden("purge") // esconde a flag deprecated
}

func runRemove(cmd *cobra.Command, args []string) error {
	appName := args[0]

	// Verificar se existe
	appConfig, err := storage.LoadApp(appName)
	if err != nil {
		ui.Error(fmt.Sprintf("App '%s' não encontrado", appName))
		return err
	}

	// Calcular steps baseado no que será removido
	steps := 4 // container + config + volumes + secrets
	if appConfig.Database != "" && !removeKeepData {
		steps = 5 // + database
	}
	if removeKeepData {
		steps = 4 // container + config + backup secrets
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

	if removeKeepData {
		// Modo --keep-data: salva secrets para reinstalação futura
		progress.Step("Salvando secrets para reinstalação...")
		if err := storage.BackupAppSecrets(appConfig); err != nil {
			ui.Warning("Erro ao salvar backup de secrets: " + err.Error())
		}
	} else {
		// Modo padrão: remove TUDO

		// 4. Remover database se existir
		if appConfig.Database != "" {
			progress.Step("Removendo database...")
			secrets, _ := storage.LoadSecrets()
			pgManager := services.NewPostgresManager(dockerClient, secrets)
			if err := pgManager.DropDatabase(appConfig.Database); err != nil {
				ui.Warning("Erro ao remover database: " + err.Error())
			}
		}

		// 5. Remover volumes do app
		progress.Step("Removendo volumes...")
		if err := dockerClient.RemoveVolumesByPrefix(appName + "_"); err != nil {
			ui.Warning("Erro ao remover volumes: " + err.Error())
		}

		// 6. Remover backup de secrets se existir
		if err := storage.DeleteAppSecretsBackup(appName); err != nil {
			ui.Warning("Erro ao remover backup de secrets: " + err.Error())
		}
	}

	// Remover configuração
	progress.Step("Removendo configuração...")
	if err := storage.DeleteApp(appName); err != nil {
		ui.Warning("Erro ao remover configuração: " + err.Error())
	}

	ui.Success(fmt.Sprintf("%s removido completamente!", appName))

	if removeKeepData {
		ui.Info("Volumes e secrets mantidos para reinstalação futura.")
	}

	return nil
}
