# Experiment D – Dynamic Provisioning with WaitForFirstConsumer (WFFC)

## 1. Objective

The objective of this experiment is to understand how Kubernetes handles dynamic volume provisioning when a StorageClass uses:

```yaml
volumeBindingMode: WaitForFirstConsumer
```

In the previous experiment (Experiment C), we used the default StorageClass, which had:

```yaml
volumeBindingMode: Immediate
```

With `Immediate`, Kubernetes provisions and binds storage as soon as the PVC is created.

In this experiment, we want to observe how the workflow changes when we use `WaitForFirstConsumer`.

### What we want to understand

- What happens when a PVC using WFFC is created without a Pod?
- What changes when a Pod references that PVC?
- How does Kubernetes coordinate Pod scheduling and volume provisioning?
- What happens if the storage provisioner does not have sufficient RBAC permissions?

---

## 2. Understand the Expected Behaviour

### Immediate vs WaitForFirstConsumer

| Behaviour | Immediate | WaitForFirstConsumer |
|---|---|---|
| When does provisioning begin? | When the PVC is created | When a Pod consumes the PVC |
| Does a Pod need to reference the PVC first? | No | Yes |
| When does binding happen? | Before Pod scheduling | Coordinated with Pod scheduling |
| Main purpose | Provision storage immediately | Coordinate storage provisioning with workload scheduling |

### Expected WFFC workflow

```text
Create StorageClass
       |
       v
Create PVC
       |
       v
PVC remains Pending
       |
       v
Create Pod referencing PVC
       |
       v
Kubernetes scheduling workflow
       |
       v
Select a suitable node
       |
       v
Provisioner receives provisioning request
       |
       v
Create PersistentVolume
       |
       v
PVC binds to PV
       |
       v
Pod can proceed with scheduling and startup
```

**Important:** WFFC does not mean Kubernetes waits until the Pod is running. The Pod only needs to reference the PVC to trigger the scheduling and provisioning workflow.

---

## 3. Create a Dedicated StorageClass

We created a separate StorageClass for this experiment rather than modifying the existing default StorageClass.

### Manifest: `experiment-d-wffc-storageclass.yaml`

```yaml
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: gamehub-wffc
provisioner: k8s.io/minikube-hostpath
volumeBindingMode: WaitForFirstConsumer
reclaimPolicy: Delete
```

### Important fields

| Field | Explanation |
|---|---|
| `provisioner` | Identifies the component responsible for dynamically provisioning storage |
| `volumeBindingMode` | Controls when provisioning and binding should happen |
| `WaitForFirstConsumer` | Delays provisioning and binding until a Pod consumes the PVC |
| `reclaimPolicy: Delete` | Controls what happens to the dynamically provisioned PV when its PVC is deleted |

### Apply the StorageClass

```powershell
kubectl apply -f .\k8s-troubleshooting\manifests\unbound-pvc\experiment-d-wffc-storageclass.yaml
```

Output:

```text
storageclass.storage.k8s.io/gamehub-wffc created
```

---

## 4. Create a PVC Using the WFFC StorageClass

We created a PVC that explicitly references our new StorageClass.

### Manifest: `experiment-d-wffc-pvc.yaml`

```yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: gamehub-wffc-pvc
  namespace: k8s-troubleshooting
spec:
  accessModes:
    - ReadWriteOnce
  storageClassName: gamehub-wffc
  resources:
    requests:
      storage: 1G
```

### Important fields

| Field | Explanation |
|---|---|
| `accessModes` | Specifies how the volume can be mounted by workloads |
| `storageClassName` | Connects this PVC to our `gamehub-wffc` StorageClass |
| `resources.requests.storage` | Requests 1 GB of storage |

**Note about storage units:**

Kubernetes accepts both `1G` and `1Gi`.

- `1G` = 1,000,000,000 bytes
- `1Gi` = 1,073,741,824 bytes

They are different quantities, but both are valid storage requests.

### Apply the PVC

```powershell
kubectl apply -f .\k8s-troubleshooting\manifests\unbound-pvc\experiment-d-wffc-pvc.yaml
```

Output:

```text
persistentvolumeclaim/gamehub-wffc-pvc created
```

### Observation: PVC before Pod creation

The PVC status was:

```text
STATUS
Pending
```

This was the expected behaviour.

**Why?**

The StorageClass uses `WaitForFirstConsumer`.

Kubernetes does not immediately provision and bind the volume when the PVC is created. It waits for a Pod to consume the PVC.

At this stage:

- StorageClass exists.
- PVC exists.
- No Pod references the PVC.
- PVC remains Pending.

