# Kubernetes Troubleshooting – Insufficient Memory

## 1. Objective

The objective of this experiment is to understand what happens when a Kubernetes Pod requests more memory than the available memory on a node.

We will:

1. Intentionally create an insufficient-memory scheduling issue.
2. Observe the Pod's status.
3. Identify the root cause using Kubernetes troubleshooting commands.
4. Fix the resource configuration.
5. Verify that the Pod and Deployment recover successfully.

All resources for this experiment are created inside the `k8s-troubleshooting` namespace to keep them separate from the GameHub application.

---

## 2. Understanding the problem

Kubernetes uses resource requests when deciding which node can run a Pod.

If a Pod requests more memory than a node has available for scheduling, the Kubernetes scheduler cannot place that Pod on the node.

The Pod remains in the `Pending` state.

### Important concepts

| Term | Meaning |
|---|---|
| Memory capacity | Total memory available on the node. |
| Allocatable memory | Memory Kubernetes makes available for Pods. |
| Memory request | The amount of memory Kubernetes uses when scheduling a Pod. |
| Memory limit | The maximum memory the container is allowed to consume. |

**Important:** A memory request is not the amount of memory the application will necessarily consume. It is a resource requirement used by the scheduler.

---

## 3. Understanding application resource requirements

Before configuring resource requests and limits, a deployment engineer should understand how much CPU and memory the application actually needs.

The engineer should work with the development team to understand:

1. How much memory does the application normally require?
2. What is its expected memory consumption under normal load?
3. What is its peak memory consumption under heavy load?
4. What CPU resources does it require?
5. What are reasonable resource requests and limits?

Based on this information, the deployment engineer configures appropriate resource requests and limits.

### Important distinction

- **Requests** are used for scheduling. They tell Kubernetes how much resource capacity to reserve for scheduling the Pod.
- **Limits** define runtime ceilings. They specify the maximum CPU or memory the container is allowed to consume.

Requests and limits are not necessarily the application's exact minimum and maximum requirements.

For example, a memory request is not automatically the application's minimum possible memory consumption, and a memory limit is not automatically its expected peak consumption. They are Kubernetes resource configuration values that should be chosen based on application behaviour and operational requirements.

**Real-world takeaway:** We should not arbitrarily increase or decrease resource values just to make a Pod run. We should understand the application's resource usage and configure appropriate values.

---

## 4. Inspecting the node before the experiment

Before creating the test workload, we inspected the node:

```powershell
kubectl describe node gamehub-cluster
```

Relevant observations:

| Resource | Value |
|---|---:|
| CPU capacity | 12 |
| CPU allocatable | 12 |
| Memory capacity | 7,733,900Ki |
| Memory allocatable | 7,733,900Ki |
| Existing memory requests | 220Mi |
| Existing memory limits | 220Mi |

The node had approximately **7.38Gi of allocatable memory**.

Since the node had only around 7.38Gi allocatable memory, we chose an intentionally impossible memory request of 8Gi.

This ensures that the scheduler cannot place our test Pod on this single-node cluster.

---

## 5. Creating the problem

Manifest location:

`manifests/insufficient-resources/insufficient-memory.yaml`

We created a Deployment with:

```yaml
resources:
  requests:
    memory: "8Gi"
  limits:
    memory: "9Gi"
```

### Why these values?

- `8Gi` request: Exceeds the node's approximately 7.38Gi allocatable memory.
- `9Gi` limit: Defines the maximum memory the container is allowed to consume.

The container runs a simple Ubuntu shell command that prints a message every 10 seconds.

It does not intentionally consume 8Gi or 9Gi of memory. This experiment tests **scheduling based on the memory request**, not actual memory consumption.

### Validate the manifest

```powershell
kubectl apply --dry-run=client -f manifests/insufficient-resources/insufficient-memory.yaml
```

Output:

```text
deployment.apps/insufficient-memory created (dry run)
```

A client-side dry run validates the manifest without creating the Deployment or testing actual scheduling.

### Apply the manifest

