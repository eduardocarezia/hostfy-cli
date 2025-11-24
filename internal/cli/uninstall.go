package cli

import (
	"github.com/spf13/cobra"
)

var uninstallCmd = &cobra.Command{
	Use:   "uninstall <app>",
	Short: "Remove um app instalado (alias para 'remove')",
	Long:  `Remove um app instalado completamente (container, volumes, database e secrets).`,
	Args:  cobra.ExactArgs(1),
	RunE:  runRemove,
}

func init() {
	// Usa a mesma variável removeKeepData de remove.go
	uninstallCmd.Flags().BoolVar(&removeKeepData, "keep-data", false, "Mantém volumes e secrets para reinstalação futura")
}
