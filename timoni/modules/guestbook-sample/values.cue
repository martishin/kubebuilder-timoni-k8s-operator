package main

values: {
  namespace: *"default" | string
  name:      *"guestbook-sample" | string
  spec: {
    image:    *"nginx:stable" | string
    replicas: *2 | int & >0
    port:     *80 | int & >0 & <=65535
  }
}
