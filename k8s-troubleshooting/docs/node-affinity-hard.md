# Kubernetes Hands-on Lab: Required Node Affinity

## 1. Objective

Understand and demonstrate how Kubernetes **Required Node Affinity** controls Pod placement.

In this experiment, we deliberately create a scheduling failure by specifying a Node label that does not exist. We then investigate the scheduling failure, correct the Node label, and observe Kubernetes automatically schedule the existing Pending Pod.

**Environment:**
- Kubernetes: v1.37.0
- Minikube: v1.39.0
- Minikube profile: `gamehub-cluster`
- Node: `gamehub-cluster`
- Namespace: `k8s-troubleshooting`

**Important:** This is an isolated troubleshooting experiment. We do not modify the actual GameHub application resources in the `gamehub` namespace.

---

## 2. Background: Required Node Affinity

Node Affinity is a Kubernetes scheduling mechanism that allows us to specify which Nodes are eligible to receive a Pod.

We can define two types of Node Affinity:

| Type | Behaviour |
|---|---|
| `requiredDuringSchedulingIgnoredDuringExecution` | Hard requirement. A Pod can only be scheduled on a Node satisfying the rule. |
| `preferredDuringSchedulingIgnoredDuringExecution` | Soft preference. The scheduler prefers matching Nodes but can schedule on another eligible Node. |

In this experiment, we use:

`requiredDuringSchedulingIgnoredDuringExecution`

This means that if no Node satisfies the condition, the Pod remains Pending.

### Understanding the name

- `requiredDuringScheduling`: The condition must be satisfied when the scheduler assigns the Pod to a Node.
- `IgnoredDuringExecution`: Once the Pod is scheduled, Kubernetes does not automatically evict it if the Node later stops matching the affinity rule.

---

## 3. Initial cluster state

Before starting the experiment, we inspected the Node labels:

```powershell
kubectl get nodes --show-labels
```

Our Node initially had the following custom label:

```text
mynode=demonode
```

It did not have:

```text
workload=gamehub
```

We deliberately chose `workload=gamehub` as an experimental label.

It is not intended to represent a separate frontend, backend, or database Node. Our actual GameHub frontend, Auth, Game and PostgreSQL workloads share the same Node.

---

## 4. Deployment configuration

**File:** `gamehub-node-affinity.yaml`

The following Deployment was created in the `k8s-troubleshooting` namespace.

```yaml
# API version used for Kubernetes Deployment resources
apiVersion: apps/v1

# Resource type
kind: Deployment

metadata:
  # Name of our Node Affinity experiment
  name: gamehub-node-affinity

  # Keep this experiment separate from the actual GameHub application
  namespace: k8s-troubleshooting

spec:
  # Maintain one Pod for this experiment
  replicas: 1

  # Deployment uses this label to identify the Pods it manages
  selector:
    matchLabels:
      app: gamehub-node-affinity

  # Template used by the Deployment to create its Pod
  template:
    metadata:
      labels:
        # Identifies this experimental application
        app: gamehub-node-affinity

        # Identifies the purpose of this Pod
        lab: node-affinity

    spec:
      # Node Affinity controls which Nodes are eligible
      # to receive this Pod
      affinity:
        nodeAffinity:
          # Hard scheduling requirement:
          # the Pod can ONLY be scheduled on a matching Node.
          requiredDuringSchedulingIgnoredDuringExecution:

            # The Node must satisfy this matching expression
            nodeSelectorTerms:
              - matchExpressions:

                  # Node must contain the label key "workload"
                  - key: workload

                    # The label value must be present in the values list
                    operator: In
                    values:
                      - gamehub

            # EXPECTED BEHAVIOUR:
            # Our current Node has mynode=demonode,
            # but does NOT have workload=gamehub.
            # Therefore, no Node satisfies this requirement.
            # The Pod is expected to remain Pending.

      # Container specification for our experimental Pod
      containers:
        - name: main

          # Use a pinned Ubuntu image rather than the untagged ubuntu image
          image: ubuntu:24.04

          # Keep the container running so we can inspect the Pod
          command:
            - /bin/bash
            - -c
            - "while true; do echo GameHub-NodeAffinity; sleep 10; done"
```

