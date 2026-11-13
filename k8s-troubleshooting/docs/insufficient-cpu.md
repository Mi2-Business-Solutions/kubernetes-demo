# Kubernetes Troubleshooting – Insufficient CPU

## 1. Objective

The objective of this experiment is to understand what happens when a Kubernetes Pod requests more CPU than the available CPU on a node.

We will:

1. Intentionally create an insufficient CPU scheduling issue.
2. Observe the Pod's status.
3. Identify the root cause using Kubernetes troubleshooting commands.
4. Fix the CPU resource configuration.
5. Understand how Kubernetes handles the Deployment update.
6. Verify that the Pod and Deployment recover successfully.

All resources are created inside the `k8s-troubleshooting` namespace to keep them separate from the GameHub application.

---

## 2. Understanding the problem

Kubernetes uses resource requests when deciding which node can run a Pod.

If a Pod requests more CPU than a node has available for scheduling, the Kubernetes scheduler cannot place that Pod on the node.

The Pod remains in the `Pending` state.

### Understanding CPU units

Kubernetes measures CPU resources in cores or millicores.

| CPU value | Meaning |
|---|---|
| `100m` | 0.1 CPU core |
| `500m` | 0.5 CPU core |
| `1000m` | 1 CPU core |
| `2000m` | 2 CPU cores |
| `13` | 13 CPU cores |

`m` stands for millicores. One CPU core is equivalent to 1000 millicores.

### Important concepts

| Term | Meaning |
|---|---|
| CPU capacity | Total CPU resources available on the node. |
| CPU allocatable | CPU resources Kubernetes makes available for Pods. |
| CPU request | Amount of CPU used by the scheduler when deciding where to place a Pod. |
| CPU limit | Maximum CPU consumption allowed for the container. |

**Important:** CPU requests and limits serve different purposes.

- Requests influence scheduling.
- Limits define runtime CPU ceilings. When a container tries to exceed its CPU limit, it is throttled rather than normally being terminated.

---

## 3. Deployment engineer's perspective

Before configuring CPU requests and limits for a real application, a deployment engineer should understand the application's CPU requirements.

Questions to investigate:

1. How much CPU does the application normally consume?
2. What is its expected CPU consumption under normal load?
3. What is its peak CPU consumption under heavy load?
4. Does the application perform CPU-intensive operations?
5. What CPU request and limit are appropriate for its workload?

The deployment engineer should work with the development team and use application profiling and load testing to understand CPU consumption.

Based on this information, appropriate requests and limits can be configured.

**Important distinction:**

Requests and limits are Kubernetes resource configuration values. They are not necessarily the application's exact minimum and maximum resource requirements.

We should not arbitrarily reduce CPU requests just to make a Pod run.

---

## 4. Inspecting the node before the experiment

Before creating the test workload, we inspected our Minikube node:

```powershell
kubectl describe node gamehub-cluster
```

Relevant observations:

| Resource | Value |
|---|---:|
| CPU capacity | 12 |
| CPU allocatable | 12 |

Our cluster has only one node, with 12 allocatable CPU cores.

To intentionally reproduce the scheduling issue, we decided to request 13 CPU cores.

This request exceeds the node's total allocatable CPU.

---

## 5. Creating the problem

Manifest location:

`manifests/insufficient-resources/insufficient-cpu.yaml`

We created a Deployment with the following resource configuration:

```yaml
resources:
  requests:
    cpu: "13"

  limits:
    cpu: "14"
```

### Why these values?

- CPU request of `13`: Exceeds the node's 12 allocatable CPU cores.
- CPU limit of `14`: Defines the container's maximum CPU consumption.

The container uses an Ubuntu image and runs a simple shell command:

```bash
while true; do echo CPU test running; sleep 10; done
```

This command prints a message every 10 seconds and continues running.

It does not intentionally consume 13 CPU cores.

Therefore, this experiment tests **CPU scheduling based on the request**, not actual CPU saturation or throttling.

### Validate the manifest

```powershell
kubectl apply --dry-run=client -f manifests/insufficient-resources/insufficient-cpu.yaml
```

Output:

```text
deployment.apps/insufficient-cpu created (dry run)
```

The client-side dry run validates the manifest without creating the Deployment or testing actual scheduling.

### Apply the manifest

```powershell
kubectl apply -f manifests/insufficient-resources/insufficient-cpu.yaml
```

Output:

```text
deployment.apps/insufficient-cpu created
```

---

## 6. Observing the issue

We checked the Pods inside our troubleshooting namespace:

```powershell
kubectl get pods -n k8s-troubleshooting
```

Output:

```text
NAME                                   READY   STATUS    RESTARTS        AGE
insufficient-cpu-57f79b7785-w5x8v      0/1     Pending   0               32s
insufficient-memory-6c5795d69b-nzr8w   1/1     Running   5 (5h53m ago)   22h
```

### Understanding the output

