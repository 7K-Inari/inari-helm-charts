// Package quarflag holds the -include-quarantined flag definition for the
// stack suite. It lives in its own tiny, build-tag-free package because the
// flag is passed to EVERY test binary matched by `go test ./... -args
// -include-quarantined` (nightly mode in .github/workflows/e2e-stack.yaml):
// any test binary that does not define the flag dies with "flag provided
// but not defined". Test packages that neither import suite nor run
// quarantined tests (internal/kc, internal/poll) blank-import this package
// in a flags_test.go so their binaries accept (and ignore) the flag.
package quarflag

import "flag"

// IncludeQuarantined is registered on go test's flag set; the gate simply
// omits it (default false → quarantined tests skip). Nightly:
//
//	go test -tags=e2e ... -args -include-quarantined
var IncludeQuarantined = flag.Bool("include-quarantined", false,
	"run tests quarantined for flakiness (nightly only; the release gate never sets this)")