### Understanding the affinity expression

| YAML field | Explanation |
|---|---|
| `nodeAffinity` | Defines Node placement constraints. |
| `requiredDuringSchedulingIgnoredDuringExecution` | Makes the scheduling condition mandatory. |
| `nodeSelectorTerms` | Contains the alternative sets of matching expressions. |
| `matchExpressions` | Defines the conditions to evaluate against Node labels. |
| `key: workload` | The Node label key to check. |
| `operator: In` | The Node's label value must belong to the specified values list. |
| `values: gamehub` | The required label value. |

**Important logical distinction:**

- Multiple expressions inside one `nodeSelectorTerm` are combined using AND.
- Multiple `nodeSelectorTerms` are combined using OR.
- `In` is an operator within a matching expression; it is not the same as the OR relationship between terms.

Our experiment has one term and one expression, so we are not demonstrating multiple-term OR behaviour here.

---

## 5. Validate the YAML

Before creating the Deployment, we performed a client-side dry run:

```powershell
kubectl apply --dry-run=client -f .\gamehub-node-affinity.yaml
```

**Observed output:**

```text
deployment.apps/gamehub-node-affinity created (dry run)
```

This confirmed that the client accepted the manifest structure. No Deployment or Pod was created by the dry run.

---

## 6. Create the Deployment

We applied the manifest:

```powershell
kubectl apply -f .\gamehub-node-affinity.yaml
```

**Observed output:**

```text
deployment.apps/gamehub-node-affinity created
```

The Deployment was created successfully.

However, Deployment creation does not guarantee successful Pod scheduling.

The Deployment controller creates and maintains the desired number of Pods. The scheduler independently determines which Node can run each Pod.

---

## 7. Observe the scheduling failure

We inspected the Pods:

```powershell
kubectl get pods -n k8s-troubleshooting -o wide
```

**Observed output for our experiment:**

```text
NAME                                      READY   STATUS    RESTARTS   AGE   IP       NODE
gamehub-node-affinity-c6b6ff896-h9b5r     0/1     Pending   0          23s   <none>   <none>
```

### Interpretation

| Field | Observation | Meaning |
|---|---|---|
| READY | `0/1` | Container is not ready. |
| STATUS | `Pending` | Pod has not completed scheduling. |
| RESTARTS | `0` | No container restart occurred. |
| IP | `<none>` | Pod has not been assigned a Pod IP. |
| NODE | `<none>` | Scheduler has not assigned a Node. |

The Pod object existed, but Kubernetes could not find an eligible Node.

---

## 8. Diagnose the failure

We inspected the Pod:

```powershell
kubectl describe pod gamehub-node-affinity-c6b6ff896-h9b5r -n k8s-troubleshooting
```

### Conditions

```text
Conditions:
  Type           Status
  PodScheduled   False
```

This confirms that the scheduler had not assigned the Pod to a Node.

### Events

```text
Events:
  Type      Reason             From               Message
  ----      ------             ----               -------
  Warning   FailedScheduling   default-scheduler   0/1 nodes are available:
  1 node(s) didn't match Pod's node affinity/selector.
  preemption: 0/1 nodes are available:
  1 Preemption is not helpful for scheduling.
```

### Root cause

The scheduler evaluated our Node Affinity requirement.

The requirement was:

```text
workload=gamehub
```

But the Node only had:

```text
mynode=demonode
```

Therefore, the Node did not satisfy the required affinity rule.

### Why was preemption not helpful?

Preemption can help when scheduling is blocked by resource availability and evicting lower-priority Pods could free resources.

In this experiment, the problem was not resource availability. It was a missing Node label.

Evicting other Pods would not add the missing label, so preemption could not solve the problem.

**Root cause confirmed:** The Pod was Pending because no Node matched its required Node Affinity condition.

---

## 9. Remediation: Add the required Node label

We corrected the scheduling condition by adding the missing label to our Node.

```powershell
kubectl label nodes gamehub-cluster workload=gamehub
```

