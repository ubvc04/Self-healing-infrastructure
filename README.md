# Production Self-Healing Kubernetes Platform (GitOps + Observability + Chaos)

This repository is deployable on AWS using Terraform + kubeadm and includes:

- Self-managed Kubernetes cluster (1 control-plane, 2+ workers)
- ArgoCD GitOps with app-of-apps
- GitHub Actions CI/CD image build and promotion
- HPA + KEDA autoscaling
- Prometheus + Grafana + Loki + Tempo + OTEL Collector
- Custom Go self-healing operator
- Litmus chaos experiments

## 0. Prerequisites and Value Rendering

Before deployment, render organization-specific values once:

~~~bash
cp config/platform.env.example config/platform.env
# edit values: GIT_ORG, GIT_REPO, IMAGE_REGISTRY, API_HOST, SSH_PRIVATE_KEY_PATH

bash scripts/render-values.sh
~~~

For full infra + cluster bootstrap (provision, init control plane, join workers):

~~~bash
bash scripts/bootstrap-platform.sh
~~~

## 1. Architecture Diagram

~~~text
                           +-----------------------+
                           |      GitHub Repo      |
                           |  infra, apps, gitops  |
                           +-----------+-----------+
                                       |
                        GitHub Actions | build/push/promote manifests
                                       v
+------------------------------+   +-------------------+
|            ArgoCD            |-->|  Kubernetes API   |
| app-of-apps auto-sync/selfheal|  |   (kubeadm)       |
+---------------+--------------+   +----+---------+----+
                |                       |         |
                v                       v         v
        +-------+--------+        +-----+--+  +--+-------------------+
        | Platform Apps  |        | KEDA  |  | Self-Healer Operator |
        | API/Worker/RMQ |        |  HPA  |  | Pod remediation/scale |
        +-------+--------+        +-----+-+  +-----------+-----------+
                |                        |                |
                v                        v                v
       +--------+---------+   +----------+----+   +------+----------------+
       | Observability    |   | Chaos (Litmus)|   | Recovery Workflows    |
       | Prom/Graf/Loki/  |   | pod/node/net  |   | restart/scale/events  |
       | Tempo/OTEL       |   +---------------+   +------------------------+
       +------------------+
~~~

## 2. Phase 1: Infra Setup (Terraform)

### Why AWS
- Mature Terraform provider and reproducible VPC + EC2 control.
- Works for production-like self-managed kubeadm clusters.
- Easy to scale workers and integrate with cloud-native services later.

### Files
- infra/terraform/aws/main.tf
- infra/terraform/aws/variables.tf
- infra/terraform/aws/outputs.tf
- infra/terraform/aws/user_data.sh

### Commands
~~~bash
cd infra/terraform/aws
cp terraform.tfvars.example terraform.tfvars
# edit terraform.tfvars: public_key + ssh_ingress_cidr + optional region/type

terraform init
terraform plan
terraform apply -auto-approve
terraform output
~~~

### Expected
- 1 VPC, 3 public subnets, IGW, route table, SG, keypair.
- 1 control-plane and 2 worker EC2 nodes with containerd + kubeadm prereqs.

## 3. Phase 2: K8s Cluster Setup

### Files
- cluster/bootstrap/kubeadm-config.yaml
- cluster/bootstrap/01-init-control-plane.sh
- cluster/bootstrap/02-install-cni-cilium.sh
- cluster/bootstrap/03-install-addons.sh
- cluster/bootstrap/04-generate-join-command.sh
- cluster/bootstrap/05-join-worker.sh

### Commands
1. SSH to control-plane:
~~~bash
ssh ubuntu@<control_plane_public_ip>
cd cluster/bootstrap
bash 01-init-control-plane.sh <control_plane_private_ip>
bash 02-install-cni-cilium.sh
bash 03-install-addons.sh
bash 04-generate-join-command.sh
~~~

2. SSH to each worker and join:
~~~bash
ssh ubuntu@<worker_public_ip>
cd cluster/bootstrap
bash 05-join-worker.sh "kubeadm join ..."
~~~

