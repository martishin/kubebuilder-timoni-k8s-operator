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
