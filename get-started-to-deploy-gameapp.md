# Get Started: Deploy GameHub on Minikube

This guide deploys the GameHub application from a fresh repository clone to a
Minikube cluster. The application consists of PostgreSQL, Auth, Game, and a
frontend served by Nginx.

Run the commands below in PowerShell from the repository root. These steps use
the root-level Kubernetes manifests, not Docker Compose.

## 1. Confirm Minikube is the current cluster

```powershell
cd C:\path\to\Kubernetes-crash-course-2025

minikube profile list
minikube status
kubectl config current-context
kubectl get nodes
```

Make sure `kubectl get nodes` shows the Minikube node as `Ready`. If the
current context is not the Minikube cluster, switch to its context before
continuing:

```powershell
kubectl config use-context <minikube-context-name>
```

## 2. Make sure the application images are available

The manifests refer to these Docker Hub images:

- `lakshmisaranya/gamehub:auth-v1`
- `lakshmisaranya/gamehub:game-v1`
- `lakshmisaranya/gamehub:frontend-v1`

Kubernetes will try to pull them when the Pods start. If those images aren’t
accessible, build them from the repository root and load them into Minikube:

```powershell
docker build -t lakshmisaranya/gamehub:auth-v1 .\auth-service
docker build -t lakshmisaranya/gamehub:game-v1 .\game-service
docker build -t lakshmisaranya/gamehub:frontend-v1 .\frontend

minikube image load lakshmisaranya/gamehub:auth-v1 -p gamehub-cluster
minikube image load lakshmisaranya/gamehub:game-v1 -p gamehub-cluster
minikube image load lakshmisaranya/gamehub:frontend-v1 -p gamehub-cluster
```

Replace `gamehub-cluster` with the profile name shown by `minikube profile
list`.

## 3. Create the namespace and database resources

Apply these manifests from the repository root, in order:

```powershell
kubectl apply -f .\namespace.yaml
kubectl apply -f .\postgres-pvc.yaml
kubectl apply -f .\postgres-secret.yaml
kubectl apply -f .\postgres-configmap.yaml
kubectl apply -f .\postgres-service.yaml
kubectl apply -f .\postgres-deployment.yaml

kubectl rollout status deployment/postgres -n gamehub --timeout=180s
kubectl get pvc -n gamehub
```

Check that the PostgreSQL Deployment rollout completes and the PVC becomes
`Bound` before proceeding.

## 4. Deploy Auth and Game

```powershell
kubectl apply -f .\auth-deployment.yaml
kubectl apply -f .\auth-service.yaml
kubectl apply -f .\game-deployment.yaml
kubectl apply -f .\game-service.yaml

kubectl set env deployment/auth-deployment --from=secret/gamehub-db-secret -n gamehub
kubectl set env deployment/game-deployment --from=secret/gamehub-db-secret -n gamehub

kubectl rollout status deployment/auth-deployment -n gamehub
kubectl rollout status deployment/game-deployment -n gamehub
```

The `kubectl set env` commands are important: the Auth and Game manifests
don’t set the database environment variables themselves. These commands load
them from the Secret.

## 5. Deploy the frontend last

```powershell
kubectl apply -f .\frontend-deployment.yaml
kubectl apply -f .\frontend-service.yaml

kubectl rollout status deployment/gamehub-frontend -n gamehub
```

The frontend has an init container that waits for the Auth Service, so apply it
after the backend Services.

## 6. Check the deployment and open the app

```powershell
kubectl get deployments,pods,services -n gamehub
kubectl get pvc -n gamehub
kubectl get endpointslices -n gamehub

minikube service frontend-service -n gamehub -p gamehub-cluster
```

Replace `gamehub-cluster` with the actual Minikube profile name. The last
command opens the frontend in a browser. Try registering and logging in to
check the app’s database-backed features.

## Troubleshooting

If something isn’t ready, inspect the Pods and application logs:

```powershell
kubectl describe pods -n gamehub
kubectl logs deployment/postgres -n gamehub
kubectl logs deployment/auth-deployment -n gamehub
kubectl logs deployment/game-deployment -n gamehub
```

The root manifests use namespace `gamehub` and Service `frontend-service`.
The database credentials in `postgres-secret.yaml` are for local development
only, not production.
