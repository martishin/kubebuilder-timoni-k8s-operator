# -----------------------------------------
# Project variables
# -----------------------------------------

# Image URL for the controller manager
IMG ?= controller:latest

# Timoni bundle file
BUNDLE ?= timoni/bundles/operator-stack.cue

# Kind settings (for local testing)
KIND ?= kind
KIND_CLUSTER ?= myclaster

# Tools (overridable)
TIMONI ?= timoni
KUBECTL ?= kubectl
KIND_BIN ?= $(KIND)

# Get the currently used golang install path (in GOPATH/bin, unless GOBIN is set)
ifeq (,$(shell go env GOBIN))
GOBIN=$(shell go env GOPATH)/bin
else
GOBIN=$(shell go env GOBIN)
endif

# Container runtime (docker|podman)
CONTAINER_TOOL ?= docker

# Setting SHELL to bash allows bash commands to be executed by recipes.
SHELL = /usr/bin/env bash -o pipefail
.SHELLFLAGS = -ec

# -----------------------------------------
# Help
# -----------------------------------------

.PHONY: help
help: ## Show this help
	@awk 'BEGIN {FS = ":.*##"; printf "\nUsage:\n  make \033[36m<target>\033[0m\n"} \
	/^[a-zA-Z_0-9-]+:.*?##/ { printf "  \033[36m%-22s\033[0m %s\n", $$1, $$2 } \
	/^##@/ { printf "\n\033[1m%s\033[0m\n", substr($$0, 5) } ' $(MAKEFILE_LIST)

# -----------------------------------------
##@ Development (Kubebuilder workflow)
# -----------------------------------------

.PHONY: manifests
manifests: controller-gen ## Generate CRDs/RBAC/Webhooks from markers
	$(CONTROLLER_GEN) rbac:roleName=manager-role crd webhook paths="./..." output:crd:artifacts:config=config/crd/bases

.PHONY: generate
generate: controller-gen ## Generate deepcopy methods
	$(CONTROLLER_GEN) object:headerFile="hack/boilerplate.go.txt" paths="./..."

.PHONY: fmt
fmt: ## go fmt
	go fmt ./...

.PHONY: vet
vet: ## go vet
	go vet ./...

.PHONY: test
test: manifests generate fmt vet setup-envtest ## Run unit/integration tests (envtest)
	KUBEBUILDER_ASSETS="$(shell $(ENVTEST) use $(ENVTEST_K8S_VERSION) --bin-dir $(LOCALBIN) -p path)" \
		go test $$(go list ./... | grep -v /e2e) -coverprofile cover.out

# Kind-based e2e (optional)
KIND_E2E_CLUSTER ?= tutorial-operator-test-e2e

.PHONY: setup-test-e2e
setup-test-e2e: ## Create Kind cluster for e2e if missing
	@command -v $(KIND_BIN) >/dev/null 2>&1 || { echo "Kind is not installed."; exit 1; }
	@case "$$($(KIND_BIN) get clusters)" in \
		*"$(KIND_E2E_CLUSTER)"*) echo "Kind cluster '$(KIND_E2E_CLUSTER)' exists";; \
		*) echo "Creating Kind cluster '$(KIND_E2E_CLUSTER)'..."; $(KIND_BIN) create cluster --name $(KIND_E2E_CLUSTER);; \
	esac

.PHONY: test-e2e
test-e2e: setup-test-e2e manifests generate fmt vet ## Run e2e tests (expects Kind)
	KIND=$(KIND_BIN) KIND_CLUSTER=$(KIND_E2E_CLUSTER) go test -tags=e2e ./test/e2e/ -v -ginkgo.v
	$(MAKE) cleanup-test-e2e

.PHONY: cleanup-test-e2e
cleanup-test-e2e: ## Delete Kind cluster used for e2e
	@$(KIND_BIN) delete cluster --name $(KIND_E2E_CLUSTER)

.PHONY: lint
lint: golangci-lint ## Run golangci-lint
	$(GOLANGCI_LINT) run

.PHONY: lint-fix
lint-fix: golangci-lint ## Run golangci-lint with --fix
	$(GOLANGCI_LINT) run --fix

.PHONY: lint-config
lint-config: golangci-lint ## Verify golangci-lint config
	$(GOLANGCI_LINT) config verify

