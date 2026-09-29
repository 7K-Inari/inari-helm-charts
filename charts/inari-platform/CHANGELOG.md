# Changelog

## [0.4.0](https://github.com/7K-Inari/inari-helm-charts/compare/platform-config-v0.3.0...platform-config-v0.4.0) (2026-09-18)


### Features

* **platform-config:** seed platform-admins group with dev-admin member ([#44](https://github.com/7K-Inari/inari-helm-charts/issues/44)) ([e36f4d9](https://github.com/7K-Inari/inari-helm-charts/commit/e36f4d9bab747dd5f79b1fc30b7e35e18fa23694))


### Bug Fixes

* **ci:** bump chart-testing-action to v2.8.0 (stale cosign v2.4.1 pin) ([#48](https://github.com/7K-Inari/inari-helm-charts/issues/48)) ([a937a43](https://github.com/7K-Inari/inari-helm-charts/commit/a937a43db98a8404464ac778262f4cfae8654f5c))

## [0.3.0](https://github.com/7K-Inari/inari-helm-charts/compare/platform-config-v0.2.2...platform-config-v0.3.0) (2026-09-12)


### Features

* **keycloak:** add inari-cli public client (device authorization grant) ([#46](https://github.com/7K-Inari/inari-helm-charts/issues/46)) ([1ebfd66](https://github.com/7K-Inari/inari-helm-charts/commit/1ebfd663c0c4efcb96377aaeead7703bd3e4479c))

## [0.2.2](https://github.com/7K-Inari/inari-helm-charts/compare/platform-config-v0.2.1...platform-config-v0.2.2) (2026-08-30)


### Bug Fixes

* **ci:** consume charts from per-repo GHCR paths and make packages public ([#42](https://github.com/7K-Inari/inari-helm-charts/issues/42)) ([b92543c](https://github.com/7K-Inari/inari-helm-charts/commit/b92543cf552a88869dbdb3de7ea17506c14397ed))

## [0.2.1](https://github.com/7K-Inari/inari-helm-charts/compare/platform-config-v0.2.0...platform-config-v0.2.1) (2026-08-28)


### Bug Fixes

* **release:** align platform-config Chart.yaml to v0.2.0 and use helm release-type ([4426bf6](https://github.com/7K-Inari/inari-helm-charts/commit/4426bf69e5a6b1f7f0bcac6984b951741cf4a07c))

## [0.2.0](https://github.com/7K-Inari/inari-helm-charts/compare/platform-config-v0.1.0...platform-config-v0.2.0) (2026-08-28)


### Features

* add platform-config chart (CNPG cluster + keycloak realm glue) with ArgoCD hooks ([0dc84ca](https://github.com/7K-Inari/inari-helm-charts/commit/0dc84ca63a12199f18fcbd627652cf7db39cd6e6))


### Bug Fixes

* **ci:** yamllint comment spacing in platform-config Chart.yaml ([bddf1cb](https://github.com/7K-Inari/inari-helm-charts/commit/bddf1cbc30135680d3fd510652bc4fa56776f6d4))
* **platform-config:** move client roles to top-level roles.client map ([8315a05](https://github.com/7K-Inari/inari-helm-charts/commit/8315a05a4f270ecb77622a4153ff9c82c6a41ea2))
