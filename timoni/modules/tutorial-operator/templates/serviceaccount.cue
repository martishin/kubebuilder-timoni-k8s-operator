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