**Observed output:**

```text
node/gamehub-cluster labeled
```

We then checked the Node labels:

```powershell
kubectl get nodes --show-labels
```

The relevant portion of the output was:

```text
mynode=demonode,
workload=gamehub
```

The Node now satisfied our affinity expression.

### Verify Pod scheduling

We inspected the Pods again:

```powershell
kubectl get pods -n k8s-troubleshooting -o wide
```

**Observed output:**

```text
NAME                                      READY   STATUS    RESTARTS   AGE     IP           NODE
gamehub-node-affinity-c6b6ff896-h9b5r     1/1     Running   0          4m21s   10.244.0.12  gamehub-cluster
```

The Pod transitioned from Pending to Running.

Notice that the Pod name remained the same.

We did not delete or recreate the Deployment or Pod.

---

## 10. Why did Kubernetes schedule the existing Pod automatically?

This is one of the most important learnings from this experiment.

### Step 1: Deployment controller created the Pod

When we applied the Deployment, the Deployment controller ensured that its ReplicaSet created one Pod.

The Pod object existed in Kubernetes, but it had not been assigned to a Node.

### Step 2: Scheduler attempted placement

The scheduler evaluated the Pod's scheduling requirements.

It found that the only Node did not satisfy:

```text
workload=gamehub
```

The Pod remained Pending.

### Step 3: Node label changed

We executed:

```powershell
kubectl label nodes gamehub-cluster workload=gamehub
```

This updated the Node object in the Kubernetes API.

### Step 4: Scheduler received the Node update

The Kubernetes scheduler watches changes to relevant cluster objects, including Nodes.

When the Node label changed, the scheduler received the update.

Because this change could make previously unschedulable Pods eligible, the scheduler could retry scheduling the Pending Pod.

The scheduler uses scheduling queues and event-driven requeuing to reconsider Pods when relevant cluster changes occur.

### Step 5: Scheduler successfully assigned the Pod

The scheduler evaluated the affinity condition again.

```text
Required label: workload=gamehub
Actual label:   workload=gamehub
Result:         Match
```

It successfully assigned the existing Pod to `gamehub-cluster`.

The kubelet on that Node then took responsibility for starting the container.

### Important distinction

We did not recreate the Pod.

The existing Pod was retained and successfully scheduled after the cluster state changed.

The Deployment controller did not need to create another Pod because the existing Pod still satisfied the Deployment's desired replica count.

---

## 11. Verify container execution

Finally, we verified that the container was actually running our intended command.

```powershell
kubectl logs gamehub-node-affinity-c6b6ff896-h9b5r -n k8s-troubleshooting
```

**Observed output:**

```text
GameHub-NodeAffinity
GameHub-NodeAffinity
GameHub-NodeAffinity
GameHub-NodeAffinity
GameHub-NodeAffinity
GameHub-NodeAffinity
```

This confirmed that:

- The Pod was scheduled.
- The container started successfully.
- The command was executing.
- The container was producing the expected logs.

The Pod had zero restarts.

---

## 12. Complete experiment flow

```text
Create Deployment
       |
       v
Deployment controller creates Pod
       |
       v
Scheduler evaluates Node Affinity
       |
       v
Does Node have workload=gamehub?
       |
       +---- No ----> Pod remains Pending
       |                    |
       |                    v
       |              Inspect FailedScheduling
       |                    |
       |                    v
       |              Add Node label
       |                    |
       +--------------------+
                            |
                            v
                  Scheduler retries placement
                            |
                            v
                  Pod assigned to Node
                            |
                            v
                  Kubelet starts container
                            |
                            v
                       Pod Running
```

---

## 13. Deployment-engineering perspective

### A. Scheduling is different from deployment creation

Creating a Deployment does not mean that its Pods can immediately run.

A Deployment may be successfully created while its Pods remain Pending.

Deployment engineers should investigate scheduling constraints independently of Deployment creation.

### B. Understand the difference between a scheduling issue and a container issue

In this experiment:

- The container image was not the problem.
- The container command was not the problem.
- The application was not crashing.
- The Pod was not being restarted.

