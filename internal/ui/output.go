package ui

import (
	"fmt"
	"time"

	"github.com/briandowns/spinner"
	"github.com/fatih/color"
)

var (
	Green   = color.New(color.FgGreen).SprintFunc()
	Yellow  = color.New(color.FgYellow).SprintFunc()
	Red     = color.New(color.FgRed).SprintFunc()
	Cyan    = color.New(color.FgCyan).SprintFunc()
	Bold    = color.New(color.Bold).SprintFunc()
	BoldCyan = color.New(color.Bold, color.FgCyan).SprintFunc()
)

type Progress struct {
	current int
	total   int
	spinner *spinner.Spinner
}

func NewProgress(total int) *Progress {
	s := spinner.New(spinner.CharSets[14], 100*time.Millisecond)
	s.Color("cyan")
	return &Progress{
		current: 0,
		total:   total,
		spinner: s,
	}
}

func (p *Progress) Step(message string) {
	p.current++
	p.spinner.Stop()
	fmt.Printf("%s %s\n", Cyan(fmt.Sprintf("[%d/%d]", p.current, p.total)), message)
}

func (p *Progress) SubStep(message string) {
	fmt.Printf("      %s %s\n", Yellow("→"), message)
}

func (p *Progress) Start(message string) {
	p.spinner.Suffix = " " + message
	p.spinner.Start()
}

func (p *Progress) Stop() {
	p.spinner.Stop()
}

func Success(message string) {
	fmt.Printf("%s %s\n", Green("✓"), message)
}

func Error(message string) {
	fmt.Printf("%s %s\n", Red("✗"), message)
}

func Warning(message string) {
	fmt.Printf("%s %s\n", Yellow("⚠"), message)
}

func Info(message string) {
	fmt.Printf("%s %s\n", Cyan("ℹ"), message)
}

func PrintCredentials(url, user, password string) {
	fmt.Println()
	fmt.Printf("  %s    %s\n", Bold("URL:"), Cyan(url))
	if user != "" {
		fmt.Printf("  %s   %s\n", Bold("User:"), user)
	}
	if password != "" {
		fmt.Printf("  %s  %s\n", Bold("Senha:"), password)
	}
	fmt.Println()
}

func PrintBox(title string, lines []string) {
	fmt.Println()
	fmt.Printf("%s\n", BoldCyan("════════════════════════════════════════"))
	fmt.Printf("  %s\n", Bold(title))
	fmt.Printf("%s\n", BoldCyan("════════════════════════════════════════"))
	fmt.Println()
	for _, line := range lines {
		fmt.Printf("  %s\n", line)
	}
	fmt.Println()
}
