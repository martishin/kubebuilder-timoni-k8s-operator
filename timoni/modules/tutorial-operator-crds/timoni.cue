package main

import templates "timoni.sh/timoni/modules/tutorial-operator-crds/templates"

values: {}

timoni: {
  apiVersion: "v1alpha1"
  instance: templates.#Instance & {
    config: {
      metadata: {
        name:      string @tag(name)
        namespace: string @tag(namespace)
      }
    }
  }
  apply: app: [ for obj in instance.objects { obj } ]
}
