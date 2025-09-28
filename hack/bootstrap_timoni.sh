#!/usr/bin/env bash
set -euo pipefail

need() { command -v "$1" >/dev/null 2>&1 || { echo "Missing $1. Install it first."; exit 1; }; }
need timoni

# Paths (relative to repo root)
CRDS_DIR="timoni/modules/tutorial-operator-crds"
OP_DIR="timoni/modules/tutorial-operator"
SAMPLE_DIR="timoni/modules/guestbook-sample"
BUNDLE_DIR="timoni/bundles"

echo "==> Creating bundle directory"
mkdir -p "$BUNDLE_DIR"

echo "==> Initializing Timoni modules"

# --- CRDs module ---
timoni mod init "$CRDS_DIR"
pushd "$CRDS_DIR" >/dev/null
timoni mod vendor k8s
popd >/dev/null

# --- Operator module ---
timoni mod init "$OP_DIR"
pushd "$OP_DIR" >/dev/null
timoni mod vendor k8s
popd >/dev/null

# --- Sample module ---
timoni mod init "$SAMPLE_DIR"
pushd "$SAMPLE_DIR" >/dev/null
timoni mod vendor k8s
popd >/dev/null

echo "==> Writing module: tutorial-operator-crds"
mkdir -p "$CRDS_DIR/templates"
cat > "$CRDS_DIR/values.cue" <<'EOF'
package main
values: {}
EOF

cat > "$CRDS_DIR/timoni.cue" <<'EOF'
package main

import (
  templates "templates"
)

values: {}

timoni: {
  apiVersion: "v1alpha1"
  instance: templates.#Instance & {
    config: {
      metadata: {
        name:      string @tag(name)
        namespace: string @tag(namespace)
      }
    }
  }
  apply: app: [ for obj in instance.objects { obj } ]
}
EOF

cat > "$CRDS_DIR/templates/crd_guestbook.cue" <<'EOF'
package templates

import (
  apiextv1 "k8s.io/apiextensions-apiserver/pkg/apis/apiextensions/v1"
)

#Instance: {
  config: _
  objects: [
    apiextv1.#CustomResourceDefinition & {
      apiVersion: "apiextensions.k8s.io/v1"
      kind:       "CustomResourceDefinition"
      metadata: name: "guestbooks.webapp.my.domain"
      spec: {
        group: "webapp.my.domain"
        scope: "Namespaced"
        names: {
          plural:   "guestbooks"
          singular: "guestbook"
          kind:     "Guestbook"
          listKind: "GuestbookList"
        }
        versions: [{
          name:    "v1"
          served:  true
          storage: true
          subresources: { status: {} }
          schema: openAPIV3Schema: {
            type: "object"
            required: ["spec"]
            properties: {
              spec: {
                type: "object"
                properties: {
                  image:    { type: "string" }
                  replicas: { type: "integer", minimum: 1 }
                  port:     { type: "integer", minimum: 1, maximum: 65535 }
                }
              }
              status: {
                type: "object"
                x-kubernetes-preserve-unknown-fields: true
              }
            }
          }
        }]
      }
    },
  ]
}
EOF

echo "==> Writing module: tutorial-operator"
mkdir -p "$OP_DIR/templates"
cat > "$OP_DIR/values.cue" <<'EOF'
package main

values: {
  namespace:       *"tutorial-operator-system" | string
  createNamespace: *true | bool

  image:           *"controller:v0.1.0" | string
  replicas:        *1 | int & >0

  metrics: {
    enabled: *true | bool
    port:    *8443 | int & >0 & <=65535
    serviceName: *"controller-manager-metrics-service" | string
  }

  networkPolicy: {
    enabled: *false | bool
  }

  serviceMonitor: {
    enabled: *false | bool
    namespace: *"system" | string
  }
}
EOF

cat > "$OP_DIR/timoni.cue" <<'EOF'
package main

import (
  templates "templates"
)

values: templates.#Config

timoni: {
  apiVersion: "v1alpha1"
  instance: templates.#Instance & {
    config: values
    config: metadata: {
      name:      string @tag(name)
      namespace: string @tag(namespace)
    }
  }
  apply: app: [ for obj in instance.objects { obj } ]
}
EOF

cat > "$OP_DIR/templates/namespace.cue" <<'EOF'
package templates

import corev1 "k8s.io/api/core/v1"

#Config: {
  metadata: {
    name:      string
    namespace: string
  }
  namespace:       string
  createNamespace: bool
  image:           string
  replicas:        int
  metrics: { enabled: bool, port: int, serviceName: string }
  networkPolicy: { enabled: bool }
  serviceMonitor: { enabled: bool, namespace: string }
}

#Namespace: corev1.#Namespace & {
  #config: _
  apiVersion: "v1"
  kind:       "Namespace"
  metadata: name: #config.namespace
}
EOF

