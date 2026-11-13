# Insufficient CPU and Memory Resources in Kubernetes

## 1. Objective

The objective of this experiment is to understand how Kubernetes behaves when a Pod requests more CPU and memory resources than the node can provide.

In the previous experiments, we tested insufficient CPU and insufficient memory individually.

In this experiment, we combine both resource constraints in a single Deployment to observe how the Kubernetes scheduler handles multiple resource shortages simultaneously.

**Expected behaviour:** The Pod should remain in `Pending` status because the node cannot satisfy either its CPU or memory request.

---

## 2. Understanding the Scenario

Our Minikube cluster contains a single node named `gamehub-cluster`.

The node has the following allocatable resources:

| Resource | Allocatable capacity |
|---|---:|
| CPU | 12 cores |
| Memory | Approximately 7.38Gi |

We intentionally configure our test container to request more resources than the node can provide.

### Resource Configuration

| Resource | Request | Limit |
|---|---:|---:|
| CPU | 13 cores | 14 cores |
| Memory | 8Gi | 9Gi |

**Why are we configuring these values?**

- CPU request of 13 cores exceeds the node's 12 allocatable CPU cores.
- Memory request of 8Gi exceeds the node's approximately 7.38Gi allocatable memory.

Therefore, the scheduler should be unable to find a suitable node for this Pod.

**Important:** Resource requests and limits serve different purposes.

- Requests specify the resources Kubernetes uses when deciding where to schedule a Pod.
- Limits specify the maximum resources a container is allowed to consume.

The scheduler evaluates requests during scheduling. The container does not need to actually consume 13 CPU cores or 8Gi of memory for this scheduling failure to occur.

---

## 3. Creating the Deployment YAML

**File name:** `insufficient-memory-cpu.yaml`

**Location:** `k8s-troubleshooting/manifests/insufficient-resources/`

The YAML combines the CPU and memory configurations into a single Deployment.

The container uses the Ubuntu image and executes a continuous shell command that prints a message every 10 seconds.

The command keeps the container running if Kubernetes successfully schedules it.

The resource requests and limits are intentionally configured beyond the node's allocatable capacity to reproduce the scheduling failure.

---

## 4. Validating the YAML Configuration

Before creating the actual Deployment, we perform a server-side dry run.

**Command:**

```powershell
kubectl apply --dry-run=server -f insufficient-memory-cpu.yaml
```

**Output:**

```text
deployment.apps/insufficient-memory-cpu created (server dry run)
```

**Explanation:**

The server-side dry run sends the configuration to the Kubernetes API server for validation without actually creating the Deployment.

The successful response confirms that the API server accepted the resource configuration.

No actual Deployment or Pod was created during this step.

---

## 5. Applying the Deployment

After successful validation, we create the actual Deployment.

**Command:**

```powershell
kubectl apply -f insufficient-memory-cpu.yaml
```

**Output:**

```text
deployment.apps/insufficient-memory-cpu created
```

**Explanation:**

The Kubernetes API server accepted the Deployment configuration.

The Deployment controller created a ReplicaSet, and the ReplicaSet created a Pod.

The scheduler then attempted to find a suitable node for the Pod.

---

## 6. Checking the Pod Status

**Command:**

```powershell
kubectl get pods -n k8s-troubleshooting
```

**Observed result:**

```text
NAME                                       READY   STATUS    RESTARTS
insufficient-cpu-8d7f6dd6f-q2x8t           1/1     Running   1
insufficient-memory-6c5795d69b-nzr8w       1/1     Running   6
insufficient-memory-cpu-786f495c44-2wcfz   0/1     Pending   0
```

**Observation:**

The combined-resource Pod remained in `Pending` status.

This indicates that the Pod was successfully created, but Kubernetes could not schedule it onto the available node.

The individual CPU and memory experiments remained unaffected.

### Important distinction

- Deployment creation succeeded.
- ReplicaSet creation succeeded.
- Pod creation succeeded.
- Pod scheduling failed.

