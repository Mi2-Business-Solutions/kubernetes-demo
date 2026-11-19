# Kubernetes Lab: Node Affinity – Soft Preference

## 1. Objective

Understand how Kubernetes Node Affinity works when a Node is preferred but not mandatory.

In this experiment, we configure a Pod to prefer a Node with a particular label. However, if no Node matches that preference, Kubernetes should still be able to schedule the Pod on another eligible Node.

The objective is to understand the difference between a scheduling requirement and a scheduling preference.

## 2. Concept: Preferred Node Affinity

Kubernetes provides two main types of Node Affinity:

| Type | Behaviour |
|---|---|
| `requiredDuringSchedulingIgnoredDuringExecution` | Hard requirement. The Pod must be scheduled on a matching Node. |
| `preferredDuringSchedulingIgnoredDuringExecution` | Soft preference. Kubernetes prefers a matching Node but can schedule the Pod elsewhere. |

### What does `preferredDuringSchedulingIgnoredDuringExecution` mean?

- **preferred:** Kubernetes tries to find a Node matching the specified preference.
- **DuringScheduling:** The preference is considered when Kubernetes schedules the Pod.
- **IgnoredDuringExecution:** If the Node's labels change after the Pod is scheduled, Kubernetes does not automatically evict the running Pod just because the preference is no longer satisfied.

### What is `weight`?

Every preferred scheduling rule requires a weight between 1 and 100.

- A higher weight represents a stronger preference.
- A lower weight represents a weaker preference.
- Weight is used as part of the scheduler's scoring process.
- Weight is not a probability or percentage.
- Weight does not guarantee that Kubernetes will select a particular Node.

When multiple preferences exist, Kubernetes considers their weights along with other scheduler scoring factors.

## 3. Our Cluster Environment

Our experiment uses the existing Minikube cluster:

- Cluster: `gamehub-cluster`
- Kubernetes namespace: `k8s-troubleshooting`
- Number of Nodes: 1
- Node name: `gamehub-cluster`

The actual Node has these relevant labels:

| Label key | Label value |
|---|---|
| `mynode` | `demonode` |
| `workload` | `gamehub` |

Our soft-affinity rule prefers:

`workload=production`

This label does not match the actual Node's `workload=gamehub` label.

That mismatch is intentional. It allows us to observe whether a soft preference prevents scheduling.

## 4. Deployment Configuration

The Deployment is named `gamehub-node-affinity-soft`.

Its Node Affinity configuration is:

```yaml
affinity:
  nodeAffinity:
    preferredDuringSchedulingIgnoredDuringExecution:
      - preference:
          matchExpressions:
            - key: workload
              operator: In
              values:
                - production
        weight: 80
```

### Understanding this configuration

1. `preferredDuringSchedulingIgnoredDuringExecution` tells Kubernetes that this is a preference, not a mandatory requirement.
2. `matchExpressions` defines the label condition.
3. `key: workload` identifies the Node label to evaluate.
4. `operator: In` means the label value must be present in the specified values.
5. `values: production` specifies the preferred label value.
6. `weight: 80` gives this preference a weight of 80 in scheduler scoring.

**Expected behaviour:** Since our only Node has `workload=gamehub`, it does not satisfy the preference. However, because this is a soft preference, the Pod can still be scheduled there.

## 5. Apply the Deployment

Command:

```powershell
kubectl apply -f .\gamehub-node-affinity-soft.yaml
```

Purpose:

- Creates the Deployment if it does not exist.
- Applies configuration changes if the Deployment already exists.
- Does not create a duplicate Deployment with the same name.

## 6. Verify the Deployment

Command:

```powershell
kubectl get deployments -n k8s-troubleshooting
```

Our observed output included:

```text
NAME                         READY   UP-TO-DATE   AVAILABLE
gamehub-node-affinity-soft   1/1     1            1
```

This confirms that the Deployment has one available replica.

## 7. Verify the Pod

Command:

```powershell
kubectl get pods -n k8s-troubleshooting -o wide
```

Observed Pod:

