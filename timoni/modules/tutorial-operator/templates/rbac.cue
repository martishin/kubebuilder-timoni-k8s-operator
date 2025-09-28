package templates

import rbacv1 "k8s.io/api/rbac/v1"

#ClusterRole: rbacv1.#ClusterRole & {
  #config: #Config
  apiVersion: "rbac.authorization.k8s.io/v1"
  kind:       "ClusterRole"
  metadata: name: "tutorial-operator-manager-role"
  rules: [
    { apiGroups: ["webapp.my.domain"], resources: ["guestbooks"],            verbs: ["*"] },
    { apiGroups: ["webapp.my.domain"], resources: ["guestbooks/status"],     verbs: ["get","patch","update"] },
    { apiGroups: ["webapp.my.domain"], resources: ["guestbooks/finalizers"], verbs: ["update"] },
    { apiGroups: [""],                   resources: ["services"],             verbs: ["*"] },
    { apiGroups: ["apps"],               resources: ["deployments"],          verbs: ["*"] },
  ]
}

#ClusterRoleBinding: rbacv1.#ClusterRoleBinding & {
  #config: #Config
  apiVersion: "rbac.authorization.k8s.io/v1"
  kind:       "ClusterRoleBinding"
  metadata: name: "tutorial-operator-manager-rolebinding"
  roleRef: { apiGroup: "rbac.authorization.k8s.io", kind: "ClusterRole", name: "tutorial-operator-manager-role" }
  subjects: [{ kind: "ServiceAccount", name: "controller-manager", namespace: #config.namespace }]
}