This is not an error. It is the intended WFFC behaviour.

---

## 5. Create a Pod That Consumes the PVC

Next, we created a Pod that references our PVC.

### What does "consume a PVC" mean?

A Pod consumes a PVC when it references that PVC in its `spec.volumes` configuration.

The container can then access that volume through a `volumeMounts` entry.

The relationship is:

```text
Pod
 |
 | references
 v
PVC
 |
 | binds to
 v
PV
```

### Manifest: `experiment-d-wffc-pod.yaml`

```yaml
# Experiment D: Pod that consumes the WaitForFirstConsumer PVC

apiVersion: v1
kind: Pod

metadata:
  name: gamehub-wffc-pod
  namespace: k8s-troubleshooting

spec:
  containers:
    - name: nginx
      image: nginx

      # Makes the Pod volume accessible inside the container.
      volumeMounts:
        - name: gamehub-storage
          mountPath: /data

  # Connects the Pod to the PVC.
  volumes:
    - name: gamehub-storage
      persistentVolumeClaim:
        claimName: gamehub-wffc-pvc
```

### Important configuration

The following part connects the Pod to the PVC:

```yaml
volumes:
  - name: gamehub-storage
    persistentVolumeClaim:
      claimName: gamehub-wffc-pvc
```

The following part makes the volume accessible inside the container:

```yaml
volumeMounts:
  - name: gamehub-storage
    mountPath: /data
```

The volume name `gamehub-storage` must match in both places.

We did not write or test any files inside the mounted volume. That was not required for this experiment.

### Apply the Pod

```powershell
kubectl apply -f .\k8s-troubleshooting\manifests\unbound-pvc\experiment-d-wffc-pod.yaml
```

---

## 6. Observe the Pod and PVC

After creating the Pod, we checked the resources.

```powershell
kubectl get pod,pvc -n k8s-troubleshooting
```

### Observation

Both the Pod and PVC remained Pending.

The Pod had:

```text
NODE: <none>
```

The PVC had:

```text
STATUS: Pending
```

At first, this might look like WFFC did not work. However, we needed to investigate the events to understand what was happening.

---

## 7. Troubleshoot the Pod

We inspected the Pod:

```powershell
kubectl describe pod gamehub-wffc-pod -n k8s-troubleshooting
```

### Important observations

```text
Node: <none>
```

The Pod had not been assigned to a node.

We also observed:

```text
NominatedNodeName: gamehub-cluster
```

### What does this mean?

`NominatedNodeName` and `Node` are not the same thing.

| Field | Meaning |
|---|---|
| `Node` | The node to which the Pod has actually been assigned |
| `NominatedNodeName` | A node nominated as a candidate during scheduling |

The nominated node indicated that `gamehub-cluster` was being considered in the scheduling workflow.

However, the Pod had not actually been assigned to it.

This was an important clue, but we needed to inspect the PVC as well.

---

## 8. Troubleshoot the PVC

We inspected the PVC:

```powershell
kubectl describe pvc gamehub-wffc-pvc -n k8s-troubleshooting
```

### Important observations

The PVC was still Pending.

We found the following information:

```text
Used By: gamehub-wffc-pod
```

This confirmed that the Pod was referencing the PVC.

We also found:

```text
volume.kubernetes.io/selected-node: gamehub-cluster
```

This indicated that the scheduling workflow had selected a node for the volume provisioning process.

### Important events

The PVC showed events similar to:

```text
WaitForFirstConsumer:
waiting for first consumer to be created before binding

ExternalProvisioning:
waiting for a volume to be created by the external provisioner

ProvisioningFailed:
failed to get target node: nodes "gamehub-cluster" is forbidden:
User "system:serviceaccount:kube-system:storage-provisioner"
cannot get resource "nodes" in API group "" at the cluster scope
```

### What did we learn?

The first two events showed that:

1. Kubernetes initially waited for a Pod to consume the PVC.
2. After the Pod referenced the PVC, the provisioning workflow was triggered.
3. The external provisioner attempted to provision the volume.
4. Provisioning failed because the provisioner could not retrieve information about the selected node.

This was no longer a case of the PVC waiting for a consumer.

The Pod was already referencing the PVC. The failure was happening during provisioning.

---

## 9. Investigate the RBAC Permission

The error specifically mentioned:

```text
User "system:serviceaccount:kube-system:storage-provisioner"
cannot get resource "nodes"
```

This indicated an RBAC permission issue.

### What is RBAC?

RBAC stands for Role-Based Access Control.

Kubernetes uses RBAC to control what users, groups, and ServiceAccounts are allowed to do.

