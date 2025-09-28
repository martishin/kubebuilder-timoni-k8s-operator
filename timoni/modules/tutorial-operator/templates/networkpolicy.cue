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