cat > "$OP_DIR/templates/serviceaccount.cue" <<'EOF'
package templates

import corev1 "k8s.io/api/core/v1"

#ServiceAccount: corev1.#ServiceAccount & {
  #config:    #Config
  apiVersion: "v1"
  kind:       "ServiceAccount"
  metadata: {
    name:      "controller-manager"
    namespace: #config.namespace
    labels: {
      "control-plane": "controller-manager"
      "app.kubernetes.io/name": #config.metadata.name
    }
  }
}
EOF

cat > "$OP_DIR/templates/rbac.cue" <<'EOF'
package templates

import rbacv1 "k8s.io/api/rbac/v1"

#ClusterRole: rbacv1.#ClusterRole & {
  #config: #Config
  apiVersion: "rbac.authorization.k8s.io/v1"
  kind:       "ClusterRole"
  metadata: name: "tutorial-operator-manager-role"
  rules: [
    { apiGroups: ["webapp.my.domain"], resources: ["guestbooks"],            verbs: ["*"] },
    { apiGroups: ["webapp.my.domain"], resources: ["guestbooks/status"],     verbs: ["get","patch","update"] },
    { apiGroups: ["webapp.my.domain"], resources: ["guestbooks/finalizers"], verbs: ["update"] },
    { apiGroups: [""],                   resources: ["services"],             verbs: ["*"] },
    { apiGroups: ["apps"],               resources: ["deployments"],          verbs: ["*"] },
  ]
}

#ClusterRoleBinding: rbacv1.#ClusterRoleBinding & {
  #config: #Config
  apiVersion: "rbac.authorization.k8s.io/v1"
  kind:       "ClusterRoleBinding"
  metadata: name: "tutorial-operator-manager-rolebinding"
  roleRef: { apiGroup: "rbac.authorization.k8s.io", kind: "ClusterRole", name: "tutorial-operator-manager-role" }
  subjects: [{ kind: "ServiceAccount", name: "controller-manager", namespace: #config.namespace }]
}
EOF

cat > "$OP_DIR/templates/deployment.cue" <<'EOF'
package templates

import (
  appsv1 "k8s.io/api/apps/v1"
  corev1 "k8s.io/api/core/v1"
)

#Deployment: appsv1.#Deployment & {
  #config: #Config
  apiVersion: "apps/v1"
  kind:       "Deployment"
  metadata: {
    name:      "controller-manager"
    namespace: #config.namespace
    labels: { "control-plane": "controller-manager" }
  }
  spec: {
    replicas: #config.replicas
    selector: matchLabels: { "control-plane": "controller-manager" }
    template: {
      metadata: {
        labels: { "control-plane": "controller-manager" }
        annotations: { "kubectl.kubernetes.io/default-container": "manager" }
      }
      spec: {
        serviceAccountName: "controller-manager"
        securityContext: runAsNonRoot: true
        containers: [{
          name:  "manager"
          image: #config.image
          args:  [
            "--leader-elect",
            "--health-probe-bind-address=:8081",
            if #config.metrics.enabled { "--metrics-bind-address=:\(#config.metrics.port)" },
          ]
          readinessProbe: httpGet: { path: "/readyz",  port: 8081 }
          livenessProbe:  httpGet: { path: "/healthz", port: 8081 }
          securityContext: {
            readOnlyRootFilesystem: true
            allowPrivilegeEscalation: false
            capabilities: drop: ["ALL"]
          }
          resources: {
            requests: { cpu: "10m", memory: "64Mi" }
            limits:   { cpu: "500m", memory: "128Mi" }
          }
        }]
        terminationGracePeriodSeconds: 10
      }
    }
  }
}
EOF

cat > "$OP_DIR/templates/metrics_service.cue" <<'EOF'
package templates

import corev1 "k8s.io/api/core/v1"

#MetricsService: corev1.#Service & {
  #config: #Config
  apiVersion: "v1"
  kind:       "Service"
  metadata: {
    name:      #config.metrics.serviceName
    namespace: #config.namespace
    labels: { "control-plane": "controller-manager" }
  }
  spec: {
    selector: { "control-plane": "controller-manager" }
    ports: [{
      name: "https"
      port: #config.metrics.port
      protocol: "TCP"
      targetPort: #config.metrics.port
    }]
  }
}
EOF

cat > "$OP_DIR/templates/networkpolicy.cue" <<'EOF'
package templates

import netv1 "k8s.io/api/networking/v1"