For example, a ServiceAccount might be allowed to:

- Read Pods.
- Read Services.
- Create PersistentVolumes.
- Read StorageClasses.

But it might not be allowed to read Nodes.

### Identify the provisioner's ServiceAccount

The error identified the ServiceAccount:

```text
storage-provisioner
```

It belongs to the namespace:

```text
kube-system
```

This is important because the PVC belongs to `k8s-troubleshooting`, but the provisioner runs with its own identity in `kube-system`.

### Check whether the ServiceAccount can read Nodes

We ran:

```powershell
kubectl auth can-i get nodes --as=system:serviceaccount:kube-system:storage-provisioner
```

Output:

```text
Warning: resource 'nodes' is not namespace scoped
no
```

The important result was:

```text
no
```

This confirmed that the ServiceAccount did not have permission to retrieve Nodes.

The warning simply tells us that Nodes are cluster-scoped resources, not namespace-scoped resources.

### Inspect the ClusterRole

We checked the ClusterRole:

```powershell
kubectl describe clusterrole system:persistent-volume-provisioner
```

Its rules included permissions for resources such as:

```text
persistentvolumes
persistentvolumeclaims
storageclasses.storage.k8s.io
events
events.events.k8s.io
```

However, there was no permission for:

```text
nodes
```

### Inspect the ClusterRoleBinding

We also checked:

```powershell
kubectl describe clusterrolebinding storage-provisioner
```

It showed that the ClusterRole was assigned to:

```text
ServiceAccount: storage-provisioner
Namespace: kube-system
```

This helped us identify the exact identity and role involved in the failure.

---

## 10. Check the Provisioner Logs

We checked whether the provisioner was running:

```powershell
kubectl get pods -n kube-system | Select-String "storage-provisioner"
```

Output:

```text
storage-provisioner  1/1 Running
```

The provisioner Pod was running.

However, a Running Pod does not automatically mean that its application has all the permissions it needs.

Next, we checked its logs:

```powershell
kubectl logs storage-provisioner -n kube-system --tail=30
```

The important log messages were:

```text
provision "k8s-troubleshooting/gamehub-wffc-pvc"
class "gamehub-wffc": started
```

And then:

```text
failed to get target node: nodes "gamehub-cluster" is forbidden:
User "system:serviceaccount:kube-system:storage-provisioner"
cannot get resource "nodes" in API group "" at the cluster scope
```

### Interpretation

The logs confirmed the same failure we found in the PVC events.

The provisioner received the provisioning request and attempted to retrieve the selected node.

Kubernetes denied that request because the ServiceAccount did not have the required permission.

The provisioner process itself was running, but its request to the Kubernetes API server was forbidden.

---

## 11. Why Does the Provisioner Need Node Information?

This is an important concept to understand.

With WFFC, Kubernetes coordinates Pod scheduling with volume provisioning.

Consider a cluster with multiple nodes:

```text
                 Kubernetes Cluster
                         |
          +--------------+--------------+
          |              |              |
        Node A         Node B         Node C
          |              |              |
       Storage A      Storage B      Storage C
```

Imagine that storage is available only on certain nodes, or that the storage system has topology constraints.

The scheduler needs to identify a suitable node for the Pod.

The provisioning component may need information about that selected node to create storage that is compatible with the scheduling decision.

In our Minikube experiment:

1. The Pod referenced the PVC.
2. The scheduling workflow selected `gamehub-cluster`.
3. The provisioner received the provisioning request.
4. The provisioner attempted to retrieve information about `gamehub-cluster`.
5. Its ServiceAccount lacked permission to get Nodes.
6. The API server denied the request.
7. Dynamic provisioning failed.

**Important distinction:** The provisioner is not reading what is happening inside the node or monitoring its Pods. It is attempting to retrieve the selected Node resource from the Kubernetes API.

---

## 12. Root Cause Analysis

| Area | Finding |
|---|---|
| StorageClass | Created successfully |
| Volume binding mode | `WaitForFirstConsumer` |
| PVC creation | Successful |
| Initial PVC status | Pending, as expected |
| Pod creation | Successful |
| Pod references PVC | Yes |
| Scheduling workflow | Selected node information was recorded |
| Provisioner Pod | Running |
| Provisioning request | Received by provisioner |
| Provisioning result | Failed |
| Root cause | Provisioner's ServiceAccount lacked permission to get Nodes |
| RBAC verification | `kubectl auth can-i` returned `no` |

### Root cause

The Minikube hostpath storage provisioner attempted to retrieve the selected Node resource during dynamic provisioning.