# -----------------------------------------
##@ Build
# -----------------------------------------

.PHONY: build
build: manifests generate fmt vet ## Build manager binary
	go build -o bin/manager cmd/main.go

.PHONY: run
run: manifests generate fmt vet ## Run controller locally against current kubecontext
	go run ./cmd/main.go

.PHONY: docker-build
docker-build: ## Build controller image
	$(CONTAINER_TOOL) build -t $(IMG) .

.PHONY: docker-push
docker-push: ## Push controller image
	$(CONTAINER_TOOL) push $(IMG)

PLATFORMS ?= linux/arm64,linux/amd64,linux/s390x,linux/ppc64le
.PHONY: docker-buildx
docker-buildx: ## Cross-build & push controller image
	sed -e '1 s/\(^FROM\)/FROM --platform=\$$\{BUILDPLATFORM\}/; t' -e ' 1,// s//FROM --platform=\$$\{BUILDPLATFORM\}/' Dockerfile > Dockerfile.cross
	- $(CONTAINER_TOOL) buildx create --name tutorial-operator-builder
	$(CONTAINER_TOOL) buildx use tutorial-operator-builder
	- $(CONTAINER_TOOL) buildx build --push --platform=$(PLATFORMS) --tag $(IMG) -f Dockerfile.cross .
	- $(CONTAINER_TOOL) buildx rm tutorial-operator-builder
	rm Dockerfile.cross

# Legacy installer (not used by Timoni deploys; kept for convenience)
.PHONY: build-installer
build-installer: manifests generate kustomize ## Render legacy Kustomize installer to dist/install.yaml
	mkdir -p dist
	cd config/manager && $(KUSTOMIZE) edit set image controller=$(IMG)
	$(KUSTOMIZE) build config/default > dist/install.yaml

# -----------------------------------------
##@ Timoni (deployment of CRDs + operator + sample)
# -----------------------------------------

.PHONY: bundle-build
bundle-build: ## Render the bundle (dry-run)
	$(TIMONI) bundle build -f $(BUNDLE)

.PHONY: bundle-diff
bundle-diff: ## Show diff vs cluster
	$(TIMONI) bundle diff -f $(BUNDLE) || true

.PHONY: bundle-apply
bundle-apply: ## Apply bundle to cluster and wait for readiness
	$(TIMONI) bundle apply -f $(BUNDLE) --wait

.PHONY: bundle-delete
bundle-delete: ## Delete bundle from cluster
	$(TIMONI) bundle delete -f $(BUNDLE) --wait || true

.PHONY: bundle-status
bundle-status: ## Show operator instance status
	$(TIMONI) -n tutorial-operator-system status operator || true

.PHONY: kind-load
kind-load: ## Load controller image into local Kind cluster
	$(KIND_BIN) load docker-image $(IMG) --name $(KIND_CLUSTER)

# Update the operator image inside the CUE bundle (edits the operator instance values.image only)
.PHONY: bundle-set-image
bundle-set-image: ## Set operator image in the bundle to IMG (edits $(BUNDLE))
	@awk -v IMG="$(IMG)" ' \
	  BEGIN{in_op=0; in_vals=0} \
	  /operator:[[:space:]]*{/ {in_op=1} \
	  in_op && /values:[[:space:]]*{/ {in_vals=1} \
	  in_op && in_vals && /^[[:space:]]*image:[[:space:]]*"/ { sub(/image:.*/, "image: \"" IMG "\""); } \
	  in_op && in_vals && /^[[:space:]]*}/ {in_vals=0} \
	  in_op && /^[[:space:]]*}/ {in_op=0} \
	  {print} ' $(BUNDLE) > $(BUNDLE).tmp && mv $(BUNDLE).tmp $(BUNDLE)

# One-liner: build -> load -> point bundle to image -> apply
.PHONY: release-local
release-local: docker-build kind-load bundle-set-image bundle-apply ## Build, load to Kind, bump image in bundle, apply
	@echo "✅ Released $(IMG) via Timoni"

# Optional: push Timoni modules to OCI (requires an OCI repo, e.g., ghcr.io/you/tutorial-operator)
VERSION ?= v0.1.0
OCI_REPO ?= oci://ghcr.io/you/tutorial-operator