| Pod | Status | Explanation |
|---|---|---|
| `insufficient-cpu-57f79b7785-w5x8v` | Pending | CPU scheduling issue reproduced. |
| `insufficient-memory-6c5795d69b-nzr8w` | Running | Previous memory experiment remains healthy. |

Our memory experiment continues running independently.

The CPU Pod was created, but Kubernetes could not schedule it.

---

## 7. Troubleshooting the Pending Pod

We inspected the CPU Pod:

```powershell
kubectl describe pod insufficient-cpu-57f79b7785-w5x8v -n k8s-troubleshooting
```

### Important observations

**Node:**

```text
Node: <none>
Status: Pending
```

The Pod has not been assigned to a node.

**Conditions:**

```text
PodScheduled   False
```

The scheduler has not successfully scheduled the Pod.

**Resource configuration:**

```text
Limits:
  cpu: 14

Requests:
  cpu: 13
```

The Pod requests 13 CPU cores, which exceeds our node's 12 allocatable CPU cores.

### Most important: Events

```text
Warning  FailedScheduling  default-scheduler
0/1 nodes are available: 1 Insufficient cpu.
preemption: 0/1 nodes are available: 1 Preemption is not helpful for scheduling.
```

### Understanding the Events

| Observation | Explanation |
|---|---|
| `0/1 nodes are available` | Our cluster has one node, and zero nodes can accommodate the Pod. |
| `FailedScheduling` | The scheduling attempt failed. |
| `Insufficient cpu` | The node cannot satisfy the Pod's CPU request. |
| `Preemption is not helpful` | Removing other Pods would not solve a request that exceeds the node's total allocatable CPU. |

### Root cause

Our node has 12 allocatable CPU cores, but the test Pod requests 13 cores.

The scheduler cannot satisfy this request, so the Pod remains Pending.

---

## 8. Checking the Deployment

We inspected the Deployment:

```powershell
kubectl get deployment insufficient-cpu -n k8s-troubleshooting
```

Output:

```text
NAME               READY   UP-TO-DATE   AVAILABLE   AGE
insufficient-cpu   0/1     1            0           3m42s
```

### Understanding the columns

| Column | Value | Meaning |
|---|---:|---|
| READY | 0/1 | No Pod is ready out of the one desired replica. |
| UP-TO-DATE | 1 | One Pod uses the latest Deployment configuration. |
| AVAILABLE | 0 | No Pod is available. |

### Why is UP-TO-DATE 1 while READY is 0?

The Deployment successfully created a Pod using the latest configuration.

However, that Pod could not be scheduled because of insufficient CPU.

This demonstrates that:

- Deployment creation succeeded.
- Pod creation succeeded.
- Pod scheduling failed.

These are different stages in the Kubernetes workload lifecycle.

---

## 9. Fixing the issue

For our lightweight Ubuntu test workload, we reduced the CPU request and limit:

```yaml
resources:
  requests:
    cpu: "100m"

  limits:
    cpu: "500m"
```

### Understanding the updated values

| Configuration | Value | Meaning |
|---|---:|---|
| CPU request | `100m` | 0.1 CPU core |
| CPU limit | `500m` | 0.5 CPU core |

These are illustrative values for our simple echo-and-sleep test container.

They are not recommended production values for every application.

### Why did we change the request?

The original request of 13 CPU cores exceeded the node's allocatable CPU.

The new request of 100m is small enough for the scheduler to place the Pod on the node.

### Why did we change the limit?

We set a limit of 500m to establish a small runtime CPU ceiling for the test container.

---

## 10. Applying the fix

We applied the updated manifest:

```powershell
kubectl apply -f manifests/insufficient-resources/insufficient-cpu.yaml
```

Output:

```text
deployment.apps/insufficient-cpu configured
```

The word `configured` indicates that Kubernetes updated the existing Deployment rather than creating a new one.

### Observing the updated Pods

We ran:

```powershell
kubectl get pods -n k8s-troubleshooting
```

Output:

```text
NAME                                   READY   STATUS    RESTARTS       AGE
insufficient-cpu-8d7f6dd6f-q2x8t       1/1     Running   0              26s
insufficient-memory-6c5795d69b-nzr8w   1/1     Running   5 (6h2m ago)   22h
```

### What happened?

1. We updated the Deployment's Pod template.
2. Kubernetes created a new ReplicaSet.
3. The new ReplicaSet created a Pod with the updated CPU configuration.
4. The new Pod was successfully scheduled and started.
5. The old Pending Pod was removed.

The memory experiment continued running without disruption.

---

## 11. Understanding the ReplicaSets

We inspected the ReplicaSets:

```powershell
kubectl get replicasets -n k8s-troubleshooting
```

Output:

```text
NAME                             DESIRED   CURRENT   READY   AGE
insufficient-cpu-57f79b7785      0         0         0       9m45s
insufficient-cpu-8d7f6dd6f       1         1         1       58s
insufficient-memory-6c5795d69b   1         1         1       22h
insufficient-memory-85bfbf495c   0         0         0       22h
```

