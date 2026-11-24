# Kubernetes Taints and Tolerations – Hands-on Study

## 1. Learning objective

The objective of this study was to understand how Kubernetes uses **Taints and Tolerations** to control which pods can be scheduled on particular nodes.

We studied the concept using a GameHub application scenario rather than introducing unrelated sample applications.

### Important learning distinction

There is a difference between:

- Learning a Kubernetes concept.
- Practically implementing that concept in an application.
- Understanding when and why that concept is needed in a real-world environment.

Not every Kubernetes concept needs to be implemented in our current GameHub deployment. However, understanding these concepts is important for working with Kubernetes in different environments and handling real-world deployment requirements.

---

## 2. Business scenario

Imagine our GameHub application has the following components:

- Frontend
- Authentication service
- Game service
- PostgreSQL database

Suppose an organization has multiple Kubernetes nodes and wants to reserve a particular node for dedicated workloads.

For example, the organization wants a node to be used only by authorized GameHub workloads.

To achieve this, Kubernetes provides Taints and Tolerations.

### Office analogy

Imagine a company with multiple office rooms.

One room has a restriction:

"Only authorized employees are allowed to enter."

Similarly:

- A **taint** is applied to a Kubernetes node.
- A **toleration** is defined in a pod's specification.
- A pod with a matching toleration is allowed to run on that node.

A toleration does not guarantee that the pod will be scheduled on that node. It only allows the pod to tolerate the restriction.

---

## 3. Understanding the taint

A taint is applied to a node.

For our GameHub scenario, consider this taint:

```text
dedicated=gamehub:NoSchedule
```

It contains three important parts:

| Part | Meaning |
|---|---|
| `dedicated` | Taint key |
| `gamehub` | Taint value |
| `NoSchedule` | Taint effect |

This tells Kubernetes not to schedule new pods on that node unless they have a matching toleration.

### Applying a taint

The following command applies the taint to our Minikube node:

```powershell
kubectl taint nodes gamehub-cluster dedicated=gamehub:NoSchedule
```

Expected output:

```text
node/gamehub-cluster tainted
```

To inspect the taint:

```powershell
kubectl describe node gamehub-cluster
```

Look for the `Taints` section.

Expected:

```text
Taints: dedicated=gamehub:NoSchedule
```

**Important:** The taint belongs to the node, not to the Deployment YAML.

---

## 4. Understanding the toleration

A toleration is defined inside the pod specification.

For example:

```yaml
tolerations:
  - key: "dedicated"
    operator: "Equal"
    value: "gamehub"
    effect: "NoSchedule"
```

Understanding the fields:

| Field | Meaning |
|---|---|
| `key` | The taint key that the pod wants to tolerate |
| `operator` | Defines how the key and value are matched |
| `value` | The taint value that the pod wants to tolerate |
| `effect` | The taint effect that the pod wants to tolerate |

The above toleration matches:

```text
dedicated=gamehub:NoSchedule
```

Therefore, the pod is permitted to run on a node with that taint, subject to other scheduling requirements.

---

## 5. Practical reproduction – What we would have done

The following steps were prepared for a hands-on experiment using our existing GameHub Kubernetes namespace.

**Note: These are documented steps, not commands that were executed.**

### Step 1: Verify the Kubernetes context

```powershell
kubectl config current-context
```

Expected:

```text
gamehub-cluster
```

Check the nodes:

```powershell
kubectl get nodes -o wide
```

Check existing GameHub pods:

```powershell
kubectl get pods -n gamehub
```

### Step 2: Apply a taint

```powershell
kubectl taint nodes gamehub-cluster dedicated=gamehub:NoSchedule
```

Verify:

```powershell
kubectl describe node gamehub-cluster
```

### Step 3: Create the first Deployment YAML

File name:

`gamehub-taint-toleration-demo.yaml`

The first version intentionally does not contain a toleration.

