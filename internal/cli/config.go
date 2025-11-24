package cli

import (
	"fmt"

	"github.com/spf13/cobra"
)

var configCmd = &cobra.Command{
	Use:   "config <app>",
	Short: "Configura um app instalado",
	Long:  `Alias para 'hostfy update'. Use --domain para mudar o domínio.`,
	Args:  cobra.ExactArgs(1),
	RunE:  runConfig,
}

var configDomain string

func init() {
	configCmd.Flags().StringVar(&configDomain, "domain", "", "Novo domínio")
}

func runConfig(cmd *cobra.Command, args []string) error {
	// Redireciona para update
	updateDomain = configDomain
	updateEnv = []string{}

	if configDomain == "" {
		fmt.Println("Use: hostfy config <app> --domain <novo.dominio.com>")
		return nil
	}

	return runUpdate(cmd, args)
}
