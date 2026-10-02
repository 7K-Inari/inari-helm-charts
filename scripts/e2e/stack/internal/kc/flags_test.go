package kc

// The nightly runs `go test ./... -args -include-quarantined`, which passes
// the flag to EVERY test binary — including this one, which neither imports
// suite nor defines the flag and would otherwise die with "flag provided
// but not defined". Blank-import quarflag so this binary accepts (and
// ignores) it.
import _ "7k-inari/inari-release-bundle/scripts/e2e/stack/internal/quarflag"
