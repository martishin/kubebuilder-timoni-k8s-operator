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