3. Verify:
~~~bash
kubectl get nodes -o wide
kubectl get pods -A
~~~

## 4. Phase 3: GitOps Setup

### Files
- gitops/projects/platform-project.yaml
- gitops/argocd/install-argocd.sh
- gitops/argocd/root-application.yaml
- gitops/argocd/apps/*.yaml

### Commands
~~~bash
cd gitops/argocd
bash install-argocd.sh

kubectl get applications -n argocd
argocd app list
~~~

### Notes
- Root app syncs all child apps automatically.
- All child apps use automated prune + selfHeal.

## 5. Phase 4: Autoscaling

### Files
- apps/api/k8s/hpa.yaml
- platform/autoscaling/keda/trigger-auth.yaml
- platform/autoscaling/keda/scaled-object.yaml

### Commands
~~~bash
kubectl apply -f apps/namespace.yaml
kubectl apply -f apps/rabbitmq.yaml
kubectl apply -f apps/api/k8s/deployment.yaml
kubectl apply -f apps/api/k8s/ingress.yaml
kubectl apply -f apps/api/k8s/hpa.yaml
kubectl apply -f apps/worker/k8s/deployment.yaml
kubectl apply -f platform/autoscaling/keda/trigger-auth.yaml
kubectl apply -f platform/autoscaling/keda/scaled-object.yaml

kubectl get hpa -n apps
kubectl get scaledobject -n apps
~~~

### Queue-driven scaling test
~~~bash
for i in $(seq 1 500); do
  curl -s -X POST http://api.platform.local/enqueue -H "Content-Type: application/json" -d '{"payload":"burst-job"}' >/dev/null
done

kubectl get deploy queue-worker -n apps -w
~~~

## 6. Phase 5: Observability

### Files
- platform/observability/alerts/platform-alerts.yaml
- platform/observability/dashboards-configmap.yaml
- platform/observability/servicemonitor-api.yaml
- platform/observability/tracing-collector-manifests.yaml
- gitops/argocd/apps/prometheus-grafana.yaml
- gitops/argocd/apps/loki-application.yaml
- gitops/argocd/apps/tempo.yaml

### Commands
~~~bash
kubectl apply -f platform/observability/namespace.yaml
kubectl apply -f platform/observability/tracing-collector-manifests.yaml
kubectl apply -f platform/observability/servicemonitor-api.yaml
kubectl apply -f platform/observability/alerts/platform-alerts.yaml
kubectl apply -f platform/observability/dashboards-configmap.yaml

kubectl get pods -n observability
~~~

### Access Grafana
~~~bash
kubectl port-forward svc/kube-prometheus-stack-grafana -n observability 3000:80
~~~
Open: http://localhost:3000

### Validate signals
~~~bash
# metrics
curl -s http://api.platform.local/metrics | head

# traces (Tempo)
kubectl logs deploy/otel-collector -n observability

# logs (Loki)
kubectl logs deploy/platform-api -n apps
~~~

## 7. Phase 6: Self-Healing Operator (Go code)

### Files
- operator/self-healer/main.go
- operator/self-healer/controllers/healingpolicy_controller.go
- operator/self-healer/api/v1alpha1/healingpolicy_types.go
- operator/self-healer/config/crd/bases/platform.example.com_healingpolicies.yaml
- operator/self-healer/config/manager/manager.yaml
- operator/self-healer/config/samples/platform_v1alpha1_healingpolicy.yaml

### Build and push
~~~bash
cd operator/self-healer
go mod tidy
go build ./...
docker build -t <IMAGE_REGISTRY>/self-healer-operator:latest .
docker push <IMAGE_REGISTRY>/self-healer-operator:latest
~~~

### Deploy
~~~bash
kubectl apply -k operator/self-healer/config
kubectl get crd healingpolicies.platform.example.com
kubectl get pods -n self-healer-system
~~~

### What it does
- Detects unhealthy pods by:
  - CrashLoopBackOff
  - restartCount >= threshold
  - failed pod phase
- Deletes unhealthy pods to force clean restart.
- Scales target deployment if unhealthy pod count crosses threshold.
- Emits Kubernetes events and status updates for auditability.

## 8. Phase 7: Chaos Engineering

### Files
- chaos/litmus/install-litmus.yaml
- chaos/litmus/pod-delete.yaml
- chaos/litmus/node-drain.yaml
- chaos/litmus/network-latency.yaml

### Commands
~~~bash
kubectl apply -f chaos/litmus/namespace.yaml
kubectl apply -f chaos/litmus/install-litmus.yaml

kubectl apply -f chaos/litmus/pod-delete.yaml
kubectl apply -f chaos/litmus/node-drain.yaml
kubectl apply -f chaos/litmus/network-latency.yaml

kubectl get chaosengine -n litmus
~~~

### Observe recovery
~~~bash
kubectl get pods -n apps -w
kubectl get deploy queue-worker -n apps -w
kubectl get events -n apps --sort-by=.lastTimestamp
kubectl logs deploy/self-healer-controller-manager -n self-healer-system -f
~~~

## 9. Phase 8: Testing & Validation

### Failure simulation
1. Crash worker container:
~~~bash
kubectl exec -n apps deploy/queue-worker -- sh -c 'kill 1'
~~~
2. Force restart storm:
~~~bash
kubectl patch deploy queue-worker -n apps -p '{"spec":{"template":{"spec":{"containers":[{"name":"worker","env":[{"name":"RABBITMQ_HOST","value":"invalid-host"}]}]}}}}'
~~~
3. Restore config after operator action:
~~~bash
kubectl rollout undo deploy/queue-worker -n apps
~~~

### Load test
~~~bash
# if k6 installed locally
k6 run apps/load-generator/k6-script.js

# alternatively hammer enqueue
for i in $(seq 1 1000); do
  curl -X POST http://api.platform.local/enqueue -H "Content-Type: application/json" -d '{"payload":"load-test"}'
done
~~~

### Validation checks
~~~bash
kubectl get hpa -n apps
kubectl get scaledobject -n apps
kubectl get deploy -n apps
kubectl describe healingpolicy apps-healing-policy -n self-healer-system
kubectl top pods -n apps
~~~

### Expected outputs
- HPA increases API replicas under CPU/memory pressure.
- KEDA increases worker replicas when RabbitMQ queue grows.
- Self-healer deletes unhealthy pods and may scale worker deployment.
- Prometheus fires alerts for restart storms, CPU spikes, and latency.
- Grafana shows request rate/latency/replica trends.

## 10. Production Best Practices

### Security
- Use external secret manager (AWS Secrets Manager + External Secrets Operator).
- Enforce Pod Security Standards (baseline/restricted) per namespace.
- Replace cluster-admin chaos binding with scoped RBAC in production.
- Enable image signing and verification (cosign + admission policy).
- Add CiliumNetworkPolicy egress rules for strict east-west control.

### Cost optimization
- Right-size EC2 by observed utilization, then switch to mixed instances.
- Use spot workers for non-critical workloads and chaos test pools.
- Retention tuning:
  - Prometheus 15d or less
  - Loki/Tempo short retention with object storage if needed
- Configure autoscaling limits to avoid runaway cost under bad load patterns.

### Scaling considerations
- Separate control-plane from worker subnets for strict network domains.
- Move stateful dependencies (RabbitMQ, Loki, Tempo storage) to managed or HA backends.
- Use cluster-autoscaler when moving from static VMs to autoscaling node groups.
- Add canary rollout strategy (Argo Rollouts) for safer production deploys.

### Common pitfalls
- Missing resource requests/limits causing noisy-neighbor failures.
- GitOps drift when manual kubectl changes are not blocked.
- KEDA secrets embedded in plain manifests instead of externalized secret providers.
- Alert fatigue due to low-signal rules without routing/severity policy.
