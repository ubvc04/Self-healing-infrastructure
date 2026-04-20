package v1alpha1

import metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"

type HealingPolicySpec struct {
	Namespace          string `json:"namespace"`
	DeploymentName     string `json:"deploymentName"`
	PodLabelSelector   string `json:"podLabelSelector"`
	RestartThreshold   int32  `json:"restartThreshold"`
	ScaleUpStep        int32  `json:"scaleUpStep"`
	MaxReplicas        int32  `json:"maxReplicas"`
	UnhealthyPodTarget int32  `json:"unhealthyPodTarget"`
}

type HealingPolicyStatus struct {
	LastRun              string `json:"lastRun,omitempty"`
	LastAction           string `json:"lastAction,omitempty"`
	RemediatedPods       int32  `json:"remediatedPods,omitempty"`
	DeploymentReplicaSet int32  `json:"deploymentReplicaSet,omitempty"`
}

type HealingPolicy struct {
	metav1.TypeMeta   `json:",inline"`
	metav1.ObjectMeta `json:"metadata,omitempty"`

	Spec   HealingPolicySpec   `json:"spec,omitempty"`
	Status HealingPolicyStatus `json:"status,omitempty"`
}

type HealingPolicyList struct {
	metav1.TypeMeta `json:",inline"`
	metav1.ListMeta `json:"metadata,omitempty"`
	Items           []HealingPolicy `json:"items"`
}
