# GameHub Kubernetes Deployment — Learning Notes

**Last updated:** 05 November 2026  
**Current checkpoint:** Frontend, Auth, Game, and PostgreSQL workloads
deployed; frontend opened successfully in the browser; application/API
verification still pending  
**Minikube profile:** `gamehub-cluster`  
**Reviewer:** Dhulipala Lakshmi
Saranya

------------------------------------------------------------------------

## 1. Project goal

Deploy the existing GameHub application, previously run with Docker
Compose, to a local Kubernetes cluster using Minikube. We are proceeding
one component at a time, inspecting each resource and understanding
errors before moving forward.

## 2. GameHub application architecture

- **Frontend**
  - **Technology:** React, Tailwind, Nginx
  - **Container port:** 80
  - **Purpose:** User interface and reverse proxy
- **Auth service**
  - **Technology:** Python Flask, JWT, Gunicorn
  - **Container port:** 8080
  - **Purpose:** Registration and login
- **Game service**
  - **Technology:** Python Flask, Gunicorn
  - **Container port:** 8081
  - **Purpose:** Game statistics and scores
- **Database**
  - **Technology:** PostgreSQL 13
  - **Container port:** 5432
  - **Purpose:** Application data

The frontend’s Nginx configuration proxies requests as follows:

- **`/api/auth/*`**
  - **Upstream hostname:** `auth-service`
  - **Upstream port:** 8080
- **`/api/game/*`**
  - **Upstream hostname:** `game-service`
  - **Upstream port:** 8081

### Understanding Upstream Host and Upstream Port

In Nginx, we use the term **upstream host** and **upstream port** to describe the destination to which Nginx forwards a request.

Let's understand this using our GameHub Nginx configuration:

```nginx
location /api/auth/ {
    proxy_pass http://auth-service:8080/;
}

location /api/game/ {
    proxy_pass http://game-service:8081/;
}
```

#### 1. Are upstream host and upstream port different from a normal host and port?

No. They are still ordinary host and port values.

The word **upstream** simply describes their role from Nginx's perspective.

For example:

```text
auth-service:8080
```

- **Host:** `auth-service`
- **Port:** `8080`
- **Upstream host:** `auth-service`
- **Upstream port:** `8080`

Why do we call them upstream?

Because they represent the destination to which Nginx forwards incoming requests.

#### 2. Understand the two connections

When a user accesses GameHub, there are two separate connections:

**Connection 1: Browser → Frontend Nginx**

The browser sends a request to the frontend. Nginx receives that request.

**Connection 2: Frontend Nginx → Backend Service**

If the request is for authentication, Nginx forwards it to:

```text
auth-service:8080
```

If the request is for game-related functionality, Nginx forwards it to:

```text
game-service:8081
```

These backend destinations are called upstream hosts and upstream ports from Nginx's perspective.

#### 3. Visual representation

```text
                 USER'S BROWSER
                       |
                       | Request
                       v
                FRONTEND NGINX
                   Port 80
                       |
             Nginx checks the URL path
                       |
              +--------+--------+
              |                 |
        /api/auth/         /api/game/
              |                 |
              v                 v
        auth-service       game-service
           Port 8080          Port 8081
              |                 |
              v                 v
          Auth Backend      Game Backend
```

#### 4. Key takeaway

- **Host and port:** Identify a destination machine/service and its port.
- **Upstream host and upstream port:** The host and port of the destination to which Nginx forwards a request.
- The word `upstream` does not introduce a different type of host or port. It describes their role in request forwarding.

In our GameHub application:
- `auth-service:8080` is the upstream host and port for authentication requests.
- `game-service:8081` is the upstream host and port for game-related requests.

Docker Compose provides DNS resolution for Compose service names on its
network. Kubernetes uses Kubernetes Services and cluster DNS to provide
stable names for backend workloads. This is an important difference when
moving the application from Compose to Kubernetes: the frontend continues
to use backend service names, but Kubernetes Services and cluster DNS
provide those names inside the cluster.

The database is initialized using the project's `init.sql`. The Compose
setup uses a persistent `pgdata` volume. In the later Kubernetes
deployment work documented in Section 15, PostgreSQL was deployed with a
PersistentVolumeClaim for storage, a Secret for database settings, a
ConfigMap for the initialization script, a Deployment, and a ClusterIP
Service.

## Dockerfiles: One Dockerfile vs Multiple Dockerfiles

A Dockerfile contains instructions to build a Docker image.

When an application consists of multiple services, we need to decide
whether to use one Dockerfile or multiple Dockerfiles.

### Option 1: One Dockerfile for the entire application

We could create one Dockerfile that packages the entire application into
a single image.

However, this approach is not ideal for an application like GameHub
because it contains multiple independent services:

- Frontend
- Auth service
- Game service

Each service has different dependencies, configurations, and
responsibilities.

Packaging everything together would make it harder to build, update, and
deploy individual services independently.

### Option 2: Separate Dockerfiles for each service

We use a separate Dockerfile for each service.

For our GameHub application:

- **Frontend**
  - **Dockerfile:** Frontend Dockerfile
  - **Purpose:** Builds the React application and packages it with Nginx
- **Auth**
  - **Dockerfile:** Auth Dockerfile
  - **Purpose:** Packages the authentication service and its dependencies
- **Game**
  - **Dockerfile:** Game Dockerfile
  - **Purpose:** Packages the game service and its dependencies

Each Dockerfile produces its own Docker image.

``` text
                 GameHub Application
                         |
          +--------------+--------------+
          |              |              |
       Frontend         Auth           Game
          |              |              |
     Dockerfile      Dockerfile      Dockerfile
          |              |              |
     Frontend         Auth           Game
       Image          Image          Image
```

### Why did we choose separate Dockerfiles?

1.  **Independent builds:** We can build each service separately.
2.  **Independent deployments:** We can deploy or update one service
    without rebuilding the others.
3.  **Different dependencies:** Each service can have its own runtime
    and required packages.
4.  **Independent scaling:** Kubernetes can scale each service according
    to its workload.

**Important:** One Dockerfile normally produces one image. An
application does not necessarily need one Dockerfile per service in
every architecture, but separate Dockerfiles are a sensible choice for
our GameHub services.

------------------------------------------------------------------------

## Making Docker Images Available to Minikube

After building Docker images, Kubernetes needs access to those images to
create containers for our Pods.

However, there is an important distinction between Docker Desktop and
Minikube.

Our Docker Desktop has its own local image store. Minikube uses its own
container runtime, containerd.

Therefore, an image available in Docker Desktop is not automatically
available inside Minikube.

We have two approaches to make images available.

### Approach 1: Push images to Docker Hub

Docker Hub is a remote container image registry where we can store and
distribute Docker images.

The workflow is:

``` text
Dockerfile
    |
    v
Build Docker Image
    |
    v
Tag Docker Image
    |
    v
Push Image to Docker Hub
    |
    v
Kubernetes Deployment references the image
    |
    v
Minikube pulls the image from Docker Hub
    |
    v
Container starts inside the Pod
```

Example:

``` powershell
docker build -t lakshmisaranya/gamehub:frontend-v1 .
```

Push the image:

``` powershell
docker push lakshmisaranya/gamehub:frontend-v1
```

Reference the image in the Kubernetes Deployment YAML:

``` yaml
containers:
  - name: frontend
    image: lakshmisaranya/gamehub:frontend-v1
```

When Kubernetes needs to create the Pod, Minikube can pull the image
from Docker Hub.

**Advantages:** - Images are stored remotely. - Images can be used
across different environments. - Team members can access the same
images, subject to registry permissions. - This approach is closer to a
typical production deployment workflow.

**Considerations:** - Requires access to Docker Hub or another
registry. - Pulling images requires network connectivity unless the
image is already cached. - Private repositories require registry
authentication.

### Approach 2: Load local Docker images into Minikube

If we only want to use an image locally, we do not necessarily need to
push it to Docker Hub.

We can load the image directly into Minikube.

Example:

``` powershell
minikube image load lakshmisaranya/gamehub:frontend-v1 -p gamehub-cluster
```

The workflow is:

``` text
Dockerfile
    |
    v
Build Docker Image in Docker Desktop
    |
    v
Load Image into Minikube
    |
    v
Kubernetes Deployment references the image
    |
    v
Minikube uses its locally available image
    |
    v
Container starts inside the Pod
```

**Advantages:** - No need to push images to Docker Hub. - Useful for
local development and testing. - Avoids downloading the image from a
remote registry.

**Considerations:** - Images must be loaded into the correct Minikube
profile. - Other environments cannot automatically access these local
images. - When an image changes, we need to load the updated image
again.

For locally loaded images, configure an appropriate image pull policy,
such as:

``` yaml
imagePullPolicy: IfNotPresent
```

This allows Kubernetes to use the local image when it is available.

------------------------------------------------------------------------

### Which approach should we use?

- **Local development and quick testing**
  - **Recommended approach:** Load images into Minikube
