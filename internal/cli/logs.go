package cli

import (
	"fmt"
	"io"
	"os"

	"github.com/eduardocarezia/hostfy-cli/internal/docker"
	"github.com/eduardocarezia/hostfy-cli/internal/storage"
	"github.com/eduardocarezia/hostfy-cli/internal/ui"
	"github.com/spf13/cobra"
)

var logsCmd = &cobra.Command{
	Use:   "logs <app>",
	Short: "Mostra logs de um app",
	Long:  `Exibe os logs do container de um app instalado.`,
	Args:  cobra.ExactArgs(1),
	RunE:  runLogs,
}

var (
	logsFollow bool
	logsTail   string
)

func init() {
	logsCmd.Flags().BoolVarP(&logsFollow, "follow", "f", false, "Segue os logs em tempo real")
	logsCmd.Flags().StringVar(&logsTail, "tail", "100", "Número de linhas a mostrar")
}

func runLogs(cmd *cobra.Command, args []string) error {
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

	reader, err := dockerClient.GetContainerLogs(appName, logsTail, logsFollow)
	if err != nil {
		ui.Error("Erro ao obter logs: " + err.Error())
		return err
	}
	defer reader.Close()

	_, err = io.Copy(os.Stdout, reader)
	return err
}
