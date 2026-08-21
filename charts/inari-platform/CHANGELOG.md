# Changelog

## [0.6.0](https://github.com/7K-Inari/inari-helm-charts/compare/inari-platform-v0.5.0...inari-platform-v0.6.0) (2026-08-21)


### Features

* **chart:** support shared CNPG/Keycloak operators ([9cc3d23](https://github.com/7K-Inari/inari-helm-charts/commit/9cc3d230ccbc673c3112943178d8a69dbc5b33f6))
* external Keycloak + existing-secret support; new inari-console chart ([086c844](https://github.com/7K-Inari/inari-helm-charts/commit/086c8447af21d25020060da72d4f73ed6f08f6e9))
* external Keycloak + existing-secret support; new inari-console chart ([0a2f828](https://github.com/7K-Inari/inari-helm-charts/commit/0a2f828b32467b8a0fe426816e005badae8a5898))

## [0.5.0](https://github.com/7K-Inari/inari-helm-charts/compare/inari-platform-v0.4.0...inari-platform-v0.5.0) (2026-08-21)


### Features

* **chart:** make console OIDC redirect URIs configurable ([03ede7b](https://github.com/7K-Inari/inari-helm-charts/commit/03ede7b510069877a44d89459513416628d8b310))
* **chart:** make console OIDC redirect URIs configurable ([44a0960](https://github.com/7K-Inari/inari-helm-charts/commit/44a096052a913640ed76917f0ccf73bc8f255458))

## [0.4.0](https://github.com/7K-Inari/inari-helm-charts/compare/inari-platform-v0.3.1...inari-platform-v0.4.0) (2026-08-21)


### Features

* **inari-platform:** pin dev issuer hostname to keycloak.local:8080 ([881614d](https://github.com/7K-Inari/inari-helm-charts/commit/881614d37b274c4d0b29b216181bc803015dbb4e))
* **inari-platform:** pin keycloak/operator images to 26.3.2 with startOptimized=false ([b8cd6e4](https://github.com/7K-Inari/inari-helm-charts/commit/b8cd6e4d4b633562f5a1043221fb687403aadf90))
* **inari-platform:** provision Keycloak realm scopes, audience mapper, and 26.3.2 image pins ([4e660ad](https://github.com/7K-Inari/inari-helm-charts/commit/4e660ad4dbbdff300d6801a474e4b89c4d931862))


### Bug Fixes

* **chart:** align inari-server env with server config; enrich dev realm ([ba4cbc3](https://github.com/7K-Inari/inari-helm-charts/commit/ba4cbc32ed81f28d22e10994c7779e46c11a93ca))
* **chart:** align inari-server env with server config; enrich dev realm ([c7e85d0](https://github.com/7K-Inari/inari-helm-charts/commit/c7e85d045c4a14e7d2230476484b625bece9d76e))
* **inari-platform:** add basic scope and audience mapper to inari realm ([53dc4bf](https://github.com/7K-Inari/inari-helm-charts/commit/53dc4bff1b33f823ab6c578b4c8c9267cf7dff68))
* **inari-platform:** align inari-server db env test with INARI_DATABASE_URL ([965916a](https://github.com/7K-Inari/inari-helm-charts/commit/965916a856694798dbd04693800ef0bb5dfc631b))
* **inari-platform:** use URL-form dev hostname and quote hostname value ([d4ff1f8](https://github.com/7K-Inari/inari-helm-charts/commit/d4ff1f86c9974c2ecb8496477cf6946ec1e5b827))

## [0.3.1](https://github.com/7K-Inari/inari-helm-charts/compare/inari-platform-v0.3.0...inari-platform-v0.3.1) (2026-08-15)


### Bug Fixes

* **ci:** extra-files is package-path-relative; repair Chart.yaml to 0.3.0 ([9f524b5](https://github.com/7K-Inari/inari-helm-charts/commit/9f524b529ef1edbd8c93b5fd40cfb906704af02c))
* **ci:** extra-files path is package-relative; repair Chart.yaml 0.3.0 ([eb2f90b](https://github.com/7K-Inari/inari-helm-charts/commit/eb2f90b2f4b69fc09d986875b9d87624170456bc))

## [0.3.0](https://github.com/7K-Inari/inari-helm-charts/compare/inari-platform-v0.2.0...inari-platform-v0.3.0) (2026-08-15)


### Features

* **chart:** replace Bitnami keycloak subchart with official Keycloak operator ([2b60cba](https://github.com/7K-Inari/inari-helm-charts/commit/2b60cba3c4cd3eefac17703331197a02c3ff7f75))
* **chart:** scaffold inari-platform umbrella chart ([ed0ea44](https://github.com/7K-Inari/inari-helm-charts/commit/ed0ea448711aa7c5a373023818e75b0699ddc3d6))
* M0 day-0 bootstrap — inari-platform umbrella chart, backup/restore, DR drill, CI ([0bbe031](https://github.com/7K-Inari/inari-helm-charts/commit/0bbe0314cfb83781f937c0c026b15a06656fc620))


### Bug Fixes

* **chart:** bitnamilegacy keycloak image; openfga migrations as init container ([1352e8c](https://github.com/7K-Inari/inari-helm-charts/commit/1352e8cedc4131d886ccdfea4e887c2d14764307))
* **chart:** use defaultDefaultClientScopes in realm import ([898d6f2](https://github.com/7K-Inari/inari-helm-charts/commit/898d6f2b29460293c35e5ffca73ab1e475e71744))
* **chart:** vendor CNPG CRDs into crds/ and move subchart values to top level ([4f47b8b](https://github.com/7K-Inari/inari-helm-charts/commit/4f47b8b4ac2015b42daa6def634fe364810cd53c))
* **chart:** yamllint spacing on x-release-please-version comments ([bda31a0](https://github.com/7K-Inari/inari-helm-charts/commit/bda31a0a853a6a6f671c209e1acd4426f1939637))

## [0.2.0](https://github.com/7K-Inari/inari-helm-charts/compare/inari-platform-vv0.1.0...inari-platform-vv0.2.0) (2026-08-14)


### Features

* **chart:** replace Bitnami keycloak subchart with official Keycloak operator ([2b60cba](https://github.com/7K-Inari/inari-helm-charts/commit/2b60cba3c4cd3eefac17703331197a02c3ff7f75))
* **chart:** scaffold inari-platform umbrella chart ([ed0ea44](https://github.com/7K-Inari/inari-helm-charts/commit/ed0ea448711aa7c5a373023818e75b0699ddc3d6))
* M0 day-0 bootstrap — inari-platform umbrella chart, backup/restore, DR drill, CI ([0bbe031](https://github.com/7K-Inari/inari-helm-charts/commit/0bbe0314cfb83781f937c0c026b15a06656fc620))


### Bug Fixes

* **chart:** bitnamilegacy keycloak image; openfga migrations as init container ([1352e8c](https://github.com/7K-Inari/inari-helm-charts/commit/1352e8cedc4131d886ccdfea4e887c2d14764307))
* **chart:** use defaultDefaultClientScopes in realm import ([898d6f2](https://github.com/7K-Inari/inari-helm-charts/commit/898d6f2b29460293c35e5ffca73ab1e475e71744))
* **chart:** vendor CNPG CRDs into crds/ and move subchart values to top level ([4f47b8b](https://github.com/7K-Inari/inari-helm-charts/commit/4f47b8b4ac2015b42daa6def634fe364810cd53c))
* **chart:** yamllint spacing on x-release-please-version comments ([bda31a0](https://github.com/7K-Inari/inari-helm-charts/commit/bda31a0a853a6a6f671c209e1acd4426f1939637))
