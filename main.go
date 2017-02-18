package main

import (
	"fmt"
	"log"
	"os"

	"github.com/rvflash/awql/conf"
	"github.com/rvflash/awql/ui"
)

func main() {
	conf := conf.New()
	if err := conf.Init(); err != nil {
		exit(err)
	}
	// Launch the environment.
	var src ui.Scanner
	if conf.IsInteractive() {
		src = ui.NewTerminal(conf)
	} else {
		src = ui.NewCommandLine(conf)
	}
	if err := src.Scan(); err != nil {
		exit(err)
	}
}

// Exit causes the current program to exit with the appropriate status code.
func exit(err error) {
	if err == nil {
		// See you soon.
		os.Exit(0)
	}
	// An error occurred, exits with the appropriate behavior.
	switch err.(type) {
	case *conf.FlagError:
		fmt.Println(err)
		conf.Usage()
		os.Exit(1)
	default:
		log.Fatal(err)
	}
}