```powershell
kubectl apply -f manifests/insufficient-resources/insufficient-memory.yaml
```

Output:

```text
deployment.apps/insufficient-memory created
```

---

## 6. Observing the issue

Initially, we ran:

```powershell
kubectl get pods
```

Output:

```text
No resources found in default namespace.
```

**Why?**

We created our Deployment in the `k8s-troubleshooting` namespace, but the command without `-n` checks the `default` namespace.

We then used:

```powershell
kubectl get pods -n k8s-troubleshooting
```

Output:

```text
NAME                                   READY   STATUS    RESTARTS   AGE
insufficient-memory-85bfbf495c-mfrdl   0/1     Pending   0          31s
```

The Pod was in the `Pending` state.

This means Kubernetes had created the Pod object, but the Pod had not been scheduled onto a node.

---

## 7. Troubleshooting the Pending Pod

We inspected the Pod:

```powershell
kubectl describe pod insufficient-memory-85bfbf495c-mfrdl -n k8s-troubleshooting
```

Important observations:

```text
Node: <none>
Status: Pending

Conditions:
  PodScheduled False
```

Resource configuration:

```text
Limits:
  memory: 9Gi

Requests:
  memory: 8Gi
```

Most importantly, the Events section showed:

```text
Warning  FailedScheduling
0/1 nodes are available: 1 Insufficient memory.
preemption: 0/1 nodes are available: 1 Preemption is not helpful for scheduling.
```

### Understanding the observations

| Observation | Explanation |
|---|---|
| `Node: <none>` | Kubernetes has not assigned the Pod to a node. |
| `Status: Pending` | The Pod is waiting to be scheduled. |
| `PodScheduled: False` | The scheduler could not schedule the Pod. |
| `FailedScheduling` | The scheduling attempt failed. |
| `Insufficient memory` | The node cannot satisfy the Pod's memory request. |
| `Preemption is not helpful` | Evicting other Pods would not make enough memory available for this request. |

### Root cause

Our node has approximately 7.38Gi allocatable memory, but the test Pod requests 8Gi.

The scheduler cannot satisfy this request, so the Pod remains Pending.

---

## 8. Checking the Deployment

We also inspected the Deployment:

```powershell
kubectl get deployment insufficient-memory -n k8s-troubleshooting
```

Output:

```text
NAME                  READY   UP-TO-DATE   AVAILABLE   AGE
insufficient-memory   0/1     1            0           5m7s
```

Understanding the columns:

| Column | Meaning |
|---|---|
| READY | Number of ready Pods out of the desired number. |
| UP-TO-DATE | Number of Pods using the latest Deployment configuration. |
| AVAILABLE | Number of Pods available to serve requests. |

The Deployment wanted one Pod, but none was ready or available.

---

## 9. Fixing the issue

For our small Ubuntu test workload, we reduced the memory request and limit:

```yaml
resources:
  requests:
    memory: "128Mi"
  limits:
    memory: "256Mi"
```

These are illustrative values for this lightweight test container, not recommended production values for every application.

**Why did we change the request?**

The original request of 8Gi could not be satisfied by our node.

The new request of 128Mi is small enough for the scheduler to place the Pod on the node.

**Why did we change the limit?**

We set a limit of 256Mi to give the test container a small memory ceiling.

Remember:

- Request: Used by Kubernetes for scheduling.
- Limit: Maximum memory the container can consume.

If a container exceeds its memory limit, it can be terminated with an `OOMKilled` reason.

---

## 10. Applying the fix

We applied the updated manifest:

```powershell
kubectl apply -f manifests/insufficient-resources/insufficient-memory.yaml
```

Output:

```text
deployment.apps/insufficient-memory configured
```

We checked the Pods:

```powershell
kubectl get pods -n k8s-troubleshooting
```

During the update, we observed:

```text
NAME                                   READY   STATUS              RESTARTS   AGE
insufficient-memory-6c5795d69b-nzr8w   0/1     ContainerCreating   0          11s
insufficient-memory-85bfbf495c-mfrdl   0/1     Pending             0          7m30s
```

