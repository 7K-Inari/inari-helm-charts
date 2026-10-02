// Package helm is a thin exec wrapper over the helm CLI — parity with
// chart-testing (CLI exec only, no helm Go SDK): there is zero magic
// between the provisioner and the CLI behavior, and failures surface the
// exact command + stderr, mirroring golden-path.sh.
package helm

import (
	"strings"

	"7k-inari/inari-release-bundle/scripts/e2e/stack/internal/kube"
)

// RepoAdd registers a helm repo. MUST be called serially before any
// concurrent installs: helm's local repo cache is shared state and
// concurrent `helm repo` commands race (golden-path.sh did all repo setup
// serially up front for the same reason).
func RepoAdd(name, url string) error {
	_, err := kube.Run("helm", "repo", "add", name, url)
	return err
}

// RepoUpdate refreshes all registered repos (also serial-only).
func RepoUpdate() error {
	_, err := kube.Run("helm", "repo", "update")
	return err
}

// DependencyBuild vendors a chart's Chart.yaml dependencies into charts/
// (helm verifies dependencies even for disabled subcharts).
func DependencyBuild(chartDir string) error {
	_, err := kube.Run("helm", "dependency", "build", chartDir)
	return err
}

// UpgradeInstall runs `helm upgrade --install <release> <args...>`; the
// caller passes the chart, namespace, values and --wait/--timeout flags.
func UpgradeInstall(release string, args ...string) error {
	full := append([]string{"upgrade", "--install", release}, args...)
	_, err := kube.Run("helm", full...)
	return err
}

// Installed reports whether the release exists in the namespace.
func Installed(ns, release string) (bool, error) {
	out, err := kube.Run("helm", "list", "-n", ns, "--filter", "^"+release+"$", "-q")
	if err != nil {
		return false, err
	}
	for _, line := range strings.Split(out, "\n") {
		if strings.TrimSpace(line) == release {
			return true, nil
		}
	}
	return false, nil
}