- **Sharing images with team members**
  - **Recommended approach:** Push images to a registry
- **Deploying across different environments**
  - **Recommended approach:** Use a container registry
- **Practising a production-like deployment workflow**
  - **Recommended approach:** Use a container registry

### What we chose for GameHub

We chose to push our frontend, auth, and game service images to Docker
Hub.

Why?

- We wanted to make the images available outside our local Docker
  Desktop environment.
- We wanted to practise a deployment workflow that resembles how images
  are distributed in real-world environments.
- Minikube can pull these images using the references in our Deployment
  YAML files.

### Important takeaway

Pushing images to Docker Hub and loading images into Minikube are two
different ways of making images available to Kubernetes.

Neither approach is universally better. The choice depends on whether we
need local-only development or image distribution across environments.

## 3. Environment and cluster

- **Operating system**
  - **Recorded value:** Windows 11
- **Docker Engine**
  - **Recorded value:** `29.9.2`
- **Docker Desktop**
  - **Recorded value:** `4.97.0`
- **Minikube**
  - **Recorded value:** `v1.39.0`
- **Kubernetes**
  - **Recorded value:** `v1.37.0`
- **Minikube container runtime**
  - **Recorded value:** `containerd://2.3.4`
- **Active Minikube profile**
  - **Recorded value:** `gamehub-cluster`
- **Current kubectl context**
  - **Recorded value:** `gamehub-cluster`
- **Kubernetes node name**
  - **Recorded value:** `gamehub-cluster`
- **Number of nodes**
  - **Recorded value:** 1

Project directory in PowerShell:

``` powershell
C:\Users\Ara\OneDrive\Desktop\k8s-project\Kubernetes-crash-course-2025
```

### 3.1 Cluster name versus node name

These are different concepts, even though they currently have the same
value.

- **Minikube profile name**
  - **What it identifies:** The Minikube cluster/profile managed by Minikube
  - **Current value:** `gamehub-cluster`
- **Kubernetes node name**
  - **What it identifies:** A machine registered with Kubernetes
  - **Current value:** `gamehub-cluster`

This is a single-node cluster, so it has one Kubernetes Node object.
Minikube commonly uses the profile name as the node name.

**Can the node be named `gamehub-node`?** Yes. The kubelet supports a
hostname override that controls the node identity it registers with.
Minikube supports Kubernetes component customization through
`--extra-config`. However, this is not a simple edit to the existing
Node object: the kubelet must register using the new identity. For an
existing Minikube cluster, that generally requires
reconfiguring/recreating the node or cluster.

We are keeping the current name. Renaming it has no functional benefit
for GameHub and is not worth disturbing the working cluster.

Useful checks:

``` powershell
minikube profile list
kubectl config current-context
kubectl get nodes -o wide
```

### 3.2 Docker Desktop and Minikube Use Separate Image Stores

Before understanding why we pushed our GameHub images to Docker Hub, let's understand how Docker Desktop and Minikube manage images.

#### 1. We have two separate environments

In our setup, Docker Desktop and Minikube operate in separate environments.

**Environment 1: Docker Desktop (Windows machine)**

Docker Desktop provides Docker Engine, which we use to build, download, and manage Docker images.

For example:

```powershell
docker build -t myapp:v1 .
```

This command builds an image and stores it in Docker Desktop's image store.

We can list the images available there using:

```powershell
docker images
```

For example:

```text
REPOSITORY       TAG
myapp            v1
nginx            latest
postgres         13
```

These images are available to the Docker Engine that our Docker CLI is connected to.

**Environment 2: Minikube (Kubernetes environment)**

Our Minikube node runs Kubernetes and uses **containerd** as its container runtime.

We verified this using:

```powershell
kubectl get nodes -o wide
```

The output showed:

```text
CONTAINER-RUNTIME
containerd://2.3.4
```

Containerd is responsible for managing containers inside the Minikube node. It also manages the images required to create those containers.

**Important:** Docker Desktop's image store and Minikube's containerd image store are separate. Having an image in Docker Desktop does not automatically make that image available inside Minikube.

#### 2. Why is this separation important?

Let's consider an example.

We build an image using Docker Desktop:

```powershell
docker build -t myapp:v1 .
```

We can see that image using:

```powershell
docker images
```

Now suppose we create a Kubernetes Deployment with this configuration:

```yaml
containers:
  - name: myapp
    image: myapp:v1
```

Kubernetes needs this image to create the application container.

However, Kubernetes asks the container runtime inside Minikube to provide the image.

Containerd checks its own image store. It does not automatically use the image stored in Docker Desktop.

If the image is unavailable locally and cannot be pulled from a registry, the Pod cannot start successfully. We may see an `ImagePullBackOff` error.

#### 3. How do we make the image available to Minikube?

There are two common approaches:

**Approach 1: Push the image to Docker Hub**

1. Build the image using Docker Desktop.
2. Push it to Docker Hub using `docker push`.
3. Reference the Docker Hub image in the Kubernetes Deployment YAML.
4. When Kubernetes needs the image, the container runtime inside Minikube can pull it from Docker Hub.

Example:

```powershell
docker push lakshmisaranya/gamehub:frontend-v1
```

Deployment YAML:

```yaml
containers:
  - name: frontend
    image: lakshmisaranya/gamehub:frontend-v1
```

**Approach 2: Load the image directly into Minikube**

Minikube also provides a command to load an image from the local Docker environment into Minikube:

```powershell
minikube image load myapp:v1 -p gamehub-cluster
```

This makes the image available inside the specified Minikube profile without requiring a Docker Hub push.

#### 4. What approach did we use in our GameHub project?

We used **Approach 1: Docker Hub**.

Our image journey was:

```text
STEP 1: BUILD
Docker Desktop / Docker Engine
        |
        | Builds application images
        v
STEP 2: PUSH
Docker Hub
        |
        | Stores our images
        v
STEP 3: PULL
Minikube / containerd
        |
        | Pulls the required image
        v
STEP 4: RUN
Kubernetes creates the application container
```

We pushed the following custom images to our public Docker Hub repository:

| Application | Docker Hub image |
|---|---|
| Frontend | `lakshmisaranya/gamehub:frontend-v1` |
| Auth | `lakshmisaranya/gamehub:auth-v1` |
| Game | `lakshmisaranya/gamehub:game-v1` |

Our Kubernetes Deployment YAML files reference these Docker Hub images. This allows Minikube to pull the required images when creating the application Pods.

#### 5. Key Takeaways

- **Docker Engine:** Builds and manages Docker images and containers in the Docker Desktop environment.
- **Containerd:** Manages images and containers inside our Minikube node.
- **Image stores:** Docker Desktop and Minikube maintain separate image stores in our setup.
- **Docker Hub:** A remote image registry where we store and share our images.
- **Image availability:** Kubernetes needs the image to be available to its container runtime, either by pulling it from a registry or by loading it directly into Minikube.

**Remember:** An image visible in `docker images` is not automatically available to Kubernetes inside Minikube. We must make that image available to Minikube separately.
## 4. Rebuild the application images

The project already contained Dockerfiles and a Docker Compose
configuration. We changed to the project root and rebuilt the images:

``` powershell
cd C:\Users\Ara\OneDrive\Desktop\k8s-project\Kubernetes-crash-course-2025
docker compose build
```

The three custom images are frontend, auth service, and game service.
The database uses the upstream `postgres:13` image.

### Issue: Compose command run from the wrong directory

**Problem:** Docker Compose initially reported that no configuration
file was provided.

**Reason:** The command was run from `C:\Users\Ara`, while the Compose
file is in the GameHub project directory.

**Resolution:** Change to the project root and run Compose commands
there.

## 5. Docker Hub repository, tagging, and pushing

We created one **public** Docker Hub repository:

``` text
lakshmisaranya/gamehub
```

All three custom images were tagged in this same repository; separate
repositories were not needed.

- **Frontend**
  - **Docker Hub image:** `lakshmisaranya/gamehub:frontend-v1`
- **Auth service**
  - **Docker Hub image:** `lakshmisaranya/gamehub:auth-v1`
- **Game service**
  - **Docker Hub image:** `lakshmisaranya/gamehub:game-v1`

Docker Hub login succeeded and all three images were pushed
successfully. Because the repository is public, Kubernetes does not need
registry credentials to pull these images.

General workflow:

``` powershell
docker tag <local-image> lakshmisaranya/gamehub:<tag>
docker push lakshmisaranya/gamehub:<tag>
```

The frontend Deployment uses:

``` text
lakshmisaranya/gamehub:frontend-v1
```

Recorded image IDs at the time of tagging/pushing:

- **`frontend-v1`**
  - **Recorded image ID:** `63ac82a71298`
- **`auth-v1`**
  - **Recorded image ID:** `d8718f2ffaf0`
- **`game-v1`**
  - **Recorded image ID:** `e1b8f74bff3c`

