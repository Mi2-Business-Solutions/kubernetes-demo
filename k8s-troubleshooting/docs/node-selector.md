# Hands-on Lab: Troubleshooting Pod Scheduling Using Node Selector

## 1. Lab Objective

The objective of this lab is to understand how Kubernetes `nodeSelector` works and reproduce a Pod scheduling failure caused by a missing Node label.

We will:
- Inspect the labels available on a Kubernetes Node.
- Create a Deployment with a `nodeSelector` requirement.
- Reproduce a scheduling failure.
- Diagnose the issue using `kubectl describe pod`.
- Fix the issue by adding the required Node label.
- Verify that Kubernetes automatically schedules the Pending Pod.

**Environment:**
- Cluster: `gamehub-cluster`
- Kubernetes version: `v1.37.0`
- Minikube version: `v1.39.0`
- Namespace: `k8s-troubleshooting`
- Deployment: `gamehub-node-selector`
- Container image: `ubuntu:24.04`

We use the existing `k8s-troubleshooting` namespace to keep this experiment separate from the actual GameHub application.

---

## 2. Understand Node Labels Before Creating the Deployment

A Kubernetes Node contains labels that describe its characteristics and identify its role.

To inspect the available Node labels:

```powershell
kubectl get nodes --show-labels
```

Our Minikube Node:

```text
NAME              STATUS   ROLES           VERSION
gamehub-cluster   Ready    control-plane   v1.37.0
```

Some of the labels observed:

| Label | Purpose |
|---|---|
| `kubernetes.io/hostname=gamehub-cluster` | Identifies the Node hostname. |
| `kubernetes.io/os=linux` | Identifies the operating system. |
| `kubernetes.io/arch=amd64` | Identifies the CPU architecture. |
| `node-role.kubernetes.io/control-plane=` | Identifies the Node role. |
| `minikube.k8s.io/name=gamehub-cluster` | Identifies the Minikube profile. |

These are standard Kubernetes or platform-generated labels.

Kubernetes also allows administrators to create custom Node labels based on infrastructure requirements.

Examples:

| Custom label | Possible purpose |
|---|---|
| `storage=ssd` | Identify Nodes with SSD storage. |
| `workload=database` | Identify Nodes intended for database workloads. |
| `environment=production` | Identify production Nodes. |

**Deployment engineer's perspective:**

Node labels help engineers describe the capabilities and intended purpose of their infrastructure.

For example, if a database requires SSD storage, an engineer can label suitable Nodes with `storage=ssd` and configure the database workload to select those Nodes.

Labels should represent meaningful infrastructure characteristics and should be managed consistently.

---

## 3. Create a Deployment Using Node Selector

We created a separate Deployment named `gamehub-node-selector`.

The important scheduling configuration is:

```yaml
nodeSelector:
  mynode: demonode
```

This tells Kubernetes:

> Schedule this Pod only on a Node that has the exact label `mynode=demonode`.

Our complete YAML:

```yaml
apiVersion: apps/v1
kind: Deployment

metadata:
  name: gamehub-node-selector
  namespace: k8s-troubleshooting

spec:
  replicas: 1

  selector:
    matchLabels:
      app: gamehub-node-selector

  template:
    metadata:
      labels:
        app: gamehub-node-selector

    spec:
      containers:
        - name: main
          image: ubuntu:24.04
          command:
            - /bin/bash
            - -c
            - "while true; do echo GameHub-NodeSelector; sleep 10; done"

      nodeSelector:
        mynode: demonode
```

### Understanding the important configuration

| Configuration | Explanation |
|---|---|
| `replicas: 1` | Requests one Pod. |
| `selector.matchLabels` | Identifies which Pods belong to the Deployment. |
| `template.metadata.labels` | Assigns the label to the created Pod. |
| `containers` | Defines the container running inside the Pod. |
| `nodeSelector` | Specifies the Node label requirement for scheduling. |

**Important distinction:**

The `app: gamehub-node-selector` label belongs to the Pod.

The `mynode: demonode` label is expected on the Node.

They serve different purposes.

### Apply the Deployment

```powershell
kubectl apply -f .\gamehub-node-selector.yaml
```

Output:

