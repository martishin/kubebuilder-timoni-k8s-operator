package main

bundle: {
  apiVersion: "v1alpha1"
  name:       "operator-stack"

  instances: {
    crds: {
      module: { url: "file://../modules/tutorial-operator-crds" }
      namespace: "default"        // ignored for CRDs
      values: {}
    }

    operator: {
      module: { url: "file://../modules/tutorial-operator" }
      namespace: "tutorial-operator-system"
      values: {
        namespace: "tutorial-operator-system"
        image: "controller:dev"
        replicas: 1
        metrics: { enabled: true, port: 8443 }
        networkPolicy: { enabled: false }
        serviceMonitor: { enabled: false }
      }
    }

    sample: {
      module: { url: "file://../modules/guestbook-sample" }
      namespace: "default"
      values: {
        namespace: "default"
        name: "guestbook-sample"
        spec: { image: "nginx:stable", replicas: 2, port: 80 }
      }
    }
  }
}