**For future rebuilds:** Verify that the intended newly built local
image is the one being tagged before pushing. A tag must point to the
image built from the source version we intend to deploy.

## 6. Create the Kubernetes namespace

A namespace provides a logical scope for grouping Kubernetes resources.
We created a dedicated `gamehub` namespace.

File: `namespace.yaml`

``` yaml
apiVersion: v1
kind: Namespace
metadata:
  name: gamehub
```

Apply:

``` powershell
kubectl apply -f namespace.yaml
```

Output:

``` text
namespace/gamehub created
```

Verify:

``` powershell
kubectl get namespaces
```

The output included the `gamehub` namespace with status `Active`.

We also checked: The below command is used to inspect the resources inside a particular namespace.

``` powershell
kubectl get all -n gamehub
```

Output:

``` text
No resources found in gamehub namespace.
```

This was expected: the namespace existed, but no application resources
had been created inside it yet.

### 6.1 Why does Namespace use `apiVersion: v1`?

Namespace belongs to Kubernetes’ core API group. The core group has no
group-name prefix, so its version is written simply as `v1`.

## 7. Kubernetes API groups and how to find API versions

Kubernetes organizes resources into API groups based on functionality.

- **Core API group (no group prefix)**
  - **Example resources:** Namespace, Pod, Service, ConfigMap
  - **Example `apiVersion`:** `v1`
- **`apps`**
  - **Example resources:** Deployment, ReplicaSet, StatefulSet, DaemonSet
  - **Example `apiVersion`:** `apps/v1`
- **`batch`**
  - **Example resources:** Job, CronJob
  - **Example `apiVersion`:** `batch/v1`
- **`networking.k8s.io`**
  - **Example resources:** Ingress, NetworkPolicy
  - **Example `apiVersion`:** `networking.k8s.io/v1`

For `apps/v1`: - `apps` is the API group. - `v1` is the version within
that API group. - `Deployment` is the resource kind.

API groups organize the Kubernetes API; they are not Kubernetes
namespaces.

### 7.1 Command to find the API version for a resource

The command we discussed was:

``` powershell
kubectl api-resources
```

It lists resource names, API versions, kinds, and whether resources are
namespaced.

Useful columns:

- **`NAME`**
  - **Meaning:** Resource name
- **`APIVERSION`**
  - **Meaning:** API group and version used by that resource
- **`KIND`**
  - **Meaning:** Kind name used in YAML
- **`NAMESPACED`**
  - **Meaning:** Whether the resource is namespace-scoped

Related command:

``` powershell
kubectl api-versions
```

Difference:

- **`kubectl api-resources`**
  - **What it displays:** Resources and the API version each resource uses
  - **When to use it:** Finding the `apiVersion` for a YAML resource
- **`kubectl api-versions`**
  - **What it displays:** API group/version combinations available in the cluster
  - **When to use it:** Listing API versions supported by the cluster

For finding the API version to put in a particular resource YAML,
`kubectl api-resources` is generally the more useful command.

## 8. Create the frontend Deployment

A Deployment manages the desired state of an application workload. It
creates and manages ReplicaSets; a ReplicaSet ensures that the desired
number of Pods exists.

We started with one frontend replica.

File: `frontend-deployment.yaml`

``` yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: gamehub-frontend
  namespace: gamehub
spec:
  replicas: 1
  selector:
    matchLabels:
      app: gamehub-frontend
  template:
    metadata:
      labels:
        app: gamehub-frontend
    spec:
      containers:
        - name: frontend
          image: lakshmisaranya/gamehub:frontend-v1
          ports:
            - containerPort: 80
```

Apply from the project root:

``` powershell
kubectl apply -f frontend-deployment.yaml
```

Output:

``` text
deployment.apps/gamehub-frontend created
```

### 8.1 Why does Deployment use `apps/v1`?

Deployment belongs to the `apps` API group, and its version is `v1`;
therefore, the YAML uses `apps/v1`.

- **Namespace**
  - **API version:** `v1`
- **Pod**
  - **API version:** `v1`
- **Service**
  - **API version:** `v1`
- **Deployment**
  - **API version:** `apps/v1`
- **ReplicaSet**
  - **API version:** `apps/v1`
- **Job**
  - **API version:** `batch/v1`

### 8.2 Important selector and label relationship

These values must match:

``` yaml
selector:
  matchLabels:
    app: gamehub-frontend
```

``` yaml
template:
  metadata:
    labels:
      app: gamehub-frontend
```

The Deployment selector identifies the Pods it manages. The Pod template
supplies the labels those Pods receive.

`replicas: 1` means the Deployment should maintain one Pod, not one
ReplicaSet. A Deployment may manage multiple ReplicaSets during a
rolling update, but the replica count describes the desired number of
Pods.

`containerPort: 80` documents the port the container is expected to
listen on. It does not, by itself, expose the application outside the
Pod. A Service is a separate Kubernetes resource.

### Understanding Rolling Updates in Kubernetes

#### 1. What is a Rolling Update?

A **Rolling Update** is a Deployment strategy in which Kubernetes gradually replaces old Pods with new Pods when we update an application.

Instead of deleting all old Pods at once and creating new ones, Kubernetes replaces them gradually.

This helps minimize application downtime during an update.

**Important:** A Rolling Update is the default update strategy for Kubernetes Deployments.

#### 2. Understanding Rolling Update with an example

Suppose our GameHub frontend Deployment currently has three replicas:

```yaml
spec:
  replicas: 3
```

This means we want three frontend Pods running.

Imagine all three Pods are running version 1 of our application (`frontend-v1`).

**Before the update:**

```text
Pod 1  → frontend-v1
Pod 2  → frontend-v1
Pod 3  → frontend-v1
```

Now, suppose we update our Deployment to use `frontend-v2`.

**During the Rolling Update:**

Kubernetes gradually creates new Pods using `frontend-v2` and replaces the old Pods running `frontend-v1`.

For example:

```text
Pod 1  → frontend-v2  (New)
Pod 2  → frontend-v1  (Old)
Pod 3  → frontend-v1  (Old)
```

As the update progresses:

```text
Pod 1  → frontend-v2  (New)
Pod 2  → frontend-v2  (New)
Pod 3  → frontend-v1  (Old)
```

**After the update:**

```text
Pod 1  → frontend-v2
Pod 2  → frontend-v2
Pod 3  → frontend-v2
```

Now all three Pods are running the new version.

**Note:** This is a simplified illustration. The exact replacement sequence depends on the Deployment's rolling update settings and Pod readiness.

#### 3. How does Kubernetes know how to perform a Rolling Update?

A Deployment uses a strategy to determine how Pods should be replaced.

Example:

```yaml
spec:
  replicas: 3

  strategy:
    type: RollingUpdate
    rollingUpdate:
      maxSurge: 1
      maxUnavailable: 1
```

Let's understand these settings:

**`type: RollingUpdate`**

Specifies that Kubernetes should gradually replace old Pods with new Pods.

**`maxSurge: 1`**

Allows Kubernetes to temporarily create one extra Pod beyond the desired replica count.

For example, if we want three replicas, Kubernetes can temporarily have up to four Pods during the update.

**`maxUnavailable: 1`**

Allows at most one Pod to be unavailable during the update.

For example, if we want three replicas, Kubernetes aims to keep at least two Pods available during the update.

**Important:** If we don't specify a Deployment strategy, Kubernetes uses `RollingUpdate` by default. The default values for `maxSurge` and `maxUnavailable` are 25% each.

#### 4. When does a Rolling Update happen?

Let's consider our GameHub frontend Deployment.

Initially, our Deployment uses:

```yaml
image: lakshmisaranya/gamehub:frontend-v1
```

Suppose we build and push a new version of our frontend image to Docker Hub.

We then update the Deployment to use:

```yaml
image: lakshmisaranya/gamehub:frontend-v2
```

Kubernetes detects that the Pod template has changed.

It creates a new ReplicaSet for the updated version and gradually replaces the Pods managed by the old ReplicaSet.

This is how a Rolling Update happens.

#### 5. How can we check the Rolling Update status?

We can use the following command to check whether the Deployment update has completed:

```powershell
kubectl rollout status deployment/gamehub-frontend -n gamehub
```

To view the Deployment's rollout history:

```powershell
kubectl rollout history deployment/gamehub-frontend -n gamehub
```

#### 6. Does Rolling Update guarantee zero downtime?

No. A Rolling Update helps minimize downtime, but it does not guarantee zero downtime in every situation.

For example:

- The new application version might be unhealthy.
- A readiness probe might be missing or incorrectly configured.
- There might not be enough resources to run the new Pods.

Kubernetes uses readiness probes, when configured, to determine whether a new Pod is ready to receive traffic.

#### 7. Key Takeaways

- Rolling Update gradually replaces old Pods with new Pods.
- It avoids deleting all old Pods at once.
- It is the default update strategy for Kubernetes Deployments.
- A Deployment creates a new ReplicaSet when its Pod template changes.
- The new ReplicaSet manages the updated Pods, while the old ReplicaSet can retain the previous version's rollout information.
- Rolling Updates help minimize application downtime, but do not guarantee zero downtime.

