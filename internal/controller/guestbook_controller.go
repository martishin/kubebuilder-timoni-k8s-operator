package controller

import (
	"context"
	"fmt"

	appsv1 "k8s.io/api/apps/v1"
	corev1 "k8s.io/api/core/v1"
	apierrors "k8s.io/apimachinery/pkg/api/errors"
	apimeta "k8s.io/apimachinery/pkg/api/meta"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/apimachinery/pkg/runtime"
	"k8s.io/apimachinery/pkg/types"
	"k8s.io/apimachinery/pkg/util/intstr"
	"k8s.io/utils/ptr"
	webappv1 "my.domain/guestbook/api/v1"
	ctrl "sigs.k8s.io/controller-runtime"
	"sigs.k8s.io/controller-runtime/pkg/client"
	logf "sigs.k8s.io/controller-runtime/pkg/log"
)

const (
	appNameLabel   = "app.kubernetes.io/name"
	appPartLabel   = "app.kubernetes.io/part-of"
	managedByLabel = "app.kubernetes.io/managed-by"
	ownerPart      = "guestbook"
	managedBy      = "guestbook-operator"
	condTypeReady  = "Ready"
)

// GuestbookReconciler reconciles a Guestbook object
type GuestbookReconciler struct {
	client.Client
	Scheme *runtime.Scheme
}

// +kubebuilder:rbac:groups=webapp.my.domain,resources=guestbooks,verbs=get;list;watch;create;update;patch;delete
// +kubebuilder:rbac:groups=webapp.my.domain,resources=guestbooks/status,verbs=get;update;patch
// +kubebuilder:rbac:groups=webapp.my.domain,resources=guestbooks/finalizers,verbs=update

// Child resources we manage:
// +kubebuilder:rbac:groups="",resources=services,verbs=get;list;watch;create;update;patch;delete
// +kubebuilder:rbac:groups="apps",resources=deployments,verbs=get;list;watch;create;update;patch;delete

