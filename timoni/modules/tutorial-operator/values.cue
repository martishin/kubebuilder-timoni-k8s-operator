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