.PHONY: push-modules
push-modules: ## Push modules to OCI (optional)
	$(TIMONI) mod push timoni/modules/tutorial-operator-crds $(OCI_REPO)-crds:$(VERSION)
	$(TIMONI) mod push timoni/modules/tutorial-operator      $(OCI_REPO):$(VERSION)
	@echo "✅ Pushed modules to $(OCI_REPO) (tag: $(VERSION))"

# Maintain deploy/undeploy aliases for muscle memory
.PHONY: deploy
deploy: bundle-apply ## Apply Timoni bundle

.PHONY: undeploy
undeploy: bundle-delete ## Delete Timoni bundle

# -----------------------------------------
##@ Dependencies
# -----------------------------------------

LOCALBIN ?= $(shell pwd)/bin
$(LOCALBIN):
	mkdir -p $(LOCALBIN)

KUSTOMIZE ?= $(LOCALBIN)/kustomize
CONTROLLER_GEN ?= $(LOCALBIN)/controller-gen
ENVTEST ?= $(LOCALBIN)/setup-envtest
GOLANGCI_LINT = $(LOCALBIN)/golangci-lint

KUSTOMIZE_VERSION ?= v5.6.0
CONTROLLER_TOOLS_VERSION ?= v0.18.0
ENVTEST_VERSION ?= $(shell go list -m -f "{{ .Version }}" sigs.k8s.io/controller-runtime | awk -F'[v.]' '{printf "release-%d.%d", $$2, $$3}')
ENVTEST_K8S_VERSION ?= $(shell go list -m -f "{{ .Version }}" k8s.io/api | awk -F'[v.]' '{printf "1.%d", $$3}')
GOLANGCI_LINT_VERSION ?= v2.3.0

.PHONY: kustomize
kustomize: $(KUSTOMIZE) ## Install kustomize locally
$(KUSTOMIZE): $(LOCALBIN)
	$(call go-install-tool,$(KUSTOMIZE),sigs.k8s.io/kustomize/kustomize/v5,$(KUSTOMIZE_VERSION))

.PHONY: controller-gen
controller-gen: $(CONTROLLER_GEN) ## Install controller-gen locally
$(CONTROLLER_GEN): $(LOCALBIN)
	$(call go-install-tool,$(CONTROLLER_GEN),sigs.k8s.io/controller-tools/cmd/controller-gen,$(CONTROLLER_TOOLS_VERSION))

.PHONY: setup-envtest
setup-envtest: envtest ## Download envtest binaries to $(LOCALBIN)
	@echo "Setting up envtest binaries for Kubernetes $(ENVTEST_K8S_VERSION)..."
	@$(ENVTEST) use $(ENVTEST_K8S_VERSION) --bin-dir $(LOCALBIN) -p path || { \
		echo "Failed to set up envtest binaries for $(ENVTEST_K8S_VERSION)."; exit 1; }

.PHONY: envtest
envtest: $(ENVTEST) ## Install setup-envtest locally
$(ENVTEST): $(LOCALBIN)
	$(call go-install-tool,$(ENVTEST),sigs.k8s.io/controller-runtime/tools/setup-envtest,$(ENVTEST_VERSION))

.PHONY: golangci-lint
golangci-lint: $(GOLANGCI_LINT) ## Install golangci-lint locally
$(GOLANGCI_LINT): $(LOCALBIN)
	$(call go-install-tool,$(GOLANGCI_LINT),github.com/golangci/golangci-lint/v2/cmd/golangci-lint,$(GOLANGCI_LINT_VERSION))

# go-install-tool will 'go install' a package into LOCALBIN with a versioned symlink
# $1 - target path with name of binary
# $2 - package url which can be installed
# $3 - specific version of package
define go-install-tool
@[ -f "$(1)-$(3)" ] && [ "$$(readlink -- "$(1)" 2>/dev/null)" = "$(1)-$(3)" ] || { \
	set -e; \
	package=$(2)@$(3) ;\
	echo "Downloading $${package}" ;\
	rm -f $(1) ;\
	GOBIN=$(LOCALBIN) go install $${package} ;\
	mv $(1) $(1)-$(3) ;\
} ;\
ln -sf $$(realpath $(1)-$(3)) $(1)
endef