#MetricsNetworkPolicy: netv1.#NetworkPolicy & {
  #config: #Config
  apiVersion: "networking.k8s.io/v1"
  kind:       "NetworkPolicy"
  metadata: {
    name:      "allow-metrics-traffic"
    namespace: #config.namespace
  }
  spec: {
    podSelector: matchLabels: { "control-plane": "controller-manager" }
    policyTypes: ["Ingress"]
    ingress: [{
      from: [{ namespaceSelector: matchLabels: { "metrics": "enabled" } }]
      ports: [{ port: #config.metrics.port, protocol: "TCP" }]
    }]
  }
}
EOF

cat > "$OP_DIR/templates/servicemonitor.cue" <<'EOF'
package templates

#ServiceMonitor: {
  #config: #Config
  apiVersion: "monitoring.coreos.com/v1"
  kind:       "ServiceMonitor"
  metadata: {
    name:      "controller-manager-metrics-monitor"
    namespace: #config.namespace
    labels: { "control-plane": "controller-manager" }
  }
  spec: {
    selector: matchLabels: { "control-plane": "controller-manager" }
    endpoints: [{
      path: "/metrics"
      port: "https"
      scheme: "https"
      tlsConfig: { insecureSkipVerify: true }
      bearerTokenFile: "/var/run/secrets/kubernetes.io/serviceaccount/token"
    }]
  }
}
EOF

cat > "$OP_DIR/templates/instance.cue" <<'EOF'
package templates

#Instance: {
  config: #Config
  #config: config

  objects: [
    if config.createNamespace then (#Namespace & { #config: config }) else _|_,
    #ServiceAccount      & { #config: config },
    #ClusterRole         & { #config: config },
    #ClusterRoleBinding  & { #config: config },
    #Deployment          & { #config: config },
    if config.metrics.enabled        then (#MetricsService & { #config: config }) else _|_,
    if config.networkPolicy.enabled  then (#MetricsNetworkPolicy & { #config: config }) else _|_,
    if config.serviceMonitor.enabled then (#ServiceMonitor & { #config: config }) else _|_,
  ]
}
EOF

echo "==> Writing module: guestbook-sample"
mkdir -p "$SAMPLE_DIR/templates"
cat > "$SAMPLE_DIR/values.cue" <<'EOF'
package main

values: {
  namespace: *"default" | string
  name:      *"guestbook-sample" | string
  spec: {
    image:    *"nginx:stable" | string
    replicas: *2 | int & >0
    port:     *80 | int & >0 & <=65535
  }
}
EOF

cat > "$SAMPLE_DIR/timoni.cue" <<'EOF'
package main

import templates "templates"

values: templates.#Config

timoni: {
  apiVersion: "v1alpha1"
  instance: templates.#Instance & {
    config: values
    config: metadata: {
      name:      string @tag(name)
      namespace: string @tag(namespace)
    }
  }
  apply: app: [ for obj in instance.objects { obj } ]
}
EOF

cat > "$SAMPLE_DIR/templates/guestbook.cue" <<'EOF'
package templates

#Config: {
  metadata: { name: string, namespace: string }
  namespace: string
  name:      string
  spec: { image: string, replicas: int, port: int }
}

#Instance: {
  config: #Config
  objects: [
    {
      apiVersion: "webapp.my.domain/v1"
      kind:       "Guestbook"
      metadata: {
        name:      config.name
        namespace: config.namespace
      }
      spec: config.spec
    },
  ]
}
EOF

echo "==> Writing bundle: operator-stack.cue"
cat > "$BUNDLE_DIR/operator-stack.cue" <<'EOF'
package main

bundle: {
  apiVersion: "v1alpha1"

  instances: {
    crds: {
      module: "./../modules/tutorial-operator-crds"
      namespace: "_"    // ignored for CRDs
      name: "tutorial-operator-crds"
      values: {}
    }
    operator: {
      module: "./../modules/tutorial-operator"
      namespace: "tutorial-operator-system"
      name: "tutorial-operator"
      values: {
        namespace: "tutorial-operator-system"
        image: "controller:v0.1.0"
        replicas: 1
        metrics: { enabled: true, port: 8443 }
        networkPolicy: { enabled: false }
        serviceMonitor: { enabled: false }
      }
    }
    sample: {
      module: "./../modules/guestbook-sample"
      namespace: "default"
      name: "guestbook-sample"
      values: {
        namespace: "default"
        name: "guestbook-sample"
        spec: { image: "nginx:stable", replicas: 2, port: 80 }
      }
    }
  }
}
EOF

echo "==> Done. Next steps:"
echo "1) (Optional) Build & load your operator image into Kind:"
echo "   docker build -t controller:v0.1.0 . && kind load docker-image controller:v0.1.0 --name myclaster"
echo "2) Preview everything:"
echo "   timoni bundle build -f timoni/bundles/operator-stack.cue | less"
echo "3) Apply:"
echo "   timoni bundle apply -f timoni/bundles/operator-stack.cue --wait"
echo "4) Check:"
echo "   timoni -n tutorial-operator-system status tutorial-operator"
echo "   kubectl -n tutorial-operator-system get deploy,pods"
echo "   kubectl get guestbook guestbook-sample -o yaml | yq '.status'"
