# Get Started: Deploy GameHub on Minikube

This guide deploys the GameHub application from a fresh repository clone to a
Minikube cluster. The application consists of PostgreSQL, Auth, Game, and a
frontend served by Nginx.

Run the commands below in PowerShell from the repository root. These steps use
the root-level Kubernetes manifests, not Docker Compose.

## 1. Start Minikube and select the target profile and context

```powershell
# Change this placeholder to the path where you cloned the repository.
cd C:\path\to\Kubernetes-crash-course-2025

# Start the Minikube cluster named gamehub-cluster.
minikube start -p gamehub-cluster
# Set gamehub-cluster as the default Minikube profile.
minikube profile gamehub-cluster
# Set kubectl's active context to the gamehub-cluster cluster.
kubectl config use-context gamehub-cluster

# List Minikube profiles.
minikube profile list
# Check the status of the gamehub-cluster profile.
minikube status -p gamehub-cluster
# Confirm the active kubectl context.
kubectl config current-context
# Check that the cluster's node is Ready.
kubectl get nodes
```

The Minikube profile selects the cluster for `minikube` commands.
`kubectl config use-context` selects the cluster for `kubectl` commands.
Check that `kubectl config current-context` prints `gamehub-cluster` and that
`kubectl get nodes` shows its Minikube node as `Ready` before continuing.

## 2. Application images

The manifests refer to these Docker Hub images:

- `lakshmisaranya/gamehub:auth-v1`
- `lakshmisaranya/gamehub:game-v1`
- `lakshmisaranya/gamehub:frontend-v1`

These images are public on Docker Hub, so Kubernetes can pull them when the
Pods start. Building and loading local copies is optional. If you want to use
local builds instead, run these commands from the repository root:

```powershell
# Build the Auth service image from its Dockerfile.
docker build -t lakshmisaranya/gamehub:auth-v1 .\auth-service
# Build the Game service image from its Dockerfile.
docker build -t lakshmisaranya/gamehub:game-v1 .\game-service
# Build the frontend image from its Dockerfile.
docker build -t lakshmisaranya/gamehub:frontend-v1 .\frontend

# Optional: load each locally built image into the gamehub-cluster profile.
minikube image load lakshmisaranya/gamehub:auth-v1 -p gamehub-cluster
minikube image load lakshmisaranya/gamehub:game-v1 -p gamehub-cluster
minikube image load lakshmisaranya/gamehub:frontend-v1 -p gamehub-cluster
```

Skip the local build and `minikube image load` commands for the normal
deployment; the image references in the manifests are publicly available on
Docker Hub.

## 3. Create the namespace and database resources

Apply these manifests from the repository root, in order:

```powershell
# Create the gamehub namespace used by the application resources.
kubectl apply -f .\namespace.yaml
# Create the PersistentVolumeClaim for PostgreSQL data.
kubectl apply -f .\postgres-pvc.yaml
# Create the Secret containing PostgreSQL connection settings.
kubectl apply -f .\postgres-secret.yaml
# Create the ConfigMap containing the PostgreSQL initialization SQL.
kubectl apply -f .\postgres-configmap.yaml
# Create the internal Service that provides the PostgreSQL endpoint.
kubectl apply -f .\postgres-service.yaml
# Create the PostgreSQL Deployment.
kubectl apply -f .\postgres-deployment.yaml

# Wait up to 180 seconds for the PostgreSQL Deployment rollout.
kubectl rollout status deployment/postgres -n gamehub --timeout=180s
# Check the PostgreSQL PersistentVolumeClaim status.
kubectl get pvc -n gamehub
```

Check that the PostgreSQL Deployment rollout completes and the PVC becomes
`Bound` before proceeding.

## 4. Deploy Auth and Game

```powershell
# Create the Auth service Deployment and its internal Service.
kubectl apply -f .\auth-deployment.yaml
kubectl apply -f .\auth-service.yaml
# Create the Game service Deployment and its internal Service.
kubectl apply -f .\game-deployment.yaml
kubectl apply -f .\game-service.yaml

# Add the database settings from the Secret to the Auth Deployment.
kubectl set env deployment/auth-deployment --from=secret/gamehub-db-secret -n gamehub
# Add the database settings from the Secret to the Game Deployment.
kubectl set env deployment/game-deployment --from=secret/gamehub-db-secret -n gamehub

# Wait for the Auth Deployment rollout to complete.
kubectl rollout status deployment/auth-deployment -n gamehub
# Wait for the Game Deployment rollout to complete.
kubectl rollout status deployment/game-deployment -n gamehub
```

The `kubectl set env` commands are important: the Auth and Game manifests
don’t set the database environment variables themselves. These commands load
them from the Secret.

## 5. Deploy the frontend last

```powershell
# Create the frontend Deployment.
kubectl apply -f .\frontend-deployment.yaml
# Create the NodePort Service used to access the frontend.
kubectl apply -f .\frontend-service.yaml

# Wait for the frontend Deployment rollout to complete.
kubectl rollout status deployment/gamehub-frontend -n gamehub
```

The frontend has an init container that waits for the Auth Service, so apply it
after the backend Services.

## 6. Check the deployment and open the app

```powershell
# List application Deployments, Pods, and Services in the gamehub namespace.
kubectl get deployments,pods,services -n gamehub
# Check the database PersistentVolumeClaim.
kubectl get pvc -n gamehub
# Check the Service endpoint slices.
kubectl get endpointslices -n gamehub

# Open the frontend Service using the gamehub-cluster Minikube profile.
minikube service frontend-service -n gamehub -p gamehub-cluster
```

The last command opens the frontend in a browser. Try registering and logging
in to check the app’s database-backed features.

## Graceful shutdown before shutting down the system

Run these commands before shutting down the computer to scale down the
application and stop Minikube:

```powershell
# Confirm kubectl is pointed at the intended cluster.
kubectl config current-context
# Check the current Pods in the gamehub namespace.
kubectl get pods -n gamehub
# Scale every Deployment in gamehub to zero replicas.
kubectl scale deployment --all --replicas=0 -n gamehub
# Check that the Pods have been scaled down.
kubectl get pods -n gamehub
# Stop the gamehub-cluster Minikube profile.
minikube stop -p gamehub-cluster
```

## Start the application after the system starts

Run these commands to start Minikube again and scale the Deployments back up:

```powershell
# Start the gamehub-cluster Minikube profile.
minikube start -p gamehub-cluster
# Check that the Kubernetes node is Ready.
kubectl get nodes
# Scale every Deployment in gamehub back to one replica.
kubectl scale deployment --all --replicas=1 -n gamehub
# Check the Pods as the application starts.
kubectl get pods -n gamehub
# Open the frontend Service using the gamehub-cluster Minikube profile.
minikube service frontend-service -n gamehub -p gamehub-cluster
```

## Troubleshooting

If something isn’t ready, inspect the Pods and application logs:

```powershell
# Show Pod details and recent events in the gamehub namespace.
kubectl describe pods -n gamehub
# Show PostgreSQL container logs.
kubectl logs deployment/postgres -n gamehub
# Show Auth service container logs.
kubectl logs deployment/auth-deployment -n gamehub
# Show Game service container logs.
kubectl logs deployment/game-deployment -n gamehub
```

The root manifests use namespace `gamehub` and Service `frontend-service`.
The database credentials in `postgres-secret.yaml` are for local development
only, not production.