```yaml
# GameHub scheduling demonstration
# This Deployment represents a lightweight GameHub workload.

apiVersion: apps/v1
kind: Deployment

metadata:
  # Name of our demonstration Deployment
  name: gamehub-scheduling-demo

  # Deploy inside the existing GameHub namespace
  namespace: gamehub

spec:
  # We need only one pod for this experiment
  replicas: 1

  # Kubernetes uses these labels to identify
  # which pods belong to this Deployment
  selector:
    matchLabels:
      app: gamehub
      component: scheduling-demo

  # Pod template
  template:
    metadata:
      labels:
        app: gamehub
        component: scheduling-demo

    spec:
      containers:
        - name: scheduling-demo

          # Lightweight Linux image for our experiment
          image: busybox:1.36

          # Keep the container running continuously
          command:
            - /bin/sh
            - -c
            - "while true; do echo GameHub scheduling demo; sleep 10; done"

          imagePullPolicy: IfNotPresent

      # Intentionally no tolerations section.
      # This pod cannot tolerate our node's taint.
```

Apply the YAML:

```powershell
kubectl apply -f gamehub-taint-toleration-demo.yaml
```

Expected scheduling behaviour:

```text
gamehub-scheduling-demo-xxxxx    0/1    Pending
```

The pod would remain Pending because the node has a taint and the pod does not have a matching toleration.

To investigate:

```powershell
kubectl get pods -n gamehub -o wide
```

```powershell
kubectl describe pod POD_NAME -n gamehub
```

The Events section would show a scheduling failure related to the untolerated taint.

### Step 4: Add a toleration

The second version of the YAML includes a toleration.

```yaml
# GameHub scheduling demonstration
# This Deployment represents a lightweight GameHub workload.

apiVersion: apps/v1
kind: Deployment

metadata:
  name: gamehub-scheduling-demo
  namespace: gamehub

spec:
  replicas: 1

  selector:
    matchLabels:
      app: gamehub
      component: scheduling-demo

  template:
    metadata:
      labels:
        app: gamehub
        component: scheduling-demo

    spec:

      # Allow this pod to tolerate the matching node taint.
      tolerations:
        - key: "dedicated"
          operator: "Equal"
          value: "gamehub"
          effect: "NoSchedule"

      containers:
        - name: scheduling-demo
          image: busybox:1.36

          command:
            - /bin/sh
            - -c
            - "while true; do echo GameHub scheduling demo; sleep 10; done"

          imagePullPolicy: IfNotPresent
```

Apply the updated YAML:

```powershell
kubectl apply -f gamehub-taint-toleration-demo.yaml
```

Check the pods:

```powershell
kubectl get pods -n gamehub -o wide
```

Expected behaviour:

The new pod would be permitted to run on the tainted node, assuming there are no other scheduling restrictions.

### Step 5: Verify the deployment

```powershell
kubectl describe deployment gamehub-scheduling-demo -n gamehub
```

Check logs:

```powershell
kubectl logs deployment/gamehub-scheduling-demo -n gamehub
```

Expected log output:

```text
GameHub scheduling demo
GameHub scheduling demo
GameHub scheduling demo
```

### Step 6: Clean up

Remove the demonstration Deployment:

```powershell
kubectl delete deployment gamehub-scheduling-demo -n gamehub
```

Remove the taint:

```powershell
kubectl taint nodes gamehub-cluster dedicated=gamehub:NoSchedule-
```

Verify:

```powershell
kubectl describe node gamehub-cluster
```

The taint should no longer be present.

---

## 6. Why we did not perform this experiment

**Status: Studied theoretically – Hands-on experiment not performed.**

We decided not to execute this experiment in our current GameHub cluster.

The reason is based on our current learning and project objectives.

Our immediate goal is to understand Kubernetes and successfully deploy and manage our GameHub application.

At the beginning of an application deployment, especially when working with a relatively small application, we may not need advanced scheduling configurations such as Taints and Tolerations.

