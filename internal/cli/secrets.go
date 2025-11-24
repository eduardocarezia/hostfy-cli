package cli

import (
	"fmt"

	"github.com/eduardocarezia/hostfy-cli/internal/storage"
	"github.com/eduardocarezia/hostfy-cli/internal/ui"
	"github.com/spf13/cobra"
)

var secretsCmd = &cobra.Command{
	Use:   "secrets <app>",
	Short: "Mostra credenciais de um app",
	Long:  `Exibe as credenciais e variáveis de ambiente sensíveis de um app.`,
	Args:  cobra.ExactArgs(1),
	RunE:  runSecrets,
}

func runSecrets(cmd *cobra.Command, args []string) error {
	appName := args[0]

	appConfig, err := storage.LoadApp(appName)
	if err != nil {
		ui.Error(fmt.Sprintf("App '%s' não encontrado", appName))
		return err
	}

	fmt.Println()
	fmt.Printf("%s %s\n", ui.BoldCyan("Credenciais de"), ui.Bold(appName))
	fmt.Println()

	fmt.Printf("  %s: https://%s\n", ui.Bold("URL"), appConfig.Domain)
	fmt.Println()

	// Mostrar envs que parecem ser credenciais
	fmt.Printf("  %s:\n", ui.Bold("Variáveis de ambiente"))
	for key, value := range appConfig.Env {
		// Mostrar todas as envs (pode filtrar por sensitivas depois)
		fmt.Printf("    %s=%s\n", key, value)
	}
	fmt.Println()

	if appConfig.Database != "" {
		secrets, _ := storage.LoadSecrets()
		fmt.Printf("  %s:\n", ui.Bold("Database"))
		fmt.Printf("    Host:     hostfy_postgres\n")
		fmt.Printf("    Port:     5432\n")
		fmt.Printf("    Database: %s\n", appConfig.Database)
		fmt.Printf("    User:     hostfy\n")
		fmt.Printf("    Password: %s\n", secrets.PostgresPassword)
		fmt.Println()
	}

	return nil
}