## 9. Check the Deployment and Pod

We checked the Deployment:

``` powershell
kubectl get deployments -n gamehub
```

Initial output:

``` text
NAME               READY   UP-TO-DATE   AVAILABLE   AGE
gamehub-frontend   0/1     1            0           33s
```

- **`READY`**
  - **Value:** `0/1`
  - **Meaning:** Zero Pods ready out of one desired replica
- **`UP-TO-DATE`**
  - **Value:** `1`
  - **Meaning:** One Pod created from the latest Deployment configuration
- **`AVAILABLE`**
  - **Value:** `0`
  - **Meaning:** No Pod available to serve traffic
- **`AGE`**
  - **Value:** `33s`
  - **Meaning:** Approximate age at the time of the check

Then we checked Pods:

``` powershell
kubectl get pods -n gamehub
```

Output at that moment:

``` text
NAME                               READY   STATUS    RESTARTS      AGE
gamehub-frontend-9c85bb695-ld2nk   1/1     Running   3 (29s ago)   76s
```

The container was running at that instant, but it had restarted three
times. `Running` alone did not prove the container was healthy.

## 10. Troubleshoot the frontend container restarts

We inspected the Pod:

``` powershell
kubectl describe pod gamehub-frontend-9c85bb695-ld2nk -n gamehub
```

Important details:

``` text
Image:          lakshmisaranya/gamehub:frontend-v1
State:          Terminated
Reason:         Error
Exit Code:      1
Last State:     Terminated
Reason:         Error
Exit Code:      1
Restart Count:  3
```

Events showed that the Pod was scheduled, the image was pulled, and the
container was created and started. Later, Kubernetes reported:

``` text
Back-off restarting failed container frontend
```

### 10.1 What this established

- Kubernetes scheduled the Pod onto the Minikube node.
- Kubernetes successfully pulled the frontend image from Docker Hub.
- The container was created and started.
- The container process then exited with error code `1`.
- Kubernetes attempted to restart it. Repeated failures led to a restart
  back-off delay.

Therefore, this was not an image-pull failure.

### 10.2 Read logs from the previous container instance

Because the container had restarted, we used `--previous` to read logs
from the last terminated instance:

``` powershell
kubectl logs gamehub-frontend-9c85bb695-ld2nk -n gamehub --previous
```

Important log lines:

``` text
Configuration complete; ready for start up
2026/10/30 08:04:28 [emerg] 1#1: host not found in upstream "auth-service" in /etc/nginx/conf.d/default.conf:12
nginx: [emerg] 1#1: host not found in upstream "auth-service" in /etc/nginx/conf.d/default.conf:12
```

### 10.3 Root cause identified

The frontend image runs Nginx. Its Nginx configuration refers to the
backend upstream hostname `auth-service`.

At this point:

- The `gamehub` namespace existed.
- The frontend Deployment and Pod had been created.
- We had **not** deployed the auth-service workload or created its
  Kubernetes Service.
- We had **not** deployed the game-service workload or created its
  Kubernetes Service.

The frontend’s Nginx configuration expects backend names that are not
yet resolvable in the Kubernetes environment. Nginx reports
`host not found in upstream "auth-service"` and exits. That causes the
container restart loop.

This is different from an image-pull problem: the image was pulled
successfully, but the application process could not complete startup
with the current upstream configuration.

### 10.4 How this will be addressed

We need to deploy the backend components and create Kubernetes Services
with DNS names that the frontend can resolve. A Kubernetes Service
provides a stable network endpoint and DNS name for the Pods selected by
that Service.

Intended high-level request path:

``` text
Browser / user
      |
      v
Frontend Service (to be created)
      |
      v
Frontend Pod (Nginx + React)
      |
      +---- /api/auth/* ----> auth-service (Kubernetes Service)
      |                           |
      |                           v

      +---- /api/game/* ----> game-service (Kubernetes Service)
                                  |
                                  v
                              Game Pod
```

The dependency causing the Nginx startup failure has been identified. We
have **not yet applied a fix or verified that the frontend starts
successfully**. The next steps must account for the backend workloads,
Services, and DNS names.

**10.5 Why does each application component need a Kubernetes
Service?**

A Deployment manages Pods, but it does not provide a stable network
endpoint for communication between application components.

A Kubernetes Service provides a stable endpoint and DNS name for
accessing the Pods selected by its selector.

Our GameHub application has three application components:

- Frontend
- Auth service
- Game service

Therefore, we need a Deployment and a Service for each component.

**10.6 Planned Kubernetes resources**

- **Frontend**
  - **Deployment:** `gamehub-frontend`
  - **Service:** `frontend-service`
  - **Planned Service type:** NodePort
- **Auth**
  - **Deployment:** `auth-deployment`
  - **Service:** `auth-service`
  - **Planned Service type:** ClusterIP
- **Game**
  - **Deployment:** `game-deployment`
  - **Service:** `game-service`
  - **Planned Service type:** ClusterIP

**Why these Service types?**

- **NodePort for Frontend:** The frontend needs to be accessible from
  outside the Kubernetes cluster through a browser.
- **ClusterIP for Auth and Game:** These services are accessed
  internally by the frontend. They do not need direct external access in
  our current architecture.

**10.7 Frontend Service configuration**

File: `frontend-service.yaml`

``` yaml
apiVersion: v1
kind: Service
metadata:
  name: frontend-service
  namespace: gamehub
spec:
  type: NodePort
  selector:
    app: gamehub-frontend
  ports:
    - protocol: TCP
      port: 80
      targetPort: 80
```
We use command to open the frontend application:
```
minikube service frontend-service -n gamehub -p gamehub-cluster

```
Traffic Flow:
``` text
Browser
   |
   v
NodePort
   |
   v
frontend-service (Port 80)
   |
   v
Frontend Pod (TargetPort 80)
   |
   v
Nginx
```

**10.8 Auth Service configuration — planned**

File: `auth-service.yaml`

``` yaml
apiVersion: v1
kind: Service
metadata:
  name: auth-service
  namespace: gamehub
spec:
  type: ClusterIP
  selector:
    app: auth-service
  ports:
    - protocol: TCP
      port: 8080
      targetPort: 8080
```

The frontend’s Nginx configuration expects the hostname `auth-service`
on port `8080`.

The Service name is important because Kubernetes DNS uses it to resolve
the backend endpoint.

**10.9 Game Service configuration — completed**

File: `game-service.yaml`

``` yaml
apiVersion: v1
kind: Service
metadata:
  name: game-service
  namespace: gamehub
spec:
  type: ClusterIP
  selector:
    app: game-service
  ports:
    - protocol: TCP
      port: 8081
      targetPort: 8081
```

The frontend’s Nginx configuration expects the hostname `game-service`
on port `8081`.

**10.10 Important selector and label relationship**

A Service uses its selector to identify the Pods to which it should
forward traffic.

For example, the Auth Service uses:

``` yaml
selector:
  app: auth-service
```

The Auth Deployment’s Pod template must therefore contain the matching
label:

``` yaml
template:
  metadata:
    labels:
      app: auth-service
```

The same principle applies to the frontend and game components.

**10.11 Planned application communication**

``` text
                    Browser
                       |
                       v
              frontend-service
                  (NodePort)
                       |
                       v
                 Frontend Pod
                    (Nginx)
                       |
             +---------+---------+
             |                   |
             v                   v
        auth-service        game-service
         (ClusterIP)         (ClusterIP)
             |                   |
             v                   v
          Auth Pod            Game Pod
             |                   |
             +---------+---------+
                       |
                       v
                PostgreSQL
                (completed)
```
## 11. Current progress checkpoint

**Last reviewed:** 06 November 2026

### 11.1 Completed deployment tasks

- **GameHub source inspected**
  - **Status:** Completed
- **Docker images rebuilt**
  - **Status:** Completed
- **Docker Hub public repository created**
  - **Status:** Completed
- **Frontend, Auth and Game images tagged and pushed**
  - **Status:** Completed
- **Minikube `gamehub-cluster` selected**
  - **Status:** Completed
- **`gamehub` namespace created**
  - **Status:** Completed
- **Frontend Deployment created and applied**
  - **Status:** Completed
- **Frontend image pulled and container started**
  - **Status:** Completed
- **Frontend Service created**
  - **Status:** Completed
- **Frontend opened successfully in the browser**
  - **Status:** Completed
- **Auth Deployment and Service created**
  - **Status:** Completed; current Pod observed Running
- **Game Deployment and Service created**
  - **Status:** Completed; current Pod observed Running
- **PostgreSQL Secret created**
  - **Status:** Completed
- **PostgreSQL ConfigMap and initialization SQL configured**
  - **Status:** Completed
- **PostgreSQL PVC created**
  - **Status:** Created; confirm its current `Bound` status
