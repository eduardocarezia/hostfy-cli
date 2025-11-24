package cli

import (
	"fmt"

	"github.com/eduardocarezia/hostfy-cli/internal/docker"
	"github.com/eduardocarezia/hostfy-cli/internal/storage"
	"github.com/eduardocarezia/hostfy-cli/internal/ui"
	"github.com/spf13/cobra"
)

var listCmd = &cobra.Command{
	Use:   "list",
	Short: "Lista apps instalados",
	Long:  `Mostra todos os apps instalados e seus status.`,
	RunE:  runList,
}

func runList(cmd *cobra.Command, args []string) error {
	apps, err := storage.ListApps()
	if err != nil {
		ui.Error("Erro ao listar apps: " + err.Error())
		return err
	}

	if len(apps) == 0 {
		ui.Info("Nenhum app instalado")
		fmt.Println()
		fmt.Printf("Instale seu primeiro app: %s\n", ui.Cyan("hostfy install <app> --domain <seu.dominio.com>"))
		return nil
	}

	dockerClient, err := docker.NewClient()
	if err != nil {
		ui.Error("Erro ao conectar ao Docker: " + err.Error())
		return err
	}
	defer dockerClient.Close()

	fmt.Println()
	fmt.Printf("%s\n", ui.BoldCyan("Apps instalados:"))
	fmt.Println()

	for _, app := range apps {
		running, _ := dockerClient.ContainerRunning(app.Name)
		status := ui.Red("parado")
		statusIcon := "○"
		if running {
			status = ui.Green("rodando")
			statusIcon = "●"
		}

		fmt.Printf("  %s %s  %s\n", statusIcon, ui.Bold(app.Name), status)
		fmt.Printf("    URL:    https://%s\n", app.Domain)
		fmt.Printf("    Imagem: %s\n", app.Image)
		fmt.Println()
	}

	return nil
}