```text
deployment.apps/gamehub-node-selector created
```

The Deployment was created successfully. However, this does not mean that its Pod has been scheduled successfully.

---

## 4. Reproduce the Scheduling Failure

We checked the Pod status:

```powershell
kubectl get pods -n k8s-troubleshooting -o wide
```

Observed result:

```text
NAME                                      READY   STATUS
gamehub-node-selector-6c9c48cb9f-2jbg4   0/1     Pending
```

The important observations were:

| Field | Observed value | Meaning |
|---|---|---|
| READY | `0/1` | Container is not ready. |
| STATUS | `Pending` | Pod has not progressed to running. |
| IP | `<none>` | No Pod IP assigned yet. |
| NODE | `<none>` | No Node has been assigned. |

Our Node did not have the required label:

```text
mynode=demonode
```

Therefore, the scheduler could not find a suitable Node.

### Why did this happen?

The Deployment requested a Node with an exact label match:

```yaml
nodeSelector:
  mynode: demonode
```

But our only available Node, `gamehub-cluster`, did not have that label.

As a result, the Pod remained Pending.

**Deployment engineer's perspective:**

A successfully created Deployment does not guarantee that its Pods will run.

The Deployment controller creates and maintains the desired number of Pods, while the scheduler is responsible for assigning eligible Pods to Nodes.

This distinction is important when troubleshooting workloads that exist but remain Pending.

---

## 5. Diagnose the Root Cause

To investigate the scheduling failure, we used:

```powershell
kubectl describe pod <pod-name> -n k8s-troubleshooting
```

We inspected the `Conditions`, `Node-Selectors`, and `Events` sections.

### Conditions

```text
Conditions:
  Type          Status
  PodScheduled  False
```

`PodScheduled: False` indicates that the Pod has not been assigned to a Node.

### Node Selectors

```text
Node-Selectors:
  mynode=demonode
```

This confirms the exact scheduling requirement configured in our Pod specification.

### Events

The most important message was:

```text
Warning  FailedScheduling

0/1 nodes are available:
1 node(s) didn't match Pod's node affinity/selector.

preemption: 0/1 nodes are available:
1 Preemption is not helpful for scheduling.
```

### Understanding the scheduler message

| Message | Explanation |
|---|---|
| `FailedScheduling` | The scheduler could not find an eligible Node. |
| `0/1 nodes are available` | Kubernetes evaluated one Node, and none qualified. |
| `didn't match Pod's node affinity/selector` | The Node did not satisfy the scheduling requirement. |
| `Preemption is not helpful` | Removing other Pods to free resources would not resolve this label mismatch. |

**Important clarification:**

The event mentions `node affinity/selector` because it uses a general scheduler message that covers both scheduling mechanisms.

Our YAML specifically uses `nodeSelector`, not Node Affinity.

### Root Cause

The Pod remained Pending because the only available Node did not have the required label:

```text
mynode=demonode
```

This was a scheduling constraint problem, not a container startup or application failure.

---

## 6. Remediate the Issue

After identifying the root cause, we added the missing label to our Minikube Node.

Command:

```powershell
kubectl label nodes gamehub-cluster mynode=demonode
```

Output:

```text
node/gamehub-cluster labeled
```

### Understanding the command

| Command component | Purpose |
|---|---|
| `kubectl label` | Adds or modifies a Kubernetes object label. |
| `nodes` | Specifies that we are targeting a Node. |
| `gamehub-cluster` | Name of our Node. |
| `mynode=demonode` | Label key and value being added. |

We modified the Node metadata, not the Deployment YAML.

The Deployment still had the same `nodeSelector` requirement.

### Deployment engineer's perspective

For a lab, manually adding a label is a straightforward way to demonstrate scheduling behaviour.

In production, engineers should first verify whether the label represents a genuine infrastructure capability or placement requirement.

Important Node labels are generally managed through infrastructure provisioning, cluster configuration, or configuration-management processes.

This helps maintain consistency when Nodes are replaced or recreated.

---

## 7. Verify the Remediation

After adding the label, we checked the Pods again:

```powershell
kubectl get pods -n k8s-troubleshooting -o wide
```

Observed result:

