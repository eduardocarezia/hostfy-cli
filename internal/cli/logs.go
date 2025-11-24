package cli

import (
	"fmt"
	"io"
	"os"
	"strings"

	"github.com/eduardocarezia/hostfy-cli/internal/docker"
	"github.com/eduardocarezia/hostfy-cli/internal/storage"
	"github.com/eduardocarezia/hostfy-cli/internal/ui"
	"github.com/spf13/cobra"
)

var logsCmd = &cobra.Command{
	Use:   "logs <app>",
	Short: "Mostra logs de um app",
	Long: `Exibe os logs do container de um app instalado.

Para apps com múltiplos containers (Stacks), use -c para selecionar:
  hostfy logs n8n -c editor
  hostfy logs n8n -c worker`,
	Args: cobra.ExactArgs(1),
	RunE: runLogs,
}

var (
	logsFollow    bool
	logsTail      string
	logsContainer string
)

func init() {
	logsCmd.Flags().BoolVarP(&logsFollow, "follow", "f", false, "Segue os logs em tempo real")
	logsCmd.Flags().StringVar(&logsTail, "tail", "100", "Número de linhas a mostrar")
	logsCmd.Flags().StringVarP(&logsContainer, "container", "c", "", "Container específico (para Stacks: editor, worker, etc)")
}

func runLogs(cmd *cobra.Command, args []string) error {
	appName := args[0]

	// Verificar se existe
	if !storage.AppExists(appName) {
		ui.Error(fmt.Sprintf("App '%s' não encontrado", appName))
		return fmt.Errorf("app não encontrado")
	}

	// Carregar configuração do app
	appConfig, err := storage.LoadApp(appName)
	if err != nil {
		ui.Error("Erro ao carregar configuração: " + err.Error())
		return err
	}

	dockerClient, err := docker.NewClient()
	if err != nil {
		ui.Error("Erro ao conectar ao Docker: " + err.Error())
		return err
	}
	defer dockerClient.Close()

	// Determinar nome do container
	containerName := appName
	if appConfig.IsStack {
		containerName, err = resolveStackContainer(appConfig, logsContainer)
		if err != nil {
			return err
		}
	}

	reader, err := dockerClient.GetContainerLogs(containerName, logsTail, logsFollow)
	if err != nil {
		ui.Error("Erro ao obter logs: " + err.Error())
		return err
	}
	defer reader.Close()

	_, err = io.Copy(os.Stdout, reader)
	return err
}

// resolveStackContainer resolve o nome do container para uma Stack
func resolveStackContainer(app *storage.AppConfig, containerFlag string) (string, error) {
	if len(app.Containers) == 0 {
		return app.Name, nil
	}

	// Listar containers disponíveis
	var containerNames []string
	var mainContainer string
	for _, c := range app.Containers {
		containerNames = append(containerNames, c.Name)
		if c.IsMain {
			mainContainer = c.Name
		}
	}

	// Se nenhum container especificado
	if containerFlag == "" {
		// Se tem main, usa o main
		if mainContainer != "" {
			ui.Info(fmt.Sprintf("Stack detectada. Usando container principal: %s", mainContainer))
			ui.Info(fmt.Sprintf("Containers disponíveis: %s", strings.Join(containerNames, ", ")))
			ui.Info("Use -c <container> para ver logs de outro container")
			fmt.Println()
			return fmt.Sprintf("%s-%s", app.Name, mainContainer), nil
		}
		// Senão, mostra erro e lista opções
		ui.Error(fmt.Sprintf("Stack '%s' tem múltiplos containers. Especifique com -c:", app.Name))
		for _, name := range containerNames {
			fmt.Printf("  hostfy logs %s -c %s\n", app.Name, name)
		}
		return "", fmt.Errorf("container não especificado")
	}

	// Verificar se o container existe
	for _, c := range app.Containers {
		if c.Name == containerFlag {
			return fmt.Sprintf("%s-%s", app.Name, containerFlag), nil
		}
	}

	// Container não encontrado
	ui.Error(fmt.Sprintf("Container '%s' não encontrado na stack '%s'", containerFlag, app.Name))
	fmt.Printf("Containers disponíveis: %s\n", strings.Join(containerNames, ", "))
	return "", fmt.Errorf("container não encontrado: %s", containerFlag)
}