### Why were there two Pods?

We changed the Deployment's Pod template by updating its memory configuration.

Kubernetes created a new ReplicaSet for the updated configuration.

During a rolling update:

1. The new ReplicaSet creates a new Pod.
2. The new Pod starts and becomes Ready.
3. Kubernetes scales down the old ReplicaSet.
4. The old Pod is removed.

This allows Kubernetes to update applications while managing their availability.

### Understanding the ReplicaSets

We ran:

```powershell
kubectl get replicasets -n k8s-troubleshooting
```

Final output:

```text
NAME                             DESIRED   CURRENT   READY   AGE
insufficient-memory-6c5795d69b   1         1         1       98s
insufficient-memory-85bfbf495c   0         0         0       8m57s
```

| ReplicaSet | Desired | Current | Ready | Explanation |
|---|---:|---:|---:|---|
| `insufficient-memory-6c5795d69b` | 1 | 1 | 1 | New ReplicaSet with updated memory configuration. |
| `insufficient-memory-85bfbf495c` | 0 | 0 | 0 | Old ReplicaSet with the original 8Gi request. |

The old ReplicaSet still exists, but it no longer manages any Pods.

---

## 11. Verifying the fix

First, we checked the Pods:

```powershell
kubectl get pods -n k8s-troubleshooting
```

Output:

```text
NAME                                   READY   STATUS    RESTARTS   AGE
insufficient-memory-6c5795d69b-nzr8w   1/1     Running   0          95s
```

Then, we checked the Deployment:

```powershell
kubectl get deployment insufficient-memory -n k8s-troubleshooting
```

Output:

```text
NAME                  READY   UP-TO-DATE   AVAILABLE   AGE
insufficient-memory   1/1     1            1           9m52s
```

### Understanding the final output

| Column | Value | Meaning |
|---|---:|---|
| READY | 1/1 | One Pod is ready out of one desired Pod. |
| UP-TO-DATE | 1 | One Pod uses the latest Deployment configuration. |
| AVAILABLE | 1 | One Pod is available. |

The Pod is Running and Ready, and the Deployment has one available replica.

The scheduling issue is resolved.

---

## 12. What I learned

1. Kubernetes schedules Pods based on their resource requests.
2. A Pod can remain Pending if its resource requests cannot be satisfied by any available node.
3. `kubectl describe pod` helps identify scheduling failures through the Events section.
4. `kubectl describe node` helps inspect node capacity, allocatable resources, and allocated requests.
5. A Deployment manages ReplicaSets, and ReplicaSets manage Pods.
6. Changing a Deployment's Pod template can trigger a rolling update and create a new ReplicaSet.
7. A memory request and a memory limit serve different purposes.
8. A namespace separates Kubernetes resources logically, but it does not provide separate node resources.
9. Resource requests and limits should be configured based on the application's actual resource usage, not arbitrary assumptions.
10. Development and deployment teams should work together to understand normal and peak CPU and memory requirements.

### Key takeaway

**A Pod being Pending does not always mean there is a problem with its image or application. It can also mean that Kubernetes cannot find a node with enough resources to satisfy its requests.**

Before configuring resource requests and limits in a real application, understand its normal and peak resource consumption and choose values accordingly.

---

## 13. Commands reference

| Command | Purpose |
|---|---|
| `kubectl describe node gamehub-cluster` | Inspect node capacity, allocatable resources, and allocated requests. |
| `kubectl apply --dry-run=client -f <file>` | Validate a manifest without creating resources. |
| `kubectl apply -f <file>` | Create or update resources from a manifest. |
| `kubectl get pods -n k8s-troubleshooting` | Check Pod status in the troubleshooting namespace. |
| `kubectl describe pod <pod-name> -n k8s-troubleshooting` | Inspect Pod details, conditions, and Events. |
| `kubectl get deployment -n k8s-troubleshooting` | Check Deployment status. |
| `kubectl get replicasets -n k8s-troubleshooting` | Inspect ReplicaSets and their Pod counts. |

**Experiment status:** Completed successfully.