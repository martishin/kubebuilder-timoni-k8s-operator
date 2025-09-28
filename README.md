# Kubebuilder + Timoni Kubernetes Operator

A simple Kubernetes Operator (built with Kubebuilder) that reconciles a
**Guestbook** custom resource (`webapp.my.domain/v1, Kind=Guestbook`).  
For each `Guestbook`, the controller creates and maintains a matching
`Deployment` and `Service` (image, replicas, and port come from the spec)
and reports readiness via `.status.conditions` and `.status.readyReplicas`.

The project is **packaged and deployed with Timoni**. Kubebuilder’s
kustomize manifests remain for development/CI codegen, but Timoni is
authoritative for installs and upgrades.

---

## Table of contents

- [Description](#description)
- [Prerequisites](#prerequisites)
- [Build & Release (Timoni-first)](#build--release-timoni-first)
  - [Quick start on Kind (local)](#quick-start-on-kind-local)
  - [Preview, apply, status](#preview-apply-status)
  - [Test reconciliation](#test-reconciliation)
  - [Uninstall](#uninstall)
- [Local development](#local-development)
  - [Run the controller locally](#run-the-controller-locally)
  - [Unit/Envtest & e2e](#unitenvtest--e2e)
- [Project structure](#project-structure)
- [Legacy kustomize (optional)](#legacy-kustomize-optional)
- [Contributing](#contributing)
- [License](#license)

---

## Description

**Goal of the controller**  
The controller watches `Guestbook` resources and continuously reconciles the
desired state:
- Creates/updates a `Deployment` named `<guestbook-name>-deploy` using
  `.spec.image`, `.spec.replicas`, and exposing `.spec.port`.
- Creates/updates a `Service` named `<guestbook-name>-svc` targeting the pods.
- Updates `.status.readyReplicas` and a `Ready` condition to reflect availability.

This demonstrates the **controller pattern**: a control loop compares desired
state (the CR spec) with actual cluster state and makes incremental changes until
they match.

---

## Prerequisites

- **Go** `>= 1.24`
- **Docker** `>= 17.03`
- **kubectl** `>= 1.24` (any reasonably recent version is fine)
- **Timoni** CLI (install from https://timoni.sh/)
- Access to a Kubernetes cluster (Kind, k3d, GKE, etc.). Examples below use **Kind**.

Optional for tests:
- **Kind** CLI (for e2e target)
- **make**

---

## Build & Release (Timoni-first)

All Timoni artifacts live under `timoni/`. The main bundle is:
```
timoni/bundles/operator-stack.cue
```
It includes three instances:
1. **crds** – the Guestbook CRD
2. **operator** – the controller (RBAC, SA, Deployment, metrics svc, etc.)
3. **sample** – a sample `Guestbook` resource

### Quick start on Kind (local)

If you already have a Kind cluster named `myclaster`, skip the create step.

```bash
# 1) (Optional) Create a Kind cluster
kind create cluster --name myclaster

# 2) Build the controller image
make docker-build IMG=controller:dev

# 3) Load the image into Kind
make kind-load IMG=controller:dev KIND_CLUSTER=myclaster

# 4) Point the Timoni bundle to that image (in-place edit)
make bundle-set-image IMG=controller:dev

# 5) Apply everything with Timoni
make bundle-apply
```

> Tip: You can do steps (2)–(5) in one shot with:
> ```bash
> make release-local IMG=controller:dev KIND_CLUSTER=myclaster
> ```

### Preview, apply, status

```bash
# Preview the generated manifests (no changes to the cluster)
make bundle-build | less

# Diff vs the live cluster
make bundle-diff

# Apply and wait for readiness
make bundle-apply

# Check operator’s Timoni status and Kubernetes resources
make bundle-status
kubectl -n tutorial-operator-system get deploy,pods
kubectl get crd guestbooks.webapp.my.domain
```

### Test reconciliation

Create/update the sample CR (already applied by the bundle). Check that the
controller creates the app resources and updates status.

```bash
# Verify the app Deployment+Service exist
kubectl get deploy,svc -l app.kubernetes.io/part-of=guestbook -A

# Inspect Guestbook status (expect Ready=True once replicas are available)
kubectl get guestbook guestbook-sample -o yaml | yq '.status'
```

Scale the CR and watch the Deployment change and status update:

```bash
# Scale from 2 -> 3 replicas
kubectl patch guestbook guestbook-sample --type=merge -p '{"spec":{"replicas":3}}'

# Watch rollout
kubectl -n default rollout status deploy/guestbook-sample-deploy

# Verify the controller reported readiness
kubectl get guestbook guestbook-sample -o yaml | yq '.status'
```

Optional: port-forward and browse the nginx page managed by the controller:

```bash
kubectl -n default port-forward svc/guestbook-sample-svc 8080:80
# Open http://localhost:8080
```

### Uninstall

Delete the whole stack with Timoni (CRDs, operator, sample CR):

```bash
make bundle-delete
```

If you only want to remove the sample CR (and keep the operator):

```bash
$(TIMONI) apply -n default sample --module timoni/modules/guestbook-sample --prune --delete
```

---

## Local development

### Run the controller locally

Run the controller against your current kubecontext (no image build needed).

```bash
make run
```

You can then create/update `Guestbook` resources and watch logs in your terminal.

### Unit/Envtest & e2e

```bash
# Unit/integration tests (envtest)
make test

# e2e tests (requires Kind)
make test-e2e
```

---

## Project structure

```
tutorial-operator/
├── api/v1/                      # CRD Go types (scheme, deepcopy, etc.)
├── cmd/main.go                  # Controller entrypoint
├── internal/controller/         # Reconciler implementation
├── timoni/
│   ├── bundles/operator-stack.cue
│   └── modules/
│       ├── tutorial-operator-crds/   # CRD instance
│       ├── tutorial-operator/        # Operator instance (RBAC, SA, Deployment, metrics)
│       └── guestbook-sample/         # Sample Guestbook instance
└── config/                     # Kubebuilder kustomize (kept for dev/CI, not used to deploy)
```

> **Note:** `config/` (kustomize) is not used by Timoni. If you keep it in the
repo (recommended), add a short README to `config/` stating:
“Not used for deployment; Timoni is authoritative.”

---

## Legacy kustomize (optional)

If you still want a single YAML bundle (e.g., for troubleshooting), you can render it:

```bash
make build-installer IMG=controller:dev
# outputs dist/install.yaml
kubectl apply -f dist/install.yaml
```

For production, prefer **Timoni** for installing and upgrading.

---

## Contributing

PRs welcome! Please run linters and tests locally:

```bash
make lint
make test
```

Run `make help` to see all available targets.

---

## License

Copyright 2025.

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

    http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.