```text
NAME                                      READY   STATUS    RESTARTS   IP
gamehub-node-selector-6c9c48cb9f-2jbg4   1/1     Running   0          10.244.0.11
```

Node:

```text
gamehub-cluster
```

The Pod transitioned from:

| Before remediation | After remediation |
|---|---|
| Pending | Running |
| 0/1 Ready | 1/1 Ready |
| Node: `<none>` | Node: `gamehub-cluster` |
| IP: `<none>` | IP: `10.244.0.11` |

We also verified the Node labels:

```powershell
kubectl get nodes --show-labels
```

The output now included:

```text
mynode=demonode
```

This confirmed that the required custom label was successfully added.

### What happened internally?

1. The Deployment created a Pod.
2. The scheduler evaluated the Pod's scheduling requirements.
3. No available Node matched the required label.
4. The Pod remained Pending.
5. We added `mynode=demonode` to the Node.
6. The scheduler could now find an eligible Node.
7. The Pod was assigned to `gamehub-cluster`.
8. The kubelet started the container.
9. The Pod became Running and Ready.

**Important learning:** We did not recreate the Deployment or manually restart the Pod. Kubernetes automatically reconciled the workload after the scheduling constraint became satisfiable.

---

## 8. Real-World Deployment Engineering Considerations

Before using Node Selectors in a real environment, deployment engineers should consider the following:

### A. Verify Node labels before deploying

Inspect Node labels before introducing a scheduling requirement.

```powershell
kubectl get nodes --show-labels
```

A Pod can remain Pending indefinitely if no eligible Node exists.

### B. Validate infrastructure requirements

Do not add arbitrary labels merely to make a Pod run.

For example, if a database requires SSD storage, the engineer must verify that the selected Node actually has SSD storage.

A label is metadata; it does not install or provide the underlying capability.

### C. Consider cluster capacity

Even when a Node has the required label, resource availability, taints and tolerations, and other scheduling constraints can still prevent scheduling.

A matching label alone does not guarantee successful placement.

### D. Plan for Node replacement

If a Node is replaced, custom labels may need to be reapplied through the infrastructure provisioning process.

Important scheduling labels should not depend solely on manual changes.

### E. Choose the right scheduling mechanism

| Requirement | Suitable mechanism |
|---|---|
| Simple exact Node label matching | `nodeSelector` |
| More expressive hard scheduling rules | Required Node Affinity |
| Prefer a Node characteristic but allow alternatives | Preferred Node Affinity |
| Co-locate Pods based on other Pod labels | Pod Affinity |
| Avoid co-locating certain Pods | Pod Anti-Affinity |
| Spread workloads across topology domains | Topology Spread Constraints |

`nodeSelector` is still a supported Kubernetes scheduling mechanism. Node Affinity provides additional flexibility when more complex placement rules are required.

---

## 9. Troubleshooting Workflow — Key Takeaways

Our troubleshooting sequence:

```text
Create Deployment
       |
       v
Check Pod status
       |
       v
Pod is Pending
       |
       v
Inspect with kubectl describe pod
       |
       v
Identify FailedScheduling event
       |
       v
Check Node labels
       |
       v
Identify missing label
       |
       v
Add required Node label
       |
       v
Verify Pod becomes Running
```

### Commands learned

| Command | Purpose |
|---|---|
| `kubectl get nodes --show-labels` | Inspect Node labels. |
| `kubectl apply -f .\gamehub-node-selector.yaml` | Create the Deployment. |
| `kubectl get pods -n k8s-troubleshooting -o wide` | Inspect Pod status and Node assignment. |
| `kubectl describe pod <pod-name> -n k8s-troubleshooting` | Investigate Pod configuration, conditions and events. |
| `kubectl label nodes gamehub-cluster mynode=demonode` | Add the required Node label. |

### Final Learning

A Pending Pod is not necessarily an application problem.

As deployment engineers, we must identify which stage of the Kubernetes workload lifecycle is failing before deciding on a remediation.

In this lab, the Deployment was created successfully, but the scheduler could not find an eligible Node because of a missing Node label.

By identifying the root cause and correcting the Node metadata, Kubernetes automatically scheduled the Pod and brought it to the Running state.