A Pod can exist in the Kubernetes cluster without being assigned to a node.

---

## 7. Investigating the Scheduling Failure

To understand why the Pod remained Pending, we inspected it using `kubectl describe`.

**Command:**

```powershell
kubectl describe pod insufficient-memory-cpu-786f495c44-2wcfz -n k8s-troubleshooting
```

**Important observations:**

```text
Node: <none>
Status: Pending

Requests:
  cpu:        13
  memory:     8Gi

Limits:
  cpu:        14
  memory:     9Gi
```

The `Node: <none>` field indicates that the scheduler has not assigned the Pod to a node.

### Scheduler Events

The most important finding was in the Events section:

```text
Warning  FailedScheduling  default-scheduler

0/1 nodes are available:
1 Insufficient cpu,
1 Insufficient memory.

preemption: 0/1 nodes are available:
1 Preemption is not helpful for scheduling.
```

**Understanding the event:**

| Message | Explanation |
|---|---|
| `0/1 nodes are available` | The cluster has one node, but it cannot accommodate the Pod. |
| `Insufficient cpu` | The node cannot satisfy the requested 13 CPU cores. |
| `Insufficient memory` | The node cannot satisfy the requested 8Gi memory. |
| `Preemption is not helpful` | Evicting lower-priority Pods would not solve the resource shortage. |

Both CPU and memory constraints are preventing scheduling.

### What is Preemption?

Preemption is a Kubernetes scheduling mechanism in which lower-priority Pods may be evicted to make room for higher-priority Pods.

However, preemption cannot solve every scheduling problem.

In our experiment, the Pod requests 13 CPU cores, while the entire node has only 12 allocatable CPU cores.

Similarly, the Pod requests 8Gi memory, while the node has only approximately 7.38Gi allocatable memory.

Even if all other Pods were removed, the requested resources would still exceed the node's capacity.

Therefore, preemption cannot help.

---

## 8. Verifying Node Capacity

To verify the scheduler's findings, we inspected the node.

**Command:**

```powershell
kubectl describe node gamehub-cluster
```

### Node Capacity and Allocatable Resources

Observed output:

```text
Capacity:
  cpu:     12
  memory:  7733896Ki

Allocatable:
  cpu:     12
  memory:  7733896Ki
```

The node has:

| Resource | Allocatable |
|---|---:|
| CPU | 12 cores |
| Memory | Approximately 7.38Gi |

Our Deployment requests:

| Resource | Requested | Allocatable |
|---|---:|---:|
| CPU | 13 cores | 12 cores |
| Memory | 8Gi | 7.38Gi |

Both requests exceed the node's allocatable capacity.

### Understanding Allocated Resources

The node description also contains an `Allocated resources` section.

Observed output:

```text
Allocated resources:
  Resource           Requests    Limits
  --------           --------    ------
  cpu                950m (7%)   600m (5%)
  memory             348Mi (4%)  476Mi (6%)
```

**What does this mean?**

- Requests represent the resources already reserved for existing Pods.
- Limits represent the maximum resource consumption configured for those Pods.

An interesting observation is that existing Pods have requested only 950m CPU and 348Mi memory.

However, our new Pod still cannot be scheduled.

Why?

Because the scheduler evaluates whether the node can satisfy the entire resource request.

Even before considering the resources reserved for existing Pods, our new Pod requests more CPU and memory than the node's total allocatable capacity.

### Important Learning

Resource requests are not the same as actual resource consumption.

A container does not need to consume all its requested resources for the scheduler to consider those resources when making placement decisions.

---

## 9. Understanding the QoS Class

The Pod description also showed:

```text
QoS Class: Burstable
```

Kubernetes assigns a Quality of Service (QoS) class to Pods based on their CPU and memory requests and limits.

Our configuration:

| Resource | Request | Limit |
|---|---:|---:|
| CPU | 13 | 14 |
| Memory | 8Gi | 9Gi |

Since the requests and limits are different, the Pod receives the `Burstable` QoS class.

**Important:** The Burstable classification is not the reason for the scheduling failure.

