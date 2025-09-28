package templates

import rbacv1 "k8s.io/api/rbac/v1"

#LeaderElectionRole: rbacv1.#Role & {
  #config: #Config
  apiVersion: "rbac.authorization.k8s.io/v1"
  kind:       "Role"
  metadata: {
    name:      "tutorial-operator-leader-election-role"
    namespace: #config.namespace
  }
  rules: [
    // Lease API (newer leader election)
    { apiGroups: ["coordination.k8s.io"], resources: ["leases"],
      verbs: ["get","list","watch","create","update","patch","delete"] },
    // ConfigMaps (backward compat / helpers)
    { apiGroups: [""], resources: ["configmaps"],
      verbs: ["get","list","watch","create","update","patch","delete"] },
    // Emit Events
    { apiGroups: [""], resources: ["events"], verbs: ["create","patch"] },
  ]
}

#LeaderElectionRoleBinding: rbacv1.#RoleBinding & {
  #config: #Config
  apiVersion: "rbac.authorization.k8s.io/v1"
  kind:       "RoleBinding"
  metadata: {
    name:      "tutorial-operator-leader-election-rolebinding"
    namespace: #config.namespace
  }
  roleRef: {
    apiGroup: "rbac.authorization.k8s.io"
    kind:     "Role"
    name:     "tutorial-operator-leader-election-role"
  }
  subjects: [{
    kind:      "ServiceAccount"
    name:      "controller-manager"
    namespace: #config.namespace
  }]
}
