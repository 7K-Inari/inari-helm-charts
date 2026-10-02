// Package kind is a thin exec wrapper over the kind CLI. Phase 1 only needs
// cluster inspection (provisioning stays in golden-path.sh until phases 2–3).
package kind

import (
	"strings"

	"7k-inari/inari-release-bundle/scripts/e2e/stack/internal/kube"
)

// ClusterExists reports whether a kind cluster with the given name exists.
func ClusterExists(name string) (bool, error) {
	out, err := kube.Run("kind", "get", "clusters")
	if err != nil {
		return false, err
	}
	for _, line := range strings.Split(out, "\n") {
		if strings.TrimSpace(line) == name {
			return true, nil
		}
	}
	return false, nil
}

// DockerExec runs cmd inside the kind control-plane node container.
func DockerExec(cluster string, cmd ...string) (string, error) {
	args := append([]string{"exec", cluster + "-control-plane"}, cmd...)
	return kube.Run("docker", args...)
}