The scheduler could not assign the Pod to a Node.

This is why inspecting Pod conditions and Events is important before investigating container logs or application code.

### C. Node labels are metadata, not infrastructure provisioning

Adding:

```text
workload=gamehub
```

does not create additional resources or change the Node's capabilities.

It only changes the Node's metadata.

In production, labels should accurately represent real Node characteristics or intended scheduling classifications.

For example, a Node label claiming SSD storage should only be used when the Node actually has the required storage characteristics.

### D. Required affinity can affect availability

If a workload has strict Node Affinity requirements and no eligible Node is available, its Pods can remain Pending.

For production systems, engineers must ensure that suitable Nodes exist and have the correct labels.

Otherwise, a scheduling policy can prevent an application from starting even when other Nodes have available resources.

### E. Labels are not security boundaries

Node Affinity is a scheduling mechanism, not a security or isolation mechanism.

It should not be used as a replacement for appropriate access controls, security policies, taints and tolerations, or infrastructure isolation.

---

## 14. Limitations of this experiment

Our Minikube cluster has only one Node.

This allowed us to demonstrate:

1. Required Node Affinity.
2. A missing label causing a scheduling failure.
3. The `In` operator.
4. Pod Pending status and `FailedScheduling` events.
5. Remediation through a Node label update.
6. Automatic scheduling of the existing Pending Pod.

However, this experiment does not demonstrate:

- Scheduling between multiple eligible Nodes.
- Choosing a preferred Node over a non-preferred Node.
- Comparing Node Affinity weights.
- Distributing workloads across different Nodes.
- Real production failure scenarios involving independent physical Nodes.

Our experiment proves that the scheduler evaluates the required affinity rule. It does not demonstrate multi-node placement decisions.

---

## 15. Future scope

After completing the required affinity experiment, the following are useful extensions.

### Experiment 1: Other Node Affinity operators

Explore:

- `In`
- `NotIn`
- `Exists`
- `DoesNotExist`
- `Gt`
- `Lt`

Observe how each operator changes Node eligibility.

### Experiment 2: Preferred Node Affinity

Use:

```yaml
preferredDuringSchedulingIgnoredDuringExecution:
```

Demonstrate that a preference is not mandatory.

With our single Node, we can demonstrate that a Pod can still be scheduled even when its preferred condition is not satisfied.

However, we cannot compare placement decisions between multiple Nodes.

### Experiment 3: Multi-node Minikube

Create a separate multi-node Minikube cluster when appropriate.

Use it to investigate:

- Required versus preferred placement.
- Multiple eligible Nodes.
- Affinity weights.
- Scheduler placement decisions.

Multiple Minikube Nodes are useful for learning, but they are not equivalent to independent production servers.

### Experiment 4: IgnoredDuringExecution

After the Pod is running, remove the label:

```powershell
kubectl label nodes gamehub-cluster workload-
```

Observe whether the existing Pod continues running.

This will demonstrate that `IgnoredDuringExecution` does not automatically evict an already-scheduled Pod when the affinity condition stops matching.

This should be a separate controlled experiment.

---

## 16. Key takeaways

1. Node Affinity controls Pod placement based on Node labels.
2. `requiredDuringSchedulingIgnoredDuringExecution` is a hard scheduling requirement.
3. `operator: In` checks whether the Node's label value belongs to the specified values list.
4. A missing required Node label can cause a Pod to remain Pending.
5. `kubectl describe pod` and its Events section help identify scheduling failures.
6. Correcting a Node label can make an existing Pending Pod eligible for scheduling.
7. The scheduler can retry scheduling in response to relevant cluster changes.
8. The Pod does not need to be deleted and recreated when the scheduling condition is corrected.
9. `IgnoredDuringExecution` means the affinity rule is not automatically enforced through eviction after scheduling.
10. A single-node cluster is sufficient to demonstrate basic Required Node Affinity, but not multi-node placement decisions.

**Final learning:** Kubernetes scheduling is a continuous reconciliation process. When the cluster state changes, a previously unschedulable Pod can become eligible without requiring the Deployment or Pod to be recreated.