- **PostgreSQL Deployment and Service created**
  - **Status:** Completed; PostgreSQL Pod observed Running
- **PostgreSQL persistent storage mounted in the Deployment**
  - **Status:** Configured
- **PostgreSQL startup, readiness and liveness probes**
  - **Status:** Configured
- **Auth and Game Deployments configured to consume database settings from the Secret**
  - **Status:** Completed
- **Kubernetes Service selectors and Deployment Pod labels**
  - **Status:** Configured to match
- **Rolling Update concept**
  - **Status:** Learned
- **PV, PVC and StorageClass concepts**
  - **Status:** Learned

### 11.2 Remaining deployment verification tasks

- **Confirm PostgreSQL PVC binding**
  - **Status:** Pending verification
  - **Check:** PVC should show `Bound`.
- **Verify Auth and Game connectivity to PostgreSQL**
  - **Status:** Pending end-to-end verification
- **Test Auth workflows**
  - **Status:** Pending
  - **Examples:** User registration and login.
- **Test Game workflows**
  - **Status:** Pending
  - **Examples:** Game statistics and score operations.
- **Verify frontend-to-backend API communication**
  - **Status:** Pending
- **Perform complete manual GameHub application testing**
  - **Status:** Pending
- **Investigate whether the frontend's historical restart count is still increasing**
  - **Status:** Follow-up verification required; current container was observed Running and Ready. The earlier Nginx upstream DNS startup issue was resolved after the backend Services were created.

### 11.3 Verification commands

Confirm storage:

```powershell
kubectl get pvc -n gamehub
kubectl get pv
kubectl get storageclass
```

Check all application resources:

```powershell
kubectl get all -n gamehub
kubectl get pods -n gamehub
kubectl get endpointslices -n gamehub
```

Check Deployment health:

```powershell
kubectl rollout status deployment/gamehub-frontend -n gamehub
kubectl rollout status deployment/auth-deployment -n gamehub
kubectl rollout status deployment/game-deployment -n gamehub
kubectl rollout status deployment/postgres -n gamehub
```

Inspect database and application logs:

```powershell
kubectl logs deployment/postgres -n gamehub
kubectl logs deployment/auth-deployment -n gamehub
kubectl logs deployment/game-deployment -n gamehub
```

### 11.4 Current checkpoint

The Frontend, Auth, Game and PostgreSQL workloads have been deployed. Their Kubernetes Services have been created, and the frontend has been opened successfully in the browser.

The database configuration, Secret, ConfigMap and persistent storage integration have also been set up.

**The next priority is to verify storage binding and actual application functionality, especially communication between the frontend, backend services and PostgreSQL.**

Performance and resilience testing with k6 remains a separate future phase.
## 12. Future Phase: Performance and Resilience Testing with k6

> **Status: Planned — To be started after completing the GameHub
> deployment.**
>
> This phase was suggested by my manager. The objective is to test how
> GameHub behaves under different traffic conditions and observe how
> Kubernetes handles application failures and recovery.

### 12.1 Objective

Use k6 to generate HTTP traffic against GameHub and observe how the
application and Kubernetes cluster behave under different workloads.

The goal is to understand:

- How does GameHub behave when multiple users access it simultaneously?
- Can the application handle increasing traffic?
- Do Pods restart or crash under heavy load?
- If a Pod fails while k6 continues sending requests, does Kubernetes
  recover automatically?
- Can the application continue serving requests while a failed Pod is
  replaced?
- Can we detect resource pressure or potential failures before the
  application becomes unavailable?
- Can we update the application without interrupting ongoing traffic?

### 12.2 When should this phase begin?

Performance testing should begin only after the application deployment has been verified.

The deployment tasks have been completed:

1. Auth service and Kubernetes Service deployed — **Completed**.
2. Game service and Kubernetes Service deployed — **Completed**.
3. PostgreSQL deployed with Secret, ConfigMap and persistent storage configuration — **Completed**.
4. Frontend Service created and GameHub opened in the browser — **Completed**.

The following verification tasks remain:

5. Confirm that the PostgreSQL PVC is Bound.
6. Verify communication between Auth, Game and PostgreSQL.
7. Test registration, login, game statistics and score-related workflows.
8. Verify frontend-to-backend API communication.
9. Perform manual application testing and establish a healthy baseline.

Only after these verification tasks are completed should we begin performance and resilience testing with k6.

This ensures that performance testing measures application behaviour rather than failures caused by missing dependencies or incomplete configuration.

### 12.3 Planned k6 test scenarios

Create separate k6 scripts for the following scenarios.

- **Baseline test**
  - **Purpose:** Understand application behaviour under normal traffic.
- **Load test**
  - **Purpose:** Check whether the application handles its expected workload.
- **Stress test**
  - **Purpose:** Gradually increase traffic beyond expected capacity and identify the breaking point.
- **Spike test**
  - **Purpose:** Observe how the application responds to a sudden increase in traffic.
- **Soak test**
  - **Purpose:** Run continuous traffic for an extended period and identify gradual degradation.
- **Pod failure test**
  - **Purpose:** Delete a Pod while k6 continues sending requests and observe recovery.
- **Rolling update test**
  - **Purpose:** Update a Deployment while traffic continues and observe whether requests are interrupted.
- **Scaling test**
  - **Purpose:** Increase replicas manually or through HPA and observe application behaviour.

### 12.4 Kubernetes concepts to investigate

Before performing resilience tests, understand and evaluate these
Kubernetes features:

- **Readiness probes**
  - **Purpose:** Determine whether a Pod is ready to receive traffic.
- **Liveness probes**
  - **Purpose:** Detect an unhealthy container and restart it when necessary.
- **Resource requests**
  - **Purpose:** Specify the resources a container needs for scheduling.
- **Resource limits**
  - **Purpose:** Set CPU and memory limits for containers.
- **Multiple replicas**
  - **Purpose:** Maintain multiple application Pods.
- **Kubernetes Services**
  - **Purpose:** Provide stable endpoints and route traffic to eligible Pods.
- **Rolling updates**
  - **Purpose:** Replace application Pods gradually during updates.
- **Horizontal Pod Autoscaler (HPA)**
  - **Purpose:** Automatically adjust replica counts based on configured metrics.

### 12.5 What should be monitored?

During testing, observe both k6 results and Kubernetes behaviour.

**k6 observations:** - Number of requests. - Number of virtual users. -
Request success and failure rates. - Response times. - Failed checks and
HTTP errors. - Recovery time after a failure.

**Kubernetes observations:** - Pod status and readiness. - Pod restart
counts. - Desired and available replicas. - CPU and memory usage. - Pod
events. - Container logs. - Whether replacement Pods are created and
become Ready.

Useful commands:

``` powershell
kubectl get pods -n gamehub -w
kubectl get deployments -n gamehub
kubectl get events -n gamehub --sort-by=.metadata.creationTimestamp
kubectl describe pod <pod-name> -n gamehub
kubectl logs <pod-name> -n gamehub
```

For resource usage, investigate:

``` powershell
kubectl top pods -n gamehub
kubectl top nodes
```

These commands require a working metrics source, such as the Minikube
metrics-server addon.

### 12.6 Important considerations

- Our current Minikube cluster has only one node. We can test Pod
  failures and replacement, but not proper recovery from an entire node
  failure.
- With one replica, deleting the only application Pod can temporarily
  interrupt service.
- Multiple replicas behind a Service, together with readiness probes and
  an appropriate rolling update strategy, help maintain availability.
- Multiple replicas alone do not guarantee zero downtime.
- k6 HTTP tests exercise the endpoints we configure. They do not
  automatically reproduce every browser interaction.
- Monitoring and alerts need to be configured separately; Kubernetes
  does not automatically provide advance warnings for every potential
  failure.
- All stress and failure tests should be performed in the local test
  environment with controlled traffic.

### 12.7 Planned execution order

1.  Complete the GameHub deployment.
2.  Verify application functionality.
3.  Establish a healthy baseline.
4.  Configure readiness and liveness probes.
5.  Configure appropriate resource requests and limits.
6.  Introduce multiple replicas and understand rolling updates.
7.  Make CPU and memory metrics available.
8.  Create and execute separate k6 scripts.
9.  Perform Pod failure and rolling update tests while k6 traffic
    continues.
10. Investigate scaling and HPA.
11. Record results, failures, recovery time, and observations.

**Current priority:** Continue with the remaining GameHub deployment
tasks. Performance and resilience testing is an important planned phase,
but it should not interrupt the current deployment workflow.

## 13. Commands used so far

Run these from the GameHub project root unless otherwise stated.

### Docker image preparation

``` powershell
docker compose build
```

### Minikube and Kubernetes inspection

``` powershell
minikube profile list
kubectl config current-context
kubectl get nodes -o wide
kubectl api-resources
kubectl api-versions
```

### Namespace and frontend Deployment

