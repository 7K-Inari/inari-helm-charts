// Package kind is a thin exec wrapper over the kind CLI — cluster lifecycle
// for the golden-path provisioner plus inspection helpers.
package kind

import (
	"strings"

	"7k-inari/inari-release-bundle/scripts/e2e/stack/internal/kube"
)

// Create creates a kind cluster from the given config YAML (may be empty
// for a default cluster) and waits up to 60s for readiness.
func Create(name, configYAML string) error {
	args := []string{"create", "cluster", "--name", name, "--wait", "60s"}
	if configYAML != "" {
		_, err := kube.RunStdin("kind", configYAML, append(args, "--config", "-")...)
		return err
	}
	_, err := kube.Run("kind", args...)
	return err
}

// Delete removes the cluster; a missing cluster is not an error.
func Delete(name string) error {
	exists, err := ClusterExists(name)
	if err != nil || !exists {
		return err
	}
	_, err = kube.Run("kind", "delete", "cluster", "--name", name)
	return err
}

// Recreate deletes any existing cluster of the same name and creates a fresh
// one (golden-path parity: every run starts from an empty cluster).
func Recreate(name, configYAML string) error {
	if err := Delete(name); err != nil {
		return err
	}
	return Create(name, configYAML)
}

// LoadImages side-loads docker images into the cluster nodes.
func LoadImages(name string, images ...string) error {
	args := append([]string{"load", "docker-image"}, images...)
	args = append(args, "--name", name)
	_, err := kube.Run("kind", args...)
	return err
}

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
