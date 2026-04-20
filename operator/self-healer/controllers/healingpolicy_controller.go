package controllers

import (
	"context"
	"fmt"
	"strings"
	"time"

	appsv1 "k8s.io/api/apps/v1"
	corev1 "k8s.io/api/core/v1"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/apimachinery/pkg/labels"
	"k8s.io/apimachinery/pkg/runtime"
	"k8s.io/apimachinery/pkg/types"
	ctrl "sigs.k8s.io/controller-runtime"
	"sigs.k8s.io/controller-runtime/pkg/client"

	healv1alpha1 "github.com/YOUR_ORG/self-healer-operator/api/v1alpha1"
)

type HealingPolicyReconciler struct {
	client.Client
	Scheme *runtime.Scheme
}

func (r *HealingPolicyReconciler) Reconcile(ctx context.Context, req ctrl.Request) (ctrl.Result, error) {
	policy := &healv1alpha1.HealingPolicy{}
	if err := r.Get(ctx, req.NamespacedName, policy); err != nil {
		return ctrl.Result{}, client.IgnoreNotFound(err)
	}

	selector, err := labels.Parse(policy.Spec.PodLabelSelector)
	if err != nil {
		return ctrl.Result{RequeueAfter: time.Minute}, nil
	}

	podList := &corev1.PodList{}
	if err := r.List(ctx, podList, &client.ListOptions{Namespace: policy.Spec.Namespace, LabelSelector: selector}); err != nil {
		return ctrl.Result{}, err
	}

	var unhealthyPods []corev1.Pod
	for _, pod := range podList.Items {
		if isUnhealthyPod(pod, policy.Spec.RestartThreshold) {
			unhealthyPods = append(unhealthyPods, pod)
		}
	}

	remediated := int32(0)
	for _, pod := range unhealthyPods {
		if err := r.Delete(ctx, &pod); client.IgnoreNotFound(err) != nil {
			return ctrl.Result{}, err
		}
		remediated++
	}

	action := "noop"
	if int32(len(unhealthyPods)) >= policy.Spec.UnhealthyPodTarget {
		action, err = r.scaleDeployment(ctx, policy)
		if err != nil {
			return ctrl.Result{}, err
		}
	}

	policy.Status.LastRun = time.Now().UTC().Format(time.RFC3339)
	policy.Status.LastAction = action
	policy.Status.RemediatedPods = remediated
	_ = r.Status().Update(ctx, policy)

	return ctrl.Result{RequeueAfter: 30 * time.Second}, nil
}

func (r *HealingPolicyReconciler) scaleDeployment(ctx context.Context, policy *healv1alpha1.HealingPolicy) (string, error) {
	dep := &appsv1.Deployment{}
	err := r.Get(ctx, types.NamespacedName{Name: policy.Spec.DeploymentName, Namespace: policy.Spec.Namespace}, dep)
	if err != nil {
		return "deployment-not-found", nil
	}

	currentReplicas := int32(1)
	if dep.Spec.Replicas != nil {
		currentReplicas = *dep.Spec.Replicas
	}

	target := currentReplicas + policy.Spec.ScaleUpStep
	if target > policy.Spec.MaxReplicas {
		target = policy.Spec.MaxReplicas
	}
	if target == currentReplicas {
		return "at-max-replicas", nil
	}

	dep.Spec.Replicas = &target
	if dep.Annotations == nil {
		dep.Annotations = map[string]string{}
	}
	dep.Annotations["self-healer.platform.example.com/last-recovery"] = time.Now().UTC().Format(time.RFC3339)
	dep.Annotations["self-healer.platform.example.com/recovery-note"] = fmt.Sprintf("scaled from %d to %d", currentReplicas, target)

	if err := r.Update(ctx, dep); err != nil {
		return "scale-failed", err
	}

	evt := &corev1.Event{
		ObjectMeta: metav1.ObjectMeta{
			GenerateName: "self-healer-",
			Namespace:    policy.Spec.Namespace,
		},
		InvolvedObject: corev1.ObjectReference{
			Kind:      "Deployment",
			Namespace: dep.Namespace,
			Name:      dep.Name,
			UID:       dep.UID,
		},
		Reason:  "SelfHealingScaleUp",
		Message: fmt.Sprintf("Self-healer scaled deployment %s from %d to %d", dep.Name, currentReplicas, target),
		Type:    corev1.EventTypeNormal,
		Source:  corev1.EventSource{Component: "self-healer-operator"},
	}
	_ = r.Create(ctx, evt)

	return "scaled-up", nil
}

func isUnhealthyPod(pod corev1.Pod, threshold int32) bool {
	if pod.Status.Phase == corev1.PodFailed {
		return true
	}

	for _, cs := range pod.Status.ContainerStatuses {
		if cs.RestartCount >= threshold {
			return true
		}
		if cs.State.Waiting != nil && strings.Contains(cs.State.Waiting.Reason, "CrashLoopBackOff") {
			return true
		}
	}

	return false
}

func (r *HealingPolicyReconciler) SetupWithManager(mgr ctrl.Manager) error {
	return ctrl.NewControllerManagedBy(mgr).
		For(&healv1alpha1.HealingPolicy{}).
		Complete(r)
}
