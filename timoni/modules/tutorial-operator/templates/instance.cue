// timoni/modules/tutorial-operator/templates/instance.cue
package templates

#Instance: {
  config: #Config
  let cfg = config

  objects: [
    // optional namespace first
    if cfg.createNamespace { (#Namespace & { #config: cfg }) },

    // core bits
    (#ServiceAccount     & { #config: cfg }),
    (#LeaderElectionRole         & { #config: cfg }),
    (#LeaderElectionRoleBinding  & { #config: cfg }),
    (#ClusterRole        & { #config: cfg }),
    (#ClusterRoleBinding & { #config: cfg }),
    (#Deployment         & { #config: cfg }),

    // optionals
    if cfg.metrics.enabled        { (#MetricsService       & { #config: cfg }) },
    if cfg.networkPolicy.enabled  { (#MetricsNetworkPolicy & { #config: cfg }) },
    if cfg.serviceMonitor.enabled { (#ServiceMonitor       & { #config: cfg }) },
  ]
}