The scheduling failure occurs because the node cannot satisfy the requested CPU and memory resources.

---

## 10. Understanding the Deployment Status

We also inspected the Deployment to understand its state.

**Command:**

```powershell
kubectl get deployment insufficient-memory-cpu -n k8s-troubleshooting
```

**Observed output:**

```text
NAME                      READY   UP-TO-DATE   AVAILABLE
insufficient-memory-cpu   0/1     1            0
```

### Understanding the Columns

| Field | Value | Explanation |
|---|---:|---|
| READY | 0/1 | Zero Pods are ready out of the one desired replica. |
| UP-TO-DATE | 1 | One Pod has been created using the latest Deployment configuration. |
| AVAILABLE | 0 | No Pods are available. |

**Important:** `UP-TO-DATE = 1` does not mean the Pod is running. It means the ReplicaSet has created a Pod using the latest Deployment specification.

### Deployment Conditions

From `kubectl describe deployment`:

```text
Conditions:
  Type           Status  Reason
  ----           ------  ------
  Available      False   MinimumReplicasUnavailable
  Progressing    True    ReplicaSetUpdated
```

**Understanding the conditions:**

- `Available: False` means the Deployment does not have the minimum number of available replicas.
- `Progressing: True` means the Deployment controller successfully updated the ReplicaSet.

The Deployment controller successfully created the Pod, but the Pod could not be scheduled.

This demonstrates that successful Deployment creation does not necessarily mean successful application deployment.

---

## 11. Cleaning Up the Experiment

After collecting the required observations, we deleted the combined-resource Deployment.

**Command:**

```powershell
kubectl delete -f insufficient-memory-cpu.yaml
```

**Output:**

```text
deployment.apps "insufficient-memory-cpu" deleted from k8s-troubleshooting namespace
```

### Verifying Cleanup

We verified the namespace using:

```powershell
kubectl get all -n k8s-troubleshooting
```

**Observed result:**

The combined-resource Deployment, its ReplicaSet and its Pod were no longer present.

The individual CPU and memory experiments remained intact.

This confirmed that deleting the combined Deployment did not affect our previous experiments.

---

## 12. Key Learnings

1. Kubernetes uses resource requests when deciding whether a Pod can be scheduled on a node.
2. Resource limits specify the maximum resources a container is allowed to consume.
3. A Pod can be successfully created but remain in `Pending` status if the scheduler cannot find a suitable node.
4. The `FailedScheduling` event helps identify why a Pod cannot be scheduled.
5. Both CPU and memory constraints can prevent a Pod from being scheduled simultaneously.
6. Node `Allocatable` resources represent the maximum resources available for scheduling Pods.
7. The `Allocated resources` section helps understand the resources already requested by existing Pods.
8. Preemption cannot solve a scheduling problem when a Pod's individual resource request exceeds the node's total allocatable capacity.
9. A Deployment can be successfully created while remaining unavailable because its Pods cannot become ready.
10. Resource requests must be planned according to application requirements and available cluster capacity.

## 13. Real-World Deployment Engineering Perspective

In a real-world Kubernetes environment, engineers should not randomly increase resource requests or limits.

They should first understand:

- How much CPU and memory the application actually needs.
- How much resource capacity is available across the cluster.
- How much capacity is already reserved by existing workloads.
- Whether the application can run with smaller requests.
- Whether additional nodes or greater node capacity are required.

The goal is to allocate sufficient resources to applications without unnecessarily wasting cluster capacity.

This is an important part of Kubernetes capacity planning and workload scheduling.

---

## Experiment Conclusion

Successfully reproduced a Kubernetes scheduling failure involving both insufficient CPU and insufficient memory resources.

The scheduler reported:

`Insufficient cpu, Insufficient memory`

Node capacity verification confirmed that both resource requests exceeded the node's allocatable resources.

The Deployment and Pod were created successfully, but the Pod remained Pending because no suitable node was available.

The experiment was completed successfully, and all resources created specifically for this combined scenario were cleaned up.