``` powershell
kubectl apply -f namespace.yaml
kubectl get namespaces
kubectl get all -n gamehub
kubectl apply -f frontend-deployment.yaml
kubectl get deployments -n gamehub
kubectl get pods -n gamehub
kubectl describe pod gamehub-frontend-9c85bb695-ld2nk -n gamehub
kubectl logs gamehub-frontend-9c85bb695-ld2nk -n gamehub --previous
```

## 14. Concepts learned in this stage

1.  A Kubernetes Namespace groups and scopes resources.
2.  `apiVersion` identifies the API group and version used for a
    resource.
3.  Namespace and Service use the core API version `v1`; Deployment uses
    `apps/v1`.
4.  `kubectl api-resources` lists resources and the API version each
    resource uses.
5.  `kubectl api-versions` lists API group/version combinations
    available in the cluster.
6.  A Minikube profile name and Kubernetes node name are different
    concepts, even if their values match.
7.  A Deployment manages ReplicaSets, and ReplicaSets maintain the
    desired number of Pods.
8.  `replicas: 1` means one desired Pod, not one ReplicaSet.
9.  A Pod can be `Running` at a moment in time and still have restarted
    repeatedly.
10. `kubectl describe pod` helps inspect container state, restart count,
    scheduling, and events.
11. `kubectl logs --previous` retrieves logs from the previous
    terminated container instance.
12. A successful image pull does not guarantee that the application
    inside the container can start.
13. Kubernetes Services provide stable endpoints and DNS names for
    accessing Pods.
14. Docker Compose service-name DNS and Kubernetes Service DNS are
    separate networking environments.
16. A PersistentVolume (PV) represents storage available to the Kubernetes cluster and is cluster-scoped.

17. A PersistentVolumeClaim (PVC) is a namespaced request for persistent storage.

18. A PVC can bind to an existing suitable PV or trigger dynamic provisioning through a StorageClass.

19. A StorageClass defines how storage should be dynamically provisioned.

20. Kubernetes does not automatically combine multiple independent PVs to satisfy one PVC.

21. The storage provisioner and backend are responsible for allocating the actual storage.

22. Local storage is tied to a node, whereas remote storage can provide access across nodes depending on the storage system and its configuration.

23. ConfigMaps and Secrets are configuration resources, not types of PersistentVolumes.

24. A Deployment connects a PVC to a container through `volumes` and `volumeMounts`.

25. PostgreSQL uses `/var/lib/postgresql/data` as its persistent data directory in our GameHub configuration.

26. Persistent storage helps preserve database data across Pod replacement, but data retention also depends on the PV reclaim policy and storage backend.

27. A PVC being created does not by itself prove that storage has been provisioned successfully; its status should be checked for `Bound`.

------------------------------------------------------------------------

**Learning checkpoint:** The backend and database workloads have since
been deployed. Continue with Section 15 for the later steps and current
verification status. The original sections above preserve the earlier
troubleshooting timeline; where an earlier status says a resource was
still planned, Section 15 records the later deployment.

------------------------------------------------------------------------

## 15. Later deployment work: Auth, Game, PostgreSQL, and application access

> **Update recorded on 05 November 2026.** This section continues from
> the earlier frontend-only checkpoint. It records the later deployment
> steps and the state observed after those steps.

### 15.1 Confirm the correct Kubernetes context

Before applying resources, we confirmed that kubectl was targeting the
GameHub Minikube cluster:

``` powershell
kubectl config current-context
```

Output:

``` text
gamehub-cluster
```

This matters because each Minikube profile is a separate Kubernetes
cluster. Namespaces and resources in one profile are not automatically
present in another profile.

### 15.2 Deploy the Auth and Game workloads

The Auth and Game Deployments were created in the existing `gamehub`
namespace, using the images already pushed to Docker Hub:

- **Auth**
  - **Deployment:** `auth-deployment`
  - **Image:** `lakshmisaranya/gamehub:auth-v1`
  - **Container port:** 8080
- **Game**
  - **Deployment:** `game-deployment`
  - **Image:** `lakshmisaranya/gamehub:game-v1`
  - **Container port:** 8081

The Pod template labels used by the corresponding Services must match
their selectors:

- **`auth-deployment`**
  - **Pod label:** `app: auth-service`
- **`game-deployment`**
  - **Pod label:** `app: game-service`

The Auth and Game Service resources were created with these names:

- `auth-service` — ClusterIP, port 8080, targetPort 8080.
- `game-service` — ClusterIP, port 8081, targetPort 8081.

These Service names match the upstream hostnames expected by the
frontend Nginx configuration.

**Important:** A Deployment creates and manages Pods through
ReplicaSets. A Service is a separate resource; it selects Pods using
labels and provides a stable network endpoint and DNS name.

### 15.3 Create persistent storage for PostgreSQL

File: `postgres-pvc.yaml`

``` yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: postgres-pvc
  namespace: gamehub
spec:
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: 1Gi
```

Apply:

``` powershell
kubectl apply -f postgres-pvc.yaml
```

The PersistentVolumeClaim (PVC) requests storage for the database. The
PostgreSQL Deployment mounts the claim into the container’s data
directory.

The requested size is 1 GiB. The actual PVC binding status should be
checked with:

``` powershell
kubectl get pvc -n gamehub
```

Expected status for a successfully provisioned claim:

``` text
Bound
```

A PVC is a request for storage. It is not itself the database Pod or the
database Service.

### 15.3.1 Understanding Kubernetes Storage: PV, PVC and StorageClass

Kubernetes uses three important concepts to manage persistent storage:

1. PersistentVolume (PV)
2. PersistentVolumeClaim (PVC)
3. StorageClass

#### 1. PersistentVolume (PV)

A PersistentVolume represents a piece of storage made available to a Kubernetes cluster.

- It is a cluster-scoped resource, not a namespaced resource.
- It represents storage provided by a local disk, network storage system, cloud storage service, or another supported storage backend.
- It has a capacity, access mode and other storage properties.
- It exists independently of an individual Pod.

A PV is the storage resource. It is not the same as the container's writable filesystem.

#### 2. PersistentVolumeClaim (PVC)

A PersistentVolumeClaim is an application's request for persistent storage.

For example, our PostgreSQL PVC requests 1 GiB:

```yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: postgres-pvc
  namespace: gamehub
spec:
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: 1Gi
```

Important points:

- A PVC is a namespaced resource.
- It specifies the required storage capacity and access mode.
- Kubernetes tries to bind it to a suitable existing PV or provision a new PV through a StorageClass.
- A PVC does not always create a new PV. It can use an existing suitable PV.
- A PVC is a request for storage, not the actual storage itself.

#### 3. StorageClass

A StorageClass describes how storage should be dynamically provisioned.

Without dynamic provisioning, an administrator can manually create a PV first. A matching PVC can then bind to that PV.

With dynamic provisioning:

1. An application creates a PVC.
2. The PVC specifies a StorageClass, explicitly or through the cluster's default StorageClass.
3. The StorageClass identifies the provisioner and storage parameters.
4. The provisioner requests or creates storage from the storage backend.
5. Kubernetes creates a corresponding PV and binds it to the PVC.

This reduces the need for administrators to manually create every PV.

#### 4. How PV, PVC and StorageClass work together

```text
                  Application
                       |
                       v
                 PVC (request)
                       |
                       v
                 StorageClass
                       |
                       v
                  Provisioner
                       |
                       v
                Storage Backend
                       |
                       v
                 PV (storage)
                       |
                       v
                 Bound to PVC
                       |
                       v
                Mounted in Pod
```

The StorageClass is involved in dynamic provisioning. It is not itself the storage volume.

#### 5. What happens when storage is available in separate chunks?

Imagine a storage backend has three independent available volumes:

| Available volume | Capacity |
|---|---:|
| Disk A | 2 Gi |
| Disk B | 1 Gi |
| Disk C | 2 Gi |
| **Total** | **5 Gi** |

An application requests a single PVC of 5 Gi.

Kubernetes does not automatically combine these three independent PVs into one 5 Gi PV.

For static provisioning, Kubernetes looks for one suitable PV that can satisfy the claim. If no suitable PV exists, the PVC remains Pending.

For dynamic provisioning, the provisioner asks the storage backend to create a 5 Gi volume. Whether the backend can do this depends on its available capacity and capabilities.

If the backend manages multiple physical disks as one storage pool, it may allocate the requested volume across those disks internally. That allocation is handled by the storage backend, not by Kubernetes combining separate PVs.

**Key distinction:** Kubernetes does not combine multiple independent PVs to satisfy one PVC.

#### 6. Local storage and remote storage

Storage can be provided in different ways:

- **Local storage:** Uses storage physically attached to the Kubernetes node.
- **Remote storage:** Uses storage provided over a network, such as a cloud disk or network storage system.

Local storage can survive a Pod restart, but it is tied to its node. If that node becomes unavailable, the volume may not be accessible.

Remote storage can make data accessible from different nodes, depending on the storage system and its access mode. It does not automatically guarantee backup or high availability.

The right choice depends on the application's availability, performance and durability requirements.