For example, our current Minikube cluster has a single node. Introducing a dedicated-node restriction in this environment would demonstrate the concept, but it would not represent a necessary configuration for our current application deployment.

However, this does not mean the concept is unimportant.

As applications grow, infrastructure becomes more complex, and organizations introduce multiple nodes with different purposes, scheduling restrictions become useful.

### Why is learning still important?

As deployment engineers, we should understand:

1. What a Kubernetes feature does.
2. Why the feature exists.
3. What business or infrastructure problem it solves.
4. When it should be used.
5. Whether the current application actually needs it.

We should not introduce configurations just because Kubernetes provides them.

**Our approach:** Understand the concept now, implement it when the application or infrastructure requirements justify it.

---

## 7. Real-world use cases

| Scenario | Why Taints and Tolerations are useful |
|---|---|
| Dedicated database nodes | Reserve nodes for database workloads |
| GPU nodes | Prevent ordinary workloads from consuming expensive GPU resources |
| Special hardware nodes | Restrict workloads to nodes with specific hardware |
| Dedicated application environments | Reserve infrastructure for selected workloads |
| Infrastructure isolation | Prevent unrelated workloads from being scheduled on restricted nodes |

---

## 8. Three types of taint effects

| Effect | Behaviour |
|---|---|
| `NoSchedule` | New pods without matching tolerations cannot be scheduled. Existing pods continue running. |
| `PreferNoSchedule` | Kubernetes tries to avoid scheduling pods without matching tolerations but may still schedule them. |
| `NoExecute` | Pods without matching tolerations cannot remain on the node. Existing non-tolerating pods can be evicted. |

---

## 9. Important distinction – Taints vs Tolerations vs Affinity

| Concept | Who makes the decision? | Meaning |
|---|---|---|
| Node affinity | Pod | I want this node. |
| Node anti-affinity | Pod | I want to avoid this node. |
| Pod affinity | Pod | I want to stay near another pod. |
| Pod anti-affinity | Pod | I want to stay away from another pod. |
| Taint | Node | I reject certain pods. |
| Toleration | Pod | I can tolerate the restriction. |

### Why combine taints, tolerations and node affinity?

Consider a company that wants PostgreSQL to run exclusively on a dedicated database node.

It can:

1. Apply a taint to the database node.
2. Add a matching toleration to the PostgreSQL pod.
3. Configure node affinity to direct PostgreSQL to the database node.

This provides two protections:

- PostgreSQL is directed to the intended database node.
- Unrelated pods without matching tolerations are prevented from entering that node.

A toleration alone does not reserve a node for a particular workload.

---

## 10. Knowledge check

### Question 1

A company has a GPU node with a taint. A frontend pod has no matching toleration.

What happens?

**Answer:** The frontend pod cannot be scheduled on that node because of the taint.

### Question 2

A PostgreSQL pod has node affinity selecting the database node. Can an unrelated frontend pod still be scheduled on that database node?

**Answer:** Yes. PostgreSQL's node affinity does not restrict other pods.

### Question 3

A pod has a matching toleration for the GPU node. Does that guarantee that it will run on the GPU node?

**Answer:** No. A toleration only permits scheduling despite the taint. Node affinity or another placement rule can direct it there.

### Question 4

Why combine taints, tolerations and node affinity?

**Answer:** To reserve a node for intended workloads, allow authorized pods to use it, and direct those pods to the correct node.

---

## 11. Final takeaway

Kubernetes scheduling is not just about finding an available node.

It is also about controlling workload placement, protecting infrastructure resources and maintaining application availability.

Taints and Tolerations provide a mechanism for controlling which pods can be scheduled on particular nodes.

Although we did not perform the hands-on experiment in our current GameHub cluster, we studied the complete workflow, YAML configuration, expected behaviour, verification commands and cleanup procedure.

**Learning decision:** We will implement this feature when a real application or infrastructure requirement calls for it, rather than introducing unnecessary configurations into our current deployment.