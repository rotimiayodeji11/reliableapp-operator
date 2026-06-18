/*
Copyright 2026.

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
*/

package v1

import (
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/apimachinery/pkg/runtime"
)

// ReliableAppSpec defines the desired state of ReliableApp
type ReliableAppSpec struct {
	// Image is the container image to deploy
	// +required
	Image string `json:"image"`

	// Replicas is the number of pod replicas
	// +kubebuilder:validation:Minimum=1
	// +kubebuilder:validation:Maximum=100
	// +required
	Replicas int32 `json:"replicas"`

	// Regions is the list of regions to deploy to
	// +optional
	Regions []string `json:"regions,omitempty"`

	// SLO defines the service level objectives
	// +optional
	SLO *SLOSpec `json:"slo,omitempty"`
}

// SLOSpec defines the SLO targets for a ReliableApp
type SLOSpec struct {
	// Availability is the target availability percentage (e.g. 99.9)
	// +optional
	Availability string `json:"availability,omitempty"`

	// LatencyP99Ms is the target p99 latency in milliseconds
	// +optional
	LatencyP99Ms int32 `json:"latencyP99Ms,omitempty"`
}

// ReliableAppStatus defines the observed state of ReliableApp
type ReliableAppStatus struct {
	// ReadyReplicas is the number of currently ready pods
	// +optional
	ReadyReplicas int32 `json:"readyReplicas,omitempty"`

	// Phase represents the current lifecycle phase
	// +optional
	Phase string `json:"phase,omitempty"`

	// Conditions represent the current state of the ReliableApp resource
	// +listType=map
	// +listMapKey=type
	// +optional
	Conditions []metav1.Condition `json:"conditions,omitempty"`
}

// +kubebuilder:object:root=true
// +kubebuilder:subresource:status

// ReliableApp is the Schema for the reliableapps API
type ReliableApp struct {
	metav1.TypeMeta `json:",inline"`

	// +optional
	metav1.ObjectMeta `json:"metadata,omitzero"`

	// +required
	Spec ReliableAppSpec `json:"spec"`

	// +optional
	Status ReliableAppStatus `json:"status,omitzero"`
}

// +kubebuilder:object:root=true

// ReliableAppList contains a list of ReliableApp
type ReliableAppList struct {
	metav1.TypeMeta `json:",inline"`
	metav1.ListMeta `json:"metadata,omitzero"`
	Items           []ReliableApp `json:"items"`
}

func init() {
	SchemeBuilder.Register(func(s *runtime.Scheme) error {
		s.AddKnownTypes(SchemeGroupVersion, &ReliableApp{}, &ReliableAppList{})
		return nil
	})
}