However, the ClusterRole associated with its ServiceAccount did not include permission to get Nodes.

As a result, the provisioner could not complete the volume provisioning request.

### Why we did not modify RBAC

We deliberately stopped after identifying the root cause.

Changing permissions on a cluster-level ServiceAccount and ClusterRole would alter the cluster's RBAC configuration.

For this learning experiment, identifying and proving the cause was sufficient. We did not need to modify cluster-wide permissions to understand WFFC.

---

## 13. Experiment Result

| Expected behaviour | Observed result |
|---|---|
| PVC remains Pending before a consumer exists | Yes |
| Creating a Pod referencing the PVC triggers the workflow | Yes |
| Scheduling workflow identifies a selected node | Yes, selected-node information was recorded |
| Provisioner receives the provisioning request | Yes |
| Dynamic PV gets created | No |
| PVC becomes Bound | No |
| Pod becomes Running | No |

### Final conclusion

We successfully observed the key WFFC behaviour:

- The PVC remained Pending before a Pod consumed it.
- Creating a Pod referencing the PVC triggered the scheduling and provisioning workflow.
- Kubernetes recorded the selected node.
- The provisioner received the request but failed because of insufficient RBAC permissions.

Therefore, the experiment demonstrated the WFFC workflow and exposed a provisioning failure caused by the Minikube provisioner's permissions.

We did not achieve a Bound PVC or a Running Pod in this experiment.

---

## 14. Deployment Engineer's Perspective

In a real deployment, a Pending PVC should not immediately be treated as a storage-capacity problem.

An engineer should investigate the complete provisioning workflow.

A useful troubleshooting sequence is:

```text
PVC is Pending
      |
      v
Check PVC events
      |
      v
Is there a consuming Pod?
      |
      +---- No ----> Check StorageClass binding mode
      |
      v
Inspect the consuming Pod
      |
      v
Check scheduling events and selected node
      |
      v
Check provisioner status and logs
      |
      v
Check ServiceAccount and RBAC permissions
      |
      v
Identify the actual provisioning failure
```

### Useful commands

| Purpose | Command |
|---|---|
| Check PVC status | `kubectl get pvc -n k8s-troubleshooting` |
| Inspect PVC events | `kubectl describe pvc gamehub-wffc-pvc -n k8s-troubleshooting` |
| Inspect Pod scheduling | `kubectl describe pod gamehub-wffc-pod -n k8s-troubleshooting` |
| Check StorageClasses | `kubectl get storageclass` |
| Check provisioner Pod | `kubectl get pods -n kube-system` |
| Read provisioner logs | `kubectl logs storage-provisioner -n kube-system --tail=30` |
| Verify Node permission | `kubectl auth can-i get nodes --as=system:serviceaccount:kube-system:storage-provisioner` |
| Inspect ClusterRole | `kubectl describe clusterrole system:persistent-volume-provisioner` |
| Inspect ClusterRoleBinding | `kubectl describe clusterrolebinding storage-provisioner` |

---

## 15. Key Takeaways

1. `Immediate` provisions and binds storage when the PVC is created.
2. `WaitForFirstConsumer` delays provisioning and binding until a Pod consumes the PVC.
3. Consuming a PVC means referencing it in the Pod's volume configuration.
4. WFFC helps coordinate storage provisioning with Pod scheduling.
5. A Pod can reference a PVC without becoming Running.
6. `NominatedNodeName` does not mean the Pod has been assigned to that node.
7. A provisioner Pod being Running does not guarantee that provisioning will succeed.
8. Storage provisioning can fail because of RBAC permissions.
9. PVC events and provisioner logs are valuable sources of troubleshooting information.
10. A good deployment engineer identifies the root cause before changing cluster-level configuration.

### Interview-ready explanation

**What is WaitForFirstConsumer?**

`WaitForFirstConsumer` is a StorageClass volume binding mode that delays dynamic volume provisioning and binding until a Pod references the PVC. This allows Kubernetes to coordinate storage provisioning with Pod scheduling, which is particularly useful when storage has topology or node-placement constraints.

**What did you observe in your WFFC experiment?**

I created a dedicated StorageClass using WFFC and a PVC referencing it. The PVC initially remained Pending, as expected. After creating a Pod that referenced the PVC, the scheduling and provisioning workflow started. However, the Minikube hostpath provisioner failed because its ServiceAccount did not have permission to get Nodes. I verified this using PVC events, provisioner logs, and `kubectl auth can-i`.

---

**Experiment D status: Workflow observed; provisioning failure diagnosed; RBAC left unchanged.**