### CPU ReplicaSets

| ReplicaSet | Desired | Current | Ready | Explanation |
|---|---:|---:|---:|---|
| `insufficient-cpu-57f79b7785` | 0 | 0 | 0 | Old configuration with 13 CPU cores requested. |
| `insufficient-cpu-8d7f6dd6f` | 1 | 1 | 1 | Updated configuration with 100m CPU requested. |

The old ReplicaSet has been scaled down to zero Pods.

The new ReplicaSet manages one ready Pod.

The old ReplicaSet remains as a Kubernetes object for Deployment history and potential rollback.

---

## 12. Inspecting the successfully running Pod

We also inspected the new Pod to verify its final configuration and lifecycle events:

```powershell
kubectl describe pod insufficient-cpu-8d7f6dd6f-q2x8t -n k8s-troubleshooting
```

### Node assignment

```text
Node: gamehub-cluster/192.168.58.2
Status: Running
```

Unlike the original Pod, Kubernetes successfully assigned the updated Pod to our Minikube node.

### Container state

```text
State: Running
  Started: Wed, 11 Nov 2026 18:26:44 +0530
Ready: True
Restart Count: 0
```

The container started successfully, is Ready, and has not restarted.

### Updated resource configuration

```text
Limits:
  cpu: 500m

Requests:
  cpu: 100m
```

This confirms that the Pod is running with our updated CPU values.

### Conditions

```text
PodReadyToStartContainers   True
Initialized                 True
Ready                       True
ContainersReady             True
PodScheduled                True
```

All relevant conditions are True.

### Events

```text
Normal  Scheduled  Successfully assigned k8s-troubleshooting/insufficient-cpu-8d7f6dd6f-q2x8t to gamehub-cluster

Normal  Pulling    Pulling image "ubuntu"

Normal  Pulled     Successfully pulled image "ubuntu"

Normal  Created    Container created

Normal  Started    Container started
```

### Understanding the successful lifecycle

| Event | Meaning |
|---|---|
| `Scheduled` | Kubernetes assigned the Pod to the node. |
| `Pulling` | Kubelet started downloading the Ubuntu image. |
| `Pulled` | The image was downloaded successfully. |
| `Created` | The container was created. |
| `Started` | The container started successfully. |

This confirms that the updated Pod passed the scheduling and container startup stages.

---

## 13. Final verification

Finally, we checked the Deployment:

```powershell
kubectl get deployment insufficient-cpu -n k8s-troubleshooting
```

Output:

```text
NAME               READY   UP-TO-DATE   AVAILABLE   AGE
insufficient-cpu   1/1     1            1           10m
```

### Understanding the output

| Column | Value | Meaning |
|---|---:|---|
| READY | 1/1 | One Pod is ready out of one desired replica. |
| UP-TO-DATE | 1 | One Pod uses the latest Deployment configuration. |
| AVAILABLE | 1 | One Pod is available. |

The Deployment has one ready and available replica.

The CPU scheduling issue has been resolved.

---

## 14. What I learned

1. Kubernetes schedules Pods based on their CPU requests.
2. A Pod can remain Pending when no node can satisfy its CPU request.
3. `kubectl describe pod` helps identify scheduling failures through Events.
4. `kubectl describe node` helps inspect node capacity, allocatable resources, and allocated requests.
5. CPU values can be expressed in cores or millicores.
6. A Deployment manages ReplicaSets, and ReplicaSets manage Pods.
7. Changing a Deployment's Pod template can trigger a rolling update and create a new ReplicaSet.
8. CPU requests influence scheduling, whereas CPU limits control runtime CPU consumption.
9. Exceeding a CPU limit normally causes throttling rather than container termination.
10. CPU requests and limits should be configured based on application profiling and normal and peak workload requirements.

### Key takeaway

**A Pod can remain Pending even when its container image and application configuration are correct. The scheduler may be unable to place it because the requested CPU exceeds the available node resources.**

In real deployments, resource requests and limits should be based on measured application behaviour, workload requirements, and available cluster capacity.

---

## 15. Commands reference

| Command | Purpose |
|---|---|
| `kubectl describe node gamehub-cluster` | Inspect node CPU and memory capacity and allocated resources. |
| `kubectl apply --dry-run=client -f <file>` | Validate a manifest without creating resources. |
| `kubectl apply -f <file>` | Create or update resources from a manifest. |
| `kubectl get pods -n k8s-troubleshooting` | Check Pod status. |
| `kubectl describe pod <pod-name> -n k8s-troubleshooting` | Inspect Pod details, conditions, resources, and Events. |
| `kubectl get deployment insufficient-cpu -n k8s-troubleshooting` | Check Deployment status. |
| `kubectl get replicasets -n k8s-troubleshooting` | Inspect ReplicaSets and their Pod counts. |

**Experiment status:** Completed successfully.