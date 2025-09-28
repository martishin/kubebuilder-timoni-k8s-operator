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