func (r *GuestbookReconciler) Reconcile(ctx context.Context, req ctrl.Request) (ctrl.Result, error) {
	log := logf.FromContext(ctx)

	// 1) Fetch the Guestbook
	var gb webappv1.Guestbook
	if err := r.Get(ctx, req.NamespacedName, &gb); err != nil {
		return ctrl.Result{}, client.IgnoreNotFound(err)
	}

	// defaults (also validated by CRD defaults)
	image := gb.Spec.Image
	if image == "" {
		image = "nginx:stable"
	}
	if gb.Spec.Port == 0 {
		gb.Spec.Port = 80
	}
	if gb.Spec.Replicas == 0 {
		gb.Spec.Replicas = 1
	}

	labels := map[string]string{
		appNameLabel:   gb.Name,
		appPartLabel:   ownerPart,
		managedByLabel: managedBy,
	}

	// 2) Reconcile Deployment
	depName := fmt.Sprintf("%s-deploy", gb.Name)
	var currentDep appsv1.Deployment
	err := r.Get(ctx, types.NamespacedName{Name: depName, Namespace: gb.Namespace}, &currentDep)
	desiredDep := desiredDeployment(&gb, depName, labels, image)
	if err != nil {
		if apierrors.IsNotFound(err) {
			// set owner; create
			if err := ctrl.SetControllerReference(&gb, &desiredDep, r.Scheme); err != nil {
				return ctrl.Result{}, err
			}
			if err := r.Create(ctx, &desiredDep); err != nil {
				log.Error(err, "create deployment failed")
				return ctrl.Result{}, err
			}
			log.Info("created deployment", "name", depName)
		} else {
			return ctrl.Result{}, err
		}
	} else {
		// Update if spec drift (simple fields)
		updated := false
		if *currentDep.Spec.Replicas != gb.Spec.Replicas {
			currentDep.Spec.Replicas = ptr.To(gb.Spec.Replicas)
			updated = true
		}
		// ensure container image/port align
		if len(currentDep.Spec.Template.Spec.Containers) > 0 {
			c := &currentDep.Spec.Template.Spec.Containers[0]
			if c.Image != image {
				c.Image = image
				updated = true
			}
			// keep container port consistent with spec.port
			if len(c.Ports) == 0 || c.Ports[0].ContainerPort != gb.Spec.Port {
				c.Ports = []corev1.ContainerPort{{ContainerPort: gb.Spec.Port, Name: "http"}}
				updated = true
			}
		}
		// ensure labels selector template labels
		for k, v := range labels {
			if currentDep.Spec.Template.Labels[k] != v {
				if currentDep.Spec.Template.Labels == nil {
					currentDep.Spec.Template.Labels = map[string]string{}
				}
				currentDep.Spec.Template.Labels[k] = v
				updated = true
			}
		}
		if updated {
			if err := r.Update(ctx, &currentDep); err != nil {
				return ctrl.Result{}, err
			}
			log.Info("updated deployment", "name", depName)
		}
	}

	// 3) Reconcile Service
	svcName := fmt.Sprintf("%s-svc", gb.Name)
	var currentSvc corev1.Service
	err = r.Get(ctx, types.NamespacedName{Name: svcName, Namespace: gb.Namespace}, &currentSvc)
	desiredSvc := desiredService(&gb, svcName, labels)
	if err != nil {
		if apierrors.IsNotFound(err) {
			if err := ctrl.SetControllerReference(&gb, &desiredSvc, r.Scheme); err != nil {
				return ctrl.Result{}, err
			}
			if err := r.Create(ctx, &desiredSvc); err != nil {
				return ctrl.Result{}, err
			}
			log.Info("created service", "name", svcName)
		} else {
			return ctrl.Result{}, err
		}
	} else {
		// Keep clusterIP immutable; only adjust ports/labels
		changed := false
		// port
		if len(currentSvc.Spec.Ports) == 0 ||
			currentSvc.Spec.Ports[0].Port != gb.Spec.Port ||
			currentSvc.Spec.Ports[0].TargetPort.IntVal != gb.Spec.Port {
			currentSvc.Spec.Ports = []corev1.ServicePort{{
				Name:       "http",
				Port:       gb.Spec.Port,
				Protocol:   corev1.ProtocolTCP,
				TargetPort: intstr.FromInt(int(gb.Spec.Port)),
			}}
			changed = true
		}
		// selector
		for k, v := range labels {
			if currentSvc.Spec.Selector[k] != v {
				if currentSvc.Spec.Selector == nil {
					currentSvc.Spec.Selector = map[string]string{}
				}
				currentSvc.Spec.Selector[k] = v
				changed = true
			}
		}
		if changed {
			if err := r.Update(ctx, &currentSvc); err != nil {
				return ctrl.Result{}, err
			}
			log.Info("updated service", "name", svcName)
		}
	}

	// 4) Update Status (ready replicas + Ready condition)
	// Read the latest Deployment again (it might be created above)
	var dep appsv1.Deployment
	if err := r.Get(ctx, types.NamespacedName{Name: depName, Namespace: gb.Namespace}, &dep); err == nil {
		gb.Status.ReadyReplicas = dep.Status.ReadyReplicas
		cond := metav1.Condition{
			Type:               condTypeReady,
			Status:             metav1.ConditionFalse,
			Reason:             "Progressing",
			ObservedGeneration: gb.Generation,
		}
		if dep.Status.ReadyReplicas >= gb.Spec.Replicas && gb.Spec.Replicas > 0 {
			cond.Status = metav1.ConditionTrue
			cond.Reason = "AsExpected"
			cond.Message = "All replicas are ready"
		} else {
			cond.Message = fmt.Sprintf("Ready %d/%d", dep.Status.ReadyReplicas, gb.Spec.Replicas)
		}
		apimeta.SetStatusCondition(&gb.Status.Conditions, cond)
		if err := r.Status().Update(ctx, &gb); err != nil {
			log.Error(err, "status update failed")
			// not fatal; we’ll requeue on next event
		}
	}

	return ctrl.Result{}, nil
}

func desiredDeployment(gb *webappv1.Guestbook, name string, labels map[string]string, image string) appsv1.Deployment {
	return appsv1.Deployment{
		ObjectMeta: metav1.ObjectMeta{
			Name:      name,
			Namespace: gb.Namespace,
			Labels:    labels,
		},
		Spec: appsv1.DeploymentSpec{
			Replicas: ptr.To(gb.Spec.Replicas),
			Selector: &metav1.LabelSelector{MatchLabels: labels},
			Template: corev1.PodTemplateSpec{
				ObjectMeta: metav1.ObjectMeta{Labels: labels},
				Spec: corev1.PodSpec{
					Containers: []corev1.Container{{
						Name:  "web",
						Image: image,
						Ports: []corev1.ContainerPort{{Name: "http", ContainerPort: gb.Spec.Port}},
						// keep it minimal; add resources/liveness/readiness as needed
					}},
				},
			},
		},
	}
}

func desiredService(gb *webappv1.Guestbook, name string, labels map[string]string) corev1.Service {
	return corev1.Service{
		ObjectMeta: metav1.ObjectMeta{
			Name:      name,
			Namespace: gb.Namespace,
			Labels:    labels,
		},
		Spec: corev1.ServiceSpec{
			Selector: labels,
			Ports: []corev1.ServicePort{{
				Name:       "http",
				Port:       gb.Spec.Port,
				Protocol:   corev1.ProtocolTCP,
				TargetPort: intstr.FromInt(int(gb.Spec.Port)),
			}},
		},
	}
}

// SetupWithManager sets up the controller with the Manager.
func (r *GuestbookReconciler) SetupWithManager(mgr ctrl.Manager) error {
	return ctrl.NewControllerManagedBy(mgr).
		For(&webappv1.Guestbook{}).
		Owns(&appsv1.Deployment{}).
		Owns(&corev1.Service{}).
		Named("guestbook").
		Complete(r)
}
