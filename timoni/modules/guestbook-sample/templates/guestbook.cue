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
