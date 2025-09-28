package templates

import (
  appsv1 "k8s.io/api/apps/v1"
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
