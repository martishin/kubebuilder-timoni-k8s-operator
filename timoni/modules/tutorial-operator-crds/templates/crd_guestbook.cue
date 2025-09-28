package templates

import (
  apiextv1 "k8s.io/apiextensions-apiserver/pkg/apis/apiextensions/v1"
)

#Instance: {
  config: _
  objects: [
    apiextv1.#CustomResourceDefinition & {
      apiVersion: "apiextensions.k8s.io/v1"
      kind:       "CustomResourceDefinition"
      metadata: name: "guestbooks.webapp.my.domain"
      spec: {
        group: "webapp.my.domain"
        scope: "Namespaced"
        names: {
          plural:   "guestbooks"
          singular: "guestbook"
          kind:     "Guestbook"
          listKind: "GuestbookList"
        }
        versions: [{
          name:    "v1"
          served:  true
          storage: true
          subresources: { status: {} }
          schema: openAPIV3Schema: {
            type: "object"
            required: ["spec"]
            properties: {
              spec: {
                type: "object"
                properties: {
                  image:    { type: "string" }
                  replicas: { type: "integer", minimum: 1 }
                  port:     { type: "integer", minimum: 1, maximum: 65535 }
                }
              }
              status: {
                type: "object"
                "x-kubernetes-preserve-unknown-fields": true
              }
            }
          }
        }]
      }
    },
  ]
}
