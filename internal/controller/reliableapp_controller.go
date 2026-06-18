/*
Copyright 2026.
Licensed under the Apache License, Version 2.0
*/

package controller

import (
	"context"

	appsv1 "k8s.io/api/apps/v1"
	corev1 "k8s.io/api/core/v1"
	apierrors "k8s.io/apimachinery/pkg/api/errors"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/apimachinery/pkg/runtime"
	"k8s.io/apimachinery/pkg/types"
	ctrl "sigs.k8s.io/controller-runtime"
	"sigs.k8s.io/controller-runtime/pkg/client"
	"sigs.k8s.io/controller-runtime/pkg/controller/controllerutil"
	logf "sigs.k8s.io/controller-runtime/pkg/log"

	ebaytrainingv1 "github.com/rotimiayodeji11/reliableapp-operator/api/v1"
)

// ReliableAppReconciler reconciles a ReliableApp object
type ReliableAppReconciler struct {
	client.Client
	Scheme *runtime.Scheme
}

// +kubebuilder:rbac:groups=ebay.training,resources=reliableapps,verbs=get;list;watch;create;update;patch;delete
// +kubebuilder:rbac:groups=ebay.training,resources=reliableapps/status,verbs=get;update;patch
// +kubebuilder:rbac:groups=ebay.training,resources=reliableapps/finalizers,verbs=update
// +kubebuilder:rbac:groups=apps,resources=deployments,verbs=get;list;watch;create;update;patch;delete

// Reconcile creates or updates a Deployment for each ReliableApp
func (r *ReliableAppReconciler) Reconcile(ctx context.Context, req ctrl.Request) (ctrl.Result, error) {
	log := logf.FromContext(ctx)

	// STEP 1: Fetch the ReliableApp from cache
	var app ebaytrainingv1.ReliableApp
	if err := r.Get(ctx, req.NamespacedName, &app); err != nil {
		if apierrors.IsNotFound(err) {
			return ctrl.Result{}, nil
		}
		return ctrl.Result{}, err
	}

	log.Info("Reconciling ReliableApp", "name", app.Name, "replicas", app.Spec.Replicas)

	// STEP 2: Declare desired Deployment shell
	deployment := &appsv1.Deployment{
		ObjectMeta: metav1.ObjectMeta{
			Name:      app.Name,
			Namespace: app.Namespace,
		},
	}

	// STEP 3: Idempotent create-or-update
	_, err := controllerutil.CreateOrUpdate(ctx, r.Client, deployment, func() error {
		if err := controllerutil.SetControllerReference(&app, deployment, r.Scheme); err != nil {
			return err
		}

		replicas := app.Spec.Replicas
		deployment.Spec.Replicas = &replicas
		deployment.Spec.Selector = &metav1.LabelSelector{
			MatchLabels: map[string]string{"app": app.Name},
		}
		deployment.Spec.Template = corev1.PodTemplateSpec{
			ObjectMeta: metav1.ObjectMeta{
				Labels: map[string]string{"app": app.Name},
			},
			Spec: corev1.PodSpec{
				Containers: []corev1.Container{
					{
						Name:  "main",
						Image: app.Spec.Image,
					},
				},
			},
		}
		return nil
	})

	if err != nil {
		log.Error(err, "Failed to create or update Deployment")
		return ctrl.Result{}, err
	}

	// STEP 4: Status subresource update
	var current appsv1.Deployment
	if err := r.Get(ctx, types.NamespacedName{Name: app.Name, Namespace: app.Namespace}, &current); err == nil {
		app.Status.ReadyReplicas = current.Status.ReadyReplicas
		if current.Status.ReadyReplicas == app.Spec.Replicas {
			app.Status.Phase = "Ready"
		} else {
			app.Status.Phase = "Progressing"
		}
		if err := r.Status().Update(ctx, &app); err != nil {
			log.Error(err, "Failed to update status")
			return ctrl.Result{}, err
		}
	}

	return ctrl.Result{}, nil
}

// SetupWithManager wires the controller to watch ReliableApps and owned Deployments
func (r *ReliableAppReconciler) SetupWithManager(mgr ctrl.Manager) error {
	return ctrl.NewControllerManagedBy(mgr).
		For(&ebaytrainingv1.ReliableApp{}).
		Owns(&appsv1.Deployment{}).
		Named("reliableapp").
		Complete(r)
}
