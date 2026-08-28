/*
Copyright 2026.

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

    http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.
*/

package controller

import (
	"context"

	. "github.com/onsi/ginkgo/v2"
	. "github.com/onsi/gomega"
	appsv1 "k8s.io/api/apps/v1"
	"k8s.io/apimachinery/pkg/api/errors"
	"k8s.io/apimachinery/pkg/types"
	"sigs.k8s.io/controller-runtime/pkg/reconcile"

	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"

	ebaytrainingv1 "github.com/rotimiayodeji11/reliableapp-operator/api/v1"
)

var _ = Describe("ReliableApp Controller", func() {
	Context("When reconciling a resource", func() {
		const (
			resourceName      = "test-resource"
			resourceNamespace = "default"
			resourceImage     = "nginx:1.27"
			resourceReplicas  = int32(2)
		)

		ctx := context.Background()

		typeNamespacedName := types.NamespacedName{
			Name:      resourceName,
			Namespace: resourceNamespace,
		}
		var reliableapp *ebaytrainingv1.ReliableApp

		BeforeEach(func() {
			By("Creating a valid ReliableApp")
			reliableapp = &ebaytrainingv1.ReliableApp{
				ObjectMeta: metav1.ObjectMeta{
					Name:      resourceName,
					Namespace: resourceNamespace,
				},
				Spec: ebaytrainingv1.ReliableAppSpec{
					Image:    resourceImage,
					Replicas: resourceReplicas,
				},
			}
			Expect(k8sClient.Create(ctx, reliableapp)).To(Succeed())
		})

		AfterEach(func() {
			By("Cleaning up resources created by the test")
			deployment := &appsv1.Deployment{
				ObjectMeta: metav1.ObjectMeta{Name: resourceName, Namespace: resourceNamespace},
			}
			if err := k8sClient.Delete(ctx, deployment); err != nil {
				Expect(errors.IsNotFound(err)).To(BeTrue(), "unexpected Deployment cleanup error: %v", err)
			}

			resource := &ebaytrainingv1.ReliableApp{
				ObjectMeta: metav1.ObjectMeta{Name: resourceName, Namespace: resourceNamespace},
			}
			if err := k8sClient.Delete(ctx, resource); err != nil {
				Expect(errors.IsNotFound(err)).To(BeTrue(), "unexpected ReliableApp cleanup error: %v", err)
			}
		})

		It("creates the desired Deployment and reports progress", func() {
			By("Reconciling the ReliableApp")
			controllerReconciler := &ReliableAppReconciler{
				Client: k8sClient,
				Scheme: k8sClient.Scheme(),
			}

			_, err := controllerReconciler.Reconcile(ctx, reconcile.Request{
				NamespacedName: typeNamespacedName,
			})
			Expect(err).NotTo(HaveOccurred())

			By("Verifying the desired Deployment")
			deployment := &appsv1.Deployment{}
			Expect(k8sClient.Get(ctx, typeNamespacedName, deployment)).To(Succeed())
			Expect(deployment.Spec.Replicas).NotTo(BeNil())
			Expect(*deployment.Spec.Replicas).To(Equal(resourceReplicas))
			Expect(deployment.Spec.Template.Spec.Containers).To(HaveLen(1))
			Expect(deployment.Spec.Template.Spec.Containers[0].Image).To(Equal(resourceImage))
			Expect(metav1.IsControlledBy(deployment, reliableapp)).To(BeTrue())

			By("Verifying status for a Deployment with no ready replicas")
			updatedApp := &ebaytrainingv1.ReliableApp{}
			Expect(k8sClient.Get(ctx, typeNamespacedName, updatedApp)).To(Succeed())
			Expect(updatedApp.Status.ReadyReplicas).To(BeZero())
			Expect(updatedApp.Status.Phase).To(Equal("Progressing"))
		})
	})
})
