package main

import (
	"fmt"
	"runtime"
)

func main() {
	fmt.Printf("Build Success! OS: %s, Arch: %s\n", runtime.GOOS, runtime.GOARCH)
}