#### 7. ConfigMaps and Secrets are different from PVs and PVCs

ConfigMaps and Secrets are Kubernetes configuration resources. They are not types of PersistentVolumes.

They can be mounted into containers as files or exposed as environment variables.

| Resource | Purpose |
|---|---|
| PV | Represents persistent storage. |
| PVC | Requests persistent storage. |
| StorageClass | Defines dynamic storage provisioning. |
| ConfigMap | Supplies non-sensitive configuration data. |
| Secret | Supplies sensitive configuration data, such as credentials. |

ConfigMaps and Secrets are not substitutes for persistent database storage.

#### 8. How this works in our GameHub project

Our PostgreSQL PVC requests 1 Gi of storage:

```yaml
resources:
  requests:
    storage: 1Gi
```

The PostgreSQL Deployment references that claim:

```yaml
volumes:
  - name: postgres-storage
    persistentVolumeClaim:
      claimName: postgres-pvc
```

It then mounts the volume inside the PostgreSQL container:

```yaml
volumeMounts:
  - name: postgres-storage
    mountPath: /var/lib/postgresql/data
```

The connection is:

```text
postgres-pvc
     |
     v
postgres-storage volume
     |
     v
PostgreSQL container
     |
     v
/var/lib/postgresql/data
```

In our Minikube cluster, the default StorageClass can dynamically provision storage for this PVC.

We can inspect the storage resources using:

```powershell
kubectl get storageclass
kubectl get pvc -n gamehub
kubectl get pv
```

A successfully provisioned PVC should normally show the status `Bound`.

**Important:** Deleting a Pod does not normally delete its PVC. However, data retention also depends on the PV reclaim policy, the storage backend and whether the PVC itself is deleted. Persistent storage is not a replacement for backups.

#### 9. Key takeaways

- PV represents storage; PVC requests storage.
- PV is cluster-scoped; PVC is namespaced.
- A PVC can bind to an existing PV or trigger dynamic provisioning.
- StorageClass defines how dynamic provisioning happens.
- Kubernetes does not combine separate PVs to satisfy one PVC.
- The storage backend is responsible for the actual allocation.
- Local storage is tied to a node; remote storage can provide access across nodes depending on its configuration.
- ConfigMaps and Secrets provide configuration, not persistent database storage.
- Our PostgreSQL Deployment uses `postgres-pvc` to store database files outside the container's writable layer.

### 15.4 Store PostgreSQL settings in a Secret

File: `postgres-secret.yaml`

``` yaml
apiVersion: v1
kind: Secret
metadata:
  name: gamehub-db-secret
  namespace: gamehub
type: Opaque
stringData:
  POSTGRES_USER: user
  POSTGRES_PASSWORD: password
  POSTGRES_DB: gamehub
  POSTGRES_HOST: postgres
```

Apply:

``` powershell
kubectl apply -f postgres-secret.yaml
```

The values match the local Docker Compose database settings recorded for
this project.

The PostgreSQL image uses `POSTGRES_USER`, `POSTGRES_PASSWORD`, and
`POSTGRES_DB` when initializing a new database data directory. The
application services also need the database connection settings.

**Security note:** These are the local development credentials used in
this project. Do not reuse this password in a production environment.
Kubernetes Secret values are not automatically encrypted merely because
they are stored as a Secret.

### 15.5 Create a ConfigMap from the existing `init.sql`

The project already has an `init.sql` file. We used that existing SQL
file rather than inventing new table definitions.

From the project root, first check that the file exists:

``` powershell
Test-Path .\init.sql
```

If it returns `True`, generate the ConfigMap manifest:

``` powershell
kubectl create configmap postgres-init --from-file=init.sql=.\init.sql -n gamehub --dry-run=client -o yaml | Out-File -FilePath .\postgres-configmap.yaml -Encoding utf8
```

Apply the generated manifest:

``` powershell
kubectl apply -f postgres-configmap.yaml
```

The ConfigMap makes the SQL file available to the PostgreSQL Pod. The
Deployment mounts it at:

``` text
/docker-entrypoint-initdb.d
```

The official PostgreSQL container image runs initialization scripts in
this directory when it initializes an empty database data directory.

**Important initialization behaviour:**

- On the first initialization of an empty data directory, the SQL script
  is executed.
- When the same database volume is reused after a Pod restart, the
  initialization script is not automatically executed again.
- Updating the ConfigMap does not make PostgreSQL rerun the
  initialization script against an already initialized database.

### 15.6 Deploy PostgreSQL

File: `postgres-deployment.yaml`

``` yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: postgres
  namespace: gamehub
spec:
  replicas: 1
  selector:
    matchLabels:
      app: postgres
  template:
    metadata:
      labels:
        app: postgres
    spec:
      containers:
        - name: postgres
          image: postgres:13
          ports:
            - containerPort: 5432
          env:
            - name: POSTGRES_USER
              valueFrom:
                secretKeyRef:
                  name: gamehub-db-secret
                  key: POSTGRES_USER
            - name: POSTGRES_PASSWORD
              valueFrom:
                secretKeyRef:
                  name: gamehub-db-secret
                  key: POSTGRES_PASSWORD
            - name: POSTGRES_DB
              valueFrom:
                secretKeyRef:
                  name: gamehub-db-secret
                  key: POSTGRES_DB
          volumeMounts:
            - name: postgres-storage
              mountPath: /var/lib/postgresql/data
            - name: postgres-init
              mountPath: /docker-entrypoint-initdb.d
              readOnly: true
          startupProbe:
            exec:
              command:
                - pg_isready
                - -U
                - user
                - -d
                - gamehub
            periodSeconds: 10
            failureThreshold: 30
          readinessProbe:
            exec:
              command:
                - pg_isready
                - -U
                - user
                - -d
                - gamehub
            periodSeconds: 5
          livenessProbe:
            exec:
              command:
                - pg_isready
                - -U
                - user
                - -d
                - gamehub
            periodSeconds: 10
            initialDelaySeconds: 30
      volumes:
        - name: postgres-storage
          persistentVolumeClaim:
            claimName: postgres-pvc
        - name: postgres-init
          configMap:
            name: postgres-init
```

Apply:

``` powershell
kubectl apply -f postgres-deployment.yaml
```

Wait for the Deployment rollout:

``` powershell
kubectl rollout status deployment/postgres -n gamehub --timeout=180s
```

Inspect the Pod and logs:

``` powershell
kubectl get pods -n gamehub
kubectl logs deployment/postgres -n gamehub
```

The `pg_isready` probes check whether PostgreSQL is accepting
connections. The startup probe allows time for the database to
initialize before Kubernetes begins relying on the liveness and
readiness probes.

### 15.7 Create the PostgreSQL Service

File: `postgres-service.yaml`

``` yaml
apiVersion: v1
kind: Service
metadata:
  name: postgres
  namespace: gamehub
spec:
  type: ClusterIP
  selector:
    app: postgres
  ports:
    - port: 5432
      targetPort: 5432
      protocol: TCP
```

Apply:

``` powershell
kubectl apply -f postgres-service.yaml
```

The Service name `postgres` is intentional. The Auth and Game services
use that hostname as their database host.

Within the same namespace, the application can use the short DNS name:

``` text
postgres
```

The fully qualified Service DNS name is:

``` text
postgres.gamehub.svc.cluster.local
```

The PostgreSQL Service is `ClusterIP` because the database is intended
to be accessed internally by application workloads, not directly from
the user’s browser.

### 15.8 Update Auth and Game with database environment variables

The database credentials and connection settings were added to the
existing Auth and Game Deployments from the Secret:

``` powershell
kubectl set env deployment/auth-deployment --from=secret/gamehub-db-secret -n gamehub
kubectl set env deployment/game-deployment --from=secret/gamehub-db-secret -n gamehub
```

These commands update the Pod templates of the Deployments. Kubernetes
creates new ReplicaSets and replaces the old Pods so that the new Pods
receive the updated environment variables.

Wait for each rollout:

``` powershell
kubectl rollout status deployment/auth-deployment -n gamehub
kubectl rollout status deployment/game-deployment -n gamehub
```

**Why did two ReplicaSets appear for Auth and Game?**

A Deployment keeps rollout history. When its Pod template changes—for
example, when environment variables are added—Kubernetes creates a new
ReplicaSet for the updated template.

The old ReplicaSet can remain visible with zero desired Pods, while the
new ReplicaSet owns the current Pod. This is expected and is useful for
rollout history and rollback.

Check the ReplicaSets:

``` powershell
kubectl get replicasets -n gamehub
```

### 15.9 Verify the deployed resources

The combined resource check used was:

``` powershell
kubectl get all -n gamehub
```

Observed output on 05 November 2026:

