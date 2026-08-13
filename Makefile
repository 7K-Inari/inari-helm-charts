CHART_DIR := charts/inari-platform
BACKUP_DIR ?= ./backups

.PHONY: dev-up dev-down backup restore dr-drill lint test package clean

dev-up: ## Create the kind cluster and install the platform stack
	./scripts/bootstrap.sh

dev-down: ## Delete the kind dev cluster
	kind delete cluster --name inari-platform

backup: ## Back up PostgreSQL, Keycloak, OpenFGA and NATS into BACKUP_DIR
	./scripts/backup.sh $(BACKUP_DIR)

restore: ## Restore from a backup tarball: make restore BACKUP=backups/inari-backup-<ts>.tgz
	./scripts/restore.sh $(BACKUP)

dr-drill: ## Provision a fresh kind cluster, restore BACKUP and verify: make dr-drill BACKUP=...
	./scripts/dr-drill.sh $(BACKUP)

lint: ## helm lint + chart-testing lint
	helm lint $(CHART_DIR)
	ct lint --config ct.yaml

test: ## helm-unittest suite
	helm unittest $(CHART_DIR)

package: ## Package the chart into dist/
	mkdir -p dist
	helm dependency build $(CHART_DIR)
	helm package $(CHART_DIR) -d dist

clean:
	rm -rf dist $(BACKUP_DIR)
