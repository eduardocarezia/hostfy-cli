package cli

import (
	"github.com/spf13/cobra"
)

var rootCmd = &cobra.Command{
	Use:   "hostfy",
	Short: "hostfy - Self-hosted app deployment made simple",
	Long: `hostfy é um CLI para deploy simplificado de aplicações self-hosted.

Instale apps do catálogo com um comando, configure domínios automaticamente
e deixe o hostfy cuidar das dependências.

Comece com:
  hostfy init
  hostfy catalog
  hostfy install <app> --domain <seu.dominio.com>`,
}

func Execute() error {
	return rootCmd.Execute()
}

func init() {
	rootCmd.AddCommand(initCmd)
	rootCmd.AddCommand(catalogCmd)
	rootCmd.AddCommand(installCmd)
	rootCmd.AddCommand(removeCmd)
	rootCmd.AddCommand(updateCmd)
	rootCmd.AddCommand(pullCmd)
	rootCmd.AddCommand(configCmd)
	rootCmd.AddCommand(listCmd)
	rootCmd.AddCommand(statusCmd)
	rootCmd.AddCommand(logsCmd)
	rootCmd.AddCommand(secretsCmd)
	rootCmd.AddCommand(startCmd)
	rootCmd.AddCommand(stopCmd)
	rootCmd.AddCommand(restartCmd)
}