``` text
NAME                                   READY   STATUS    RESTARTS        AGE
pod/auth-deployment-9c58796cd-7qpj8    1/1     Running   0               72s
pod/game-deployment-857b759d55-gjnwt   1/1     Running   0               49s
pod/gamehub-frontend-9c85bb695-ld2nk   1/1     Running   33 (3h5m ago)   5d23h
pod/postgres-78998c8bcc-vdg8j          1/1     Running   0               3m19s

NAME                       TYPE        CLUSTER-IP       EXTERNAL-IP   PORT(S)
service/auth-service       ClusterIP   10.103.167.234   <none>        8080/TCP
service/frontend-service   NodePort    10.111.194.187   <none>        80:30193/TCP
service/game-service       ClusterIP   10.108.166.3     <none>        8081/TCP
service/postgres           ClusterIP   10.105.24.54     <none>        5432/TCP

NAME                               READY   UP-TO-DATE   AVAILABLE   AGE
deployment.apps/auth-deployment    1/1     1            1           3d1h
deployment.apps/game-deployment    1/1     1            1           3d1h
deployment.apps/gamehub-frontend   1/1     1            1           5d23h
deployment.apps/postgres           1/1     1            1           3m19s
```

This output showed that all four Deployments had one available replica
and all four Pods were `1/1 Running` at the time of the check.

**Interpretation of the frontend restart count:**

The frontend Pod showed 33 historical restarts, with the most recent
restart about 3 hours and 5 minutes earlier at the time of this output.
Its current state was `Running` and `1/1 Ready`. The restart count is
historical information; it does not mean the current container is
continuously failing. We still need to investigate why the earlier
restarts occurred and confirm the current logs remain clean.

The `kubectl get all` command does not display every Kubernetes resource
type. In particular, check the PVC separately:

``` powershell
kubectl get pvc -n gamehub
```

Check Service endpoints separately as well:

``` powershell
kubectl get endpointslices -n gamehub
```

### 15.10 Open the frontend in a browser

The frontend was opened using:

``` powershell
minikube service frontend-service -n gamehub -p gamehub-cluster
```

The browser opened the GameHub frontend, and the user reported that it
was working in the browser.

This confirms that the frontend was reachable through the NodePort
Service and that the browser could load the frontend. It does **not by
itself** prove that every Auth API, Game API, or database-backed
workflow works end to end.

### 15.11 DNS investigation for the earlier frontend Nginx error

The earlier frontend container logs showed:

``` text
host not found in upstream "auth-service"
```

This was the error from a previous terminated container instance. Later,
after the backend Services had been created, we checked DNS resolution
from the frontend Pod.

Command:

``` powershell
kubectl exec -it gamehub-frontend-9c85bb695-ld2nk -n gamehub -- nslookup auth-service.gamehub.svc.cluster.local
```

Observed output:

``` text
Server:  10.96.0.10
Address: 10.96.0.10:53

Name:    auth-service.gamehub.svc.cluster.local
Address: 10.103.167.234
```

This confirms that the Auth Service’s fully qualified DNS name resolved
from the frontend Pod at the time of this check.

The short-name lookup also eventually returned the correct Service name
and IP, although some search-domain probes printed `NXDOMAIN` and the
command exited with code 1. The fully qualified lookup above gave a
clean successful result.

**What we know and what we do not know:**

- The previous container’s Nginx startup failed because it could not
  resolve the `auth-service` upstream hostname at that time.
- The current frontend container is running, and the fully qualified
  Auth Service DNS name resolves now.
- We have not established the exact historical timing or proven that the
  Service was still being created at the moment of the earlier failure.
- A current DNS lookup does not prove TCP connectivity to port 8080 or
  successful Auth API behaviour.
- We still need to test connectivity and application workflows
  separately.

### 15.12 Current deployment architecture

The deployed resource relationships are now:

``` text
                         Browser
                            |
                            v
                  frontend-service
                     (NodePort)
                            |
                            v
                      Frontend Pod
                       (Nginx)
                       /       \
                      /         \
                     v           v
              auth-service   game-service
                (ClusterIP)   (ClusterIP)
                     |           |
                     v           v
                  Auth Pod    Game Pod
                      \          /
                       \        /
                        v      v
                     postgres
                    (ClusterIP)
                         |
                         v
                   PostgreSQL Pod
                         |
                         v
                    postgres-pvc
```

The Services provide stable network names/endpoints. Deployments manage
the application Pods. The PostgreSQL Pod mounts persistent storage
through the PVC.

### 15.13 What remains to verify

The deployment resources exist and the frontend opened in the browser,
but deployment verification is not yet complete.

- **Correct kubectl context**
  - **Status:** Confirmed: `gamehub-cluster`
- **Frontend Pod current state**
  - **Status:** `1/1 Running`; historical restarts need investigation
- **Auth Pod current state**
  - **Status:** `1/1 Running` in the observed output
- **Game Pod current state**
  - **Status:** `1/1 Running` in the observed output
- **PostgreSQL Pod current state**
  - **Status:** `1/1 Running` in the observed output
- **Frontend browser access**
  - **Status:** Opened successfully
- **Auth Service DNS from frontend Pod**
  - **Status:** Fully qualified DNS lookup succeeded
- **PVC is `Bound`**
  - **Status:** Check explicitly with `kubectl get pvc -n gamehub`
- **PostgreSQL Service has an endpoint**
  - **Status:** Check EndpointSlices
- **Auth and Game can connect to PostgreSQL**
  - **Status:** Not yet verified
- **Auth and Game API requests succeed**
  - **Status:** Not yet verified
- **End-to-end login and game workflows**
  - **Status:** Not yet verified
- **Reason for the frontend’s earlier restarts**
  - **Status:** Historical error identified; exact timing/cause not fully established

Do not describe the application as fully end-to-end verified until the
API and database-dependent workflows have been tested.

------------------------------------------------------------------------

## 16. Additional commands used during the later deployment

### Confirm current context

``` powershell
kubectl config current-context
```

### Apply database resources

``` powershell
kubectl apply -f postgres-pvc.yaml
kubectl apply -f postgres-secret.yaml
kubectl apply -f postgres-configmap.yaml
kubectl apply -f postgres-service.yaml
kubectl apply -f postgres-deployment.yaml
```

### Update application Deployments from the Secret

``` powershell
kubectl set env deployment/auth-deployment --from=secret/gamehub-db-secret -n gamehub
kubectl set env deployment/game-deployment --from=secret/gamehub-db-secret -n gamehub
```

### Check rollouts and resources

``` powershell
kubectl rollout status deployment/postgres -n gamehub
kubectl rollout status deployment/auth-deployment -n gamehub
kubectl rollout status deployment/game-deployment -n gamehub

kubectl get all -n gamehub
kubectl get pvc -n gamehub
kubectl get replicasets -n gamehub
kubectl get endpointslices -n gamehub
```

### Inspect logs and DNS

``` powershell
kubectl logs deployment/postgres -n gamehub
kubectl logs deployment/auth-deployment -n gamehub
kubectl logs deployment/game-deployment -n gamehub

kubectl logs gamehub-frontend-9c85bb695-ld2nk -n gamehub
kubectl logs gamehub-frontend-9c85bb695-ld2nk -n gamehub --previous

kubectl exec -it gamehub-frontend-9c85bb695-ld2nk -n gamehub -- nslookup auth-service.gamehub.svc.cluster.local
```

### Open the frontend

``` powershell
minikube service frontend-service -n gamehub -p gamehub-cluster
```

------------------------------------------------------------------------

## 17. Concepts added after the initial frontend deployment

1.  A PersistentVolumeClaim requests storage for a workload.
2.  A PostgreSQL Pod should not rely on its container’s writable layer
    for durable database data.
3.  A Secret can supply configuration values such as database
    credentials to a Pod.
4.  A ConfigMap can make a configuration or SQL file available to a
    container.
5.  The PostgreSQL image uses initialization variables when initializing
    a new data directory.
6.  PostgreSQL initialization scripts in `/docker-entrypoint-initdb.d`
    are not automatically rerun on every restart.
7.  A Deployment can mount a PVC and a ConfigMap as volumes.
8.  `pg_isready` can be used by startup, readiness, and liveness probes
    to check PostgreSQL availability.
9.  A PostgreSQL ClusterIP Service provides a stable in-cluster endpoint
    named `postgres`.
10. `kubectl set env --from=secret/...` imports Secret keys as
    environment variables into a Deployment’s Pod template.
11. Changing a Deployment’s Pod template creates a new ReplicaSet during
    the rollout.
12. Old ReplicaSets can remain with zero desired Pods to preserve
    rollout history.
13. `kubectl get all` is not a complete inventory of every Kubernetes
    resource type; PVCs and EndpointSlices should be checked separately.
14. A successful browser load of the frontend does not prove that
    backend APIs and database workflows work.
15. A successful DNS lookup confirms name resolution at that moment, not
    successful TCP or application-level communication.

**Next learning checkpoint:** Review the manifests and deployment
sequence in this document. Then verify the PVC, PostgreSQL endpoint,
Auth/Game database connectivity, and actual application workflows. Only
after those checks should we move on to performance testing with k6.