```text
gamehub-node-affinity-soft-695dd8b79c-zxj7s
1/1 Running
NODE: gamehub-cluster
```

### What did we observe?

Our only Node has:

`workload=gamehub`

But the Deployment prefers:

`workload=production`

Even though the preference did not match, the Pod reached the `Running` state on `gamehub-cluster`.

**This is the expected behaviour of soft Node Affinity.**

The scheduler was allowed to select the available Node because the preference was not a mandatory scheduling requirement.

## 8. Hard vs Soft Node Affinity

| Behaviour | Hard Affinity | Soft Affinity |
|---|---|---|
| Matching Node required? | Yes | No |
| Can schedule on a non-matching Node? | No | Yes |
| Pod can remain Pending if no Node matches? | Yes | Not because of the preference alone |
| Configuration | `requiredDuringSchedulingIgnoredDuringExecution` | `preferredDuringSchedulingIgnoredDuringExecution` |

### Important distinction

A Pod can still remain Pending with soft affinity if other scheduling constraints cannot be satisfied, such as insufficient CPU, insufficient memory, taints, or other scheduling restrictions.

Soft affinity only makes the Node Affinity condition a preference. It does not remove other scheduling requirements.

## 9. Deployment Engineer Perspective

In a real environment, deployment engineers should decide whether a workload needs a mandatory Node placement or simply a preferred placement.

### Example: Application workload

Imagine a Kubernetes cluster has:

- Nodes labelled `workload=production`
- Nodes labelled `workload=general`

A production application may perform better on production-designated Nodes.

If the application must run exclusively on production Nodes because of strict infrastructure or isolation requirements, hard affinity may be appropriate.

However, if production Nodes are preferred for performance reasons but the application can safely run on general Nodes, soft affinity may be more suitable.

### Why would an engineer choose soft affinity?

1. **Scheduling flexibility:** The Pod can still run when the preferred Node is unavailable or unsuitable.
2. **Better workload placement:** Kubernetes can favour Nodes that meet the application's preferred characteristics.
3. **Reduced scheduling restrictions:** A preference does not unnecessarily block a workload from running elsewhere.
4. **Operational resilience:** The application has more placement options, provided its other scheduling requirements are satisfied.

### What should an engineer consider before choosing?

- Does the application require specific hardware?
- Is the preferred Node necessary for correctness, security, or isolation?
- Can the application safely run on other Nodes?
- Are there enough eligible Nodes to support the workload?
- Could resource constraints prevent scheduling even when a preferred Node exists?

The decision should be based on application requirements, not simply on which affinity option is easier to configure.

## 10. Limitations of This Experiment

Our Minikube cluster contains only one Node.

Therefore, this experiment demonstrates that a Pod can schedule successfully even when its soft Node Affinity preference does not match.

However, it does not demonstrate:

- How Kubernetes chooses between multiple matching Nodes.
- Whether a higher weight changes the selected Node.
- How Kubernetes falls back to another Node when the preferred Node is unavailable.
- How multiple preferences influence the scheduler's final scores.

Those behaviours require a multi-node environment for meaningful hands-on comparison.

## 11. Cleanup

The earlier experiment used a Deployment named `gamehub-node-affinity`. It was separate from the newly named hard and soft Deployments.

To remove that obsolete Deployment and its managed Pod:

```powershell
kubectl delete deployment gamehub-node-affinity -n k8s-troubleshooting
```

This does not delete the hard or soft Node Affinity Deployments.

Verify the remaining Deployments:

```powershell
kubectl get deployments -n k8s-troubleshooting
```

**Note:** The cleanup command was identified during the lab. Record the cleanup as completed only after confirming its successful execution.

## 12. Key Takeaways

- Hard affinity defines where a Pod is allowed to run.
- Soft affinity defines where Kubernetes should preferably run a Pod.
- `weight` controls the relative strength of a preference in scheduler scoring.
- A soft preference mismatch does not, by itself, prevent scheduling.
- `IgnoredDuringExecution` means a change in Node labels does not automatically evict an already-running Pod.
- Deployment engineers should choose affinity based on application requirements, infrastructure constraints, and scheduling flexibility.