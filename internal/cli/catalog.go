package cli

import (
	"fmt"

	"github.com/hostfy/cli/internal/catalog"
	"github.com/hostfy/cli/internal/ui"
	"github.com/spf13/cobra"
)

var catalogCmd = &cobra.Command{
	Use:   "catalog",
	Short: "Lista apps disponíveis no catálogo",
	Long:  `Mostra todos os apps disponíveis para instalação.`,
	RunE:  runCatalog,
}

var catalogRefresh bool

func init() {
	catalogCmd.Flags().BoolVar(&catalogRefresh, "refresh", false, "Força atualização do catálogo")
}

func runCatalog(cmd *cobra.Command, args []string) error {
	if catalogRefresh {
		ui.Info("Atualizando catálogo...")
	}

	apps, err := catalog.ListApps()
	if err != nil {
		ui.Error("Erro ao buscar catálogo: " + err.Error())
		return err
	}

	if len(apps) == 0 {
		ui.Warning("Nenhum app encontrado no catálogo")
		return nil
	}

	fmt.Println()
	fmt.Printf("%s\n", ui.BoldCyan("Apps disponíveis:"))
	fmt.Println()

	for name, app := range apps {
		deps := ""
		if len(app.Dependencies) > 0 {
			deps = fmt.Sprintf(" [deps: %v]", app.Dependencies)
		}
		fmt.Printf("  %s  %s%s\n", ui.Green("•"), ui.Bold(name), deps)
		fmt.Printf("    %s\n", app.Description)
		fmt.Println()
	}

	fmt.Printf("Para instalar: %s\n", ui.Cyan("hostfy install <app> --domain <seu.dominio.com>"))
	fmt.Println()

	return nil
}
