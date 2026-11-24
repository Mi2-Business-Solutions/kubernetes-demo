# Experiment B — Resolve an Unbound PersistentVolumeClaim Using Static Provisioning

## 1. Objective

The objective of this experiment is to resolve the Unbound PersistentVolumeClaim (PVC) reproduced in Experiment A.

In Experiment A, we intentionally created a PVC without providing a suitable PersistentVolume (PV). As a result:

- PVC remained in `Pending` state.
- The Pod referencing the PVC remained in `Pending` state.
- The Deployment had zero available replicas.

In Experiment B, we will resolve this problem by manually creating a suitable PersistentVolume.

We will **reuse the existing Pending PVC** rather than deleting and recreating it.

The purpose is to understand:

- How static provisioning works.
- How Kubernetes matches a PV with a PVC.
- How Kubernetes automatically binds a suitable PV to a PVC.
- How satisfying the storage dependency allows a Pod to proceed.

---

## 2. Experiment Environment

| Component | Value |
|---|---|
| Kubernetes cluster | `gamehub-cluster` |
| Namespace | `k8s-troubleshooting` |
| Existing PVC | `gamehub-unbound-pvc` |
| Existing Deployment | `gamehub-storage-test` |
| Container image | `nginx:latest` |
| Storage request | `1G` |
| Access mode | `ReadWriteOnce` |
| PVC StorageClass | Empty string (`""`) |
| New PV name | `gamehub-static-pv` |
| PV capacity | `1G` |
| PV StorageClass | Empty string (`""`) |
| Provisioning approach | Static provisioning |

**Important boundaries:**

- Continue using the isolated `k8s-troubleshooting` namespace for this experiment's namespaced resources.
- Do not modify the default `standard` StorageClass.
- Do not modify or delete the existing GameHub PostgreSQL PV or PVC.
- Preserve the Experiment A PVC and Deployment.
- Resolve the existing Pending PVC using a newly created PV.

---

## 3. Understanding the Initial Cluster State

### 3.1 Check the current Kubernetes context

Command:

```powershell
kubectl config current-context
```

Observed output:

```text
gamehub-cluster
```

This confirms that we are working with the intended Minikube cluster.

### 3.2 Verify the existing Experiment A resources

Command:

```powershell
kubectl get pvc,pod,deploy -n k8s-troubleshooting
```

Observed output before Experiment B:

```text
NAME                                        STATUS    VOLUME   CAPACITY   ACCESS MODES   STORAGECLASS   VOLUMEATTRIBUTESCLASS   AGE
persistentvolumeclaim/gamehub-unbound-pvc   Pending                                                     <unset>                 3h5m

NAME                                        READY   STATUS    RESTARTS   AGE
pod/gamehub-storage-test-5f5d658d9d-lxsr2   0/1     Pending   0          3h6m

NAME                                         READY   UP-TO-DATE   AVAILABLE   AGE
deployment.apps/gamehub-node-affinity-hard   0/0     0            0           2d
deployment.apps/gamehub-node-affinity-soft   0/0     0            0           2d
deployment.apps/gamehub-node-selector        0/0     0            0           3d5h
deployment.apps/gamehub-storage-test         0/1     1            0           3h6m
deployment.apps/insufficient-cpu             0/0     0            0           8d
deployment.apps/insufficient-memory          0/0     0            0           9d
```

### Understanding the initial state

| Resource | Observed state | Explanation |
|---|---|---|
| `gamehub-unbound-pvc` | Pending | No suitable PV is bound |
| `gamehub-storage-test` Pod | Pending, 0/1 | Pod cannot proceed because its PVC is unbound |
| `gamehub-storage-test` Deployment | 0/1 Available | Its desired replica is not available |

The other Deployments listed belong to earlier troubleshooting experiments. They had zero desired replicas and were not part of Experiment B.

We did not modify or delete them.

**Conclusion:** Experiment A's failure state was still present. We could proceed without recreating any of its resources.

### 3.3 Inspect existing PersistentVolumes

Command:

```powershell
kubectl get pv
```

Observed output before creating the new PV:

```text
NAME                                       CAPACITY   ACCESS MODES   RECLAIM POLICY   STATUS   CLAIM                  STORAGECLASS   VOLUMEATTRIBUTESCLASS   REASON   AGE
pvc-2dec9c98-4b22-4dba-8ae5-32f75f87bd60   1Gi        RWO            Delete           Bound    gamehub/postgres-pvc   standard       <unset>                          15d
```

**Observations:**

- One PV existed in the cluster.
- Its capacity was `1Gi`.
- Its access mode was `RWO`.
- Its status was `Bound`.
- It was already claimed by `gamehub/postgres-pvc`.
- It belonged to the `standard` StorageClass.

This PV belongs to the existing GameHub PostgreSQL setup.

It was not available for our experiment.

**Important:** PersistentVolumes are cluster-scoped resources. They are not created inside a namespace.

We did not modify or delete the existing PostgreSQL PV.

---

## 4. Static Provisioning — The Approach

In Experiment A, the PVC was Pending because no suitable PV was available.

In Experiment B, we will manually create a PV that satisfies the existing PVC's requirements.

This approach is called **static provisioning**.

### What does static provisioning mean?

In static provisioning:

1. Storage is made available by an administrator or infrastructure team.
2. A PersistentVolume is manually created in Kubernetes to represent that storage.
3. An application or deployment creates a PVC requesting storage.
4. Kubernetes matches a suitable PV with the PVC.
5. Kubernetes binds the PV and PVC.

In our experiment, the PVC already exists. We are adding the missing PV.

### Important distinction

**Static provisioning does not mean manual PV-to-PVC binding.**

We manually created the PV, but Kubernetes automatically performed the matching and binding.

---

## 5. PV Configuration Decisions

Before creating the PV, we selected values that satisfy the existing PVC.

### 5.1 Storage capacity

Existing PVC request:

```yaml
resources:
  requests:
    storage: 1G
```

New PV capacity:

```yaml
capacity:
  storage: 1G
```

The PV provides the capacity requested by the PVC.

### 5.2 Access mode

Existing PVC:

```yaml
accessModes:
  - ReadWriteOnce
```

New PV:

```yaml
accessModes:
  - ReadWriteOnce
```

The access modes are compatible.

`ReadWriteOnce` means the volume can be mounted as read-write by workloads on one node at a time. It does not mean that only one Pod can ever use the volume.

### 5.3 StorageClass

Existing PVC:

```yaml
storageClassName: ""
```

New PV:

```yaml
storageClassName: ""
```

Both explicitly specify an empty StorageClass.

This is important because the PVC does not request the default `standard` StorageClass.

A PV with a different StorageClass would not satisfy this claim's StorageClass requirement.

### 5.4 Reclaim policy

We selected:

```yaml
persistentVolumeReclaimPolicy: Retain
```

`Retain` means that when the PVC is deleted, Kubernetes does not automatically delete the underlying storage.

The PV may move into a `Released` state and require manual reclamation before it can be reused.

This is a safer choice for a learning experiment where we want to avoid automatic deletion of stored data.

### 5.5 Volume type — hostPath

We selected:

```yaml
hostPath:
  path: /mnt/data/gamehub-static-storage
  type: DirectoryOrCreate
```

`hostPath` uses a directory from the filesystem of the Kubernetes node.

In our Minikube Docker-driver environment, this path refers to the Minikube node's filesystem, not directly to the Windows host filesystem.

`DirectoryOrCreate` instructs Kubernetes to create the directory if it does not already exist when the volume is set up.

This is suitable for our single-node learning experiment.

It is not a production-grade shared storage solution.

---

## 6. YAML Manifest

Filename:

`experiment-b-static-pv.yaml`

Location:

`k8s-troubleshooting/manifests/unbound-pvc/`

Manifest:

```yaml
# ============================================================
# EXPERIMENT B: Resolve an Unbound PVC Using Static Provisioning
# ============================================================
#
# Objective:
# Manually create a PersistentVolume that satisfies the
# existing Pending PVC from Experiment A.
#
# Expected result:
# PV  -> Bound
# PVC -> Bound
# Pod -> Running
#
# Important:
# We are NOT recreating the PVC.
# We are NOT modifying the default StorageClass.
# We are NOT modifying the existing PostgreSQL PV.
#
# ============================================================

apiVersion: v1

# Resource type: PersistentVolume.
kind: PersistentVolume

metadata:
  # Unique PV name across the Kubernetes cluster.
  name: gamehub-static-pv

spec:

  # Storage capacity offered by this PV.
  # The existing PVC requests 1G.
  capacity:
    storage: 1G

  # Access mode supported by this volume.
  # Must satisfy the existing PVC's access mode.
  accessModes:
    - ReadWriteOnce

  # Retain the underlying storage when the PVC is deleted.
  # Manual reclamation may be required before reuse.
  persistentVolumeReclaimPolicy: Retain

  # Explicitly configure an empty StorageClass.
  # This must match the existing PVC's storageClassName: "".
  storageClassName: ""

  # Use a directory on the Minikube node's filesystem.
  hostPath:
    # Directory where the volume's data will be stored.
    path: /mnt/data/gamehub-static-storage

    # Create the directory automatically if it does not exist.
    type: DirectoryOrCreate
```

### Understanding the manifest

| Field | Value | Purpose |
|---|---|---|
| `apiVersion` | `v1` | Core Kubernetes API |
| `kind` | `PersistentVolume` | Creates a PV |
| `metadata.name` | `gamehub-static-pv` | Unique cluster-wide PV name |
| `capacity.storage` | `1G` | Storage capacity offered |
| `accessModes` | `ReadWriteOnce` | Access mode supported |
| `persistentVolumeReclaimPolicy` | `Retain` | Preserves underlying storage after claim deletion |
| `storageClassName` | `""` | Matches the existing PVC |
| `hostPath.path` | `/mnt/data/gamehub-static-storage` | Node filesystem directory |
| `hostPath.type` | `DirectoryOrCreate` | Creates the directory if needed |

**Important:** Unlike a PVC, a PV does not have a namespace because it is cluster-scoped.

---

## 7. Validate the PV Manifest

Before creating the actual PV, we validated the YAML using a client-side dry run.

Command used:

```powershell
kubectl apply --dry-run=client -f "k8s-troubleshooting\manifests\unbound-pvc\experiment-b-static-pv.yaml"
```

Observed successful output:

```text
persistentvolume/gamehub-static-pv created (dry run)
```

### What does dry-run mean?

The `--dry-run=client` option validates the manifest without creating the actual Kubernetes resource.

It helps identify manifest and client-side validation problems before applying the resource.

**Important:** The output `created (dry run)` does not mean that the PV was actually created in the cluster.

---

## 8. Create the PersistentVolume

After validation, we created the actual PV.

Command:

```powershell
kubectl apply -f "k8s-troubleshooting\manifests\unbound-pvc\experiment-b-static-pv.yaml"
```

Observed output:

```text
persistentvolume/gamehub-static-pv created
```

This confirms that Kubernetes successfully created the PersistentVolume resource.

Unlike a PVC, the PV was created at the cluster level.

---

## 9. Inspect the New PersistentVolume

Command:

```powershell
kubectl get pv gamehub-static-pv
```

Observed output:

```text
NAME                CAPACITY   ACCESS MODES   RECLAIM POLICY   STATUS   CLAIM                                     STORAGECLASS   VOLUMEATTRIBUTESCLASS   REASON   AGE
gamehub-static-pv   1G         RWO            Retain           Bound    k8s-troubleshooting/gamehub-unbound-pvc                  <unset>                          31s
```

### 9.1 Understanding the output

| Field | Observed value | Explanation |
|---|---|---|
| NAME | `gamehub-static-pv` | Name of our newly created PV |
| CAPACITY | `1G` | Storage capacity offered |
| ACCESS MODES | `RWO` | ReadWriteOnce |
| RECLAIM POLICY | `Retain` | Underlying storage is retained |
| STATUS | `Bound` | PV is already bound to a PVC |
| CLAIM | `k8s-troubleshooting/gamehub-unbound-pvc` | Namespace and name of the PVC using this PV |
| STORAGECLASS | Blank | PV has no StorageClass |

### 9.2 An important observation

We expected the new PV to initially be `Available`.

However, the actual output showed:

```text
STATUS   CLAIM
Bound    k8s-troubleshooting/gamehub-unbound-pvc
```

The PV was already `Bound` when we inspected it.

**Why?**

As soon as the PV was created, Kubernetes identified the existing Pending PVC as a suitable claim and automatically bound the two resources.

We did not manually assign the PVC to the PV.

This is the central learning outcome of Experiment B.

---

## 10. Verify the Existing PVC

After observing the PV binding, we checked the original PVC.

Command:

```powershell
kubectl get pvc gamehub-unbound-pvc -n k8s-troubleshooting
```

Observed output:

```text
NAME                  STATUS   VOLUME              CAPACITY   ACCESS MODES   STORAGECLASS   VOLUMEATTRIBUTESCLASS   AGE
gamehub-unbound-pvc   Bound    gamehub-static-pv   1G         RWO                           <unset>                 3h12m
```

### 10.1 Understanding the output

| Field | Observed value | Explanation |
|---|---|---|
| NAME | `gamehub-unbound-pvc` | Original PVC from Experiment A |
| STATUS | `Bound` | PVC successfully obtained storage |
| VOLUME | `gamehub-static-pv` | New PV assigned to this PVC |
| CAPACITY | `1G` | Bound PV capacity |
| ACCESS MODES | `RWO` | ReadWriteOnce |
| STORAGECLASS | Blank | No StorageClass was used |
| AGE | `3h12m` | Original PVC continued to exist |

### 10.2 Important evidence — PVC age

Notice the PVC age:

```text
3h12m
```

The PVC was already approximately three hours old before Experiment B.

Its age continued increasing rather than resetting.

This confirms that we resolved the original PVC instead of deleting and recreating it.

**Conclusion:** The same PVC that was Pending in Experiment A became Bound after we created a suitable PV.

---

## 11. Before-and-After Comparison

### Before Experiment B

The resource state was:

| Resource | State | Explanation |
|---|---|---|
| PVC | Pending | No PV was assigned |
| Pod | Pending, 0/1 | Waiting for its storage dependency |
| Deployment | 0/1 Available | No available replica |
| Suitable PV | Not available | Existing PV was already claimed by PostgreSQL |

The original PVC could not obtain storage.

### After Experiment B

The final state recorded during the experiment was:

| Resource | State | Explanation |
|---|---|---|
| PVC | Bound | Original PVC obtained storage |
| PV | Bound | `gamehub-static-pv` assigned to the PVC |
| Pod | Running, 1/1 | Storage dependency was satisfied and the Pod started |
| Deployment | 1/1 Available | Desired replica became available |

**Important evidence:** The final PVC output explicitly identifies `gamehub-static-pv` as its assigned volume. The Pod and Deployment were also reported as recovered in the Experiment B discussion.

The raw final combined `kubectl get pvc,pod,deploy` output was not captured in the discussion, so the Pod and Deployment states above are recorded as the reported final states rather than reproduced terminal output.

### The most important change

```text
BEFORE EXPERIMENT B

PVC:        Pending
Pod:        Pending
Deployment: 0/1 Available
PV:         No suitable available PV


AFTER EXPERIMENT B

PVC:        Bound
Pod:        Running (1/1)
Deployment: 1/1 Available
PV:         gamehub-static-pv
```

---

## 12. Root Cause Resolution

### Root cause identified in Experiment A

The original problem was:

**No suitable PersistentVolume was available to satisfy the PVC, and the PVC explicitly requested no StorageClass.**

The PVC configuration included:

```yaml
storageClassName: ""
```

This prevented default StorageClass assignment.

There was no suitable PV with an empty StorageClass available to satisfy the claim.

Therefore, the PVC remained Pending.

### Resolution performed in Experiment B

We manually created a PV with:

```yaml
capacity:
  storage: 1G

accessModes:
  - ReadWriteOnce

storageClassName: ""
```

These properties satisfied the existing PVC's requirements.

Kubernetes automatically matched and bound the resources.

### Resolution flow

```text
EXPERIMENT A
     |
     v
PVC remains Pending
     |
     v
No suitable PV available
     |
     v
Pod remains Pending
     |
     v
Deployment has 0 available replicas
     |
     |
     v
EXPERIMENT B
     |
     v
Manually create gamehub-static-pv
     |
     v
PV satisfies existing PVC requirements
     |
     v
Kubernetes automatically binds PV and PVC
     |
     v
PVC becomes Bound
     |
     v
Pod can proceed with volume setup and startup
     |
     v
Deployment becomes available
```

---

## 13. Important Learnings

### Learning 1: Static provisioning means manually creating the PV

In this experiment, we manually created the PersistentVolume.

We did not depend on the default StorageClass or its dynamic provisioner to create the PV.

### Learning 2: Kubernetes automatically performs PV-to-PVC binding

Although we manually created the PV, Kubernetes performed the matching and binding automatically.

We did not need to edit the PVC or manually specify the PV name in it.

### Learning 3: A Pending PVC can become Bound without being recreated

Our original PVC remained in the cluster throughout the experiment.

Once a suitable PV became available, Kubernetes bound it to the existing PVC.

This is an important troubleshooting lesson: a Pending PVC does not necessarily need to be deleted and recreated.

### Learning 4: StorageClass compatibility matters

The PVC and PV both had:

```yaml
storageClassName: ""
```

Their StorageClass requirements matched.

An empty StorageClass does not prevent a PVC from binding to a PV. It means that a suitable PV without a StorageClass must be available.

### Learning 5: PV capacity and access modes must satisfy the claim

The PVC requested `1G` and `ReadWriteOnce`.

Our PV provided `1G` and `ReadWriteOnce`.

Kubernetes was therefore able to match the resources.

### Learning 6: PVs are cluster-scoped, while PVCs are namespaced

Our PV was created without a namespace.

Our PVC remained inside:

```text
k8s-troubleshooting
```

The PV's claim reference showed:

```text
k8s-troubleshooting/gamehub-unbound-pvc
```

This demonstrates how a cluster-scoped PV can be bound to a namespaced PVC.

### Learning 7: Storage provisioning and application availability are connected

A Deployment can exist while its Pod is unable to start.

The application depends on storage, and the storage dependency must be satisfied before the Pod can complete its volume setup and proceed.

Resolving the PVC problem allowed the application workload to recover.

### Learning 8: Reclaim policy controls what happens to storage after claim deletion

We selected:

```yaml
persistentVolumeReclaimPolicy: Retain
```

This protects the underlying storage from automatic deletion when the PVC is removed.

However, retaining storage also means that an administrator may need to handle the PV's reclamation and reuse manually.

---

## 14. Deployment Engineer's Perspective

When a deployment is blocked by an unbound PVC, a deployment engineer should investigate the storage requirements before changing the application Deployment.

A practical investigation should include:

1. Does the PVC exist?
2. Is the PVC Pending or Bound?
3. What storage capacity does it request?
4. Which access modes does it require?
5. Does it specify a StorageClass?
6. Is the StorageClass omitted or explicitly empty?
7. Does a suitable PV already exist?
8. Is the PV already claimed by another PVC?
9. Is static provisioning appropriate for the infrastructure?
10. Does the PV satisfy the PVC's requirements?
11. Does the PVC become Bound after a suitable PV is created?
12. Can the Pod proceed with volume setup and startup?
13. Does the Deployment become available?

### When might an engineer choose static provisioning?

Static provisioning can be useful when:

- Storage has already been created outside Kubernetes.
- An organization manages storage centrally.
- Specific existing storage volumes must be exposed to workloads.
- The infrastructure does not provide a suitable dynamic provisioner.
- Storage allocation needs to be explicitly controlled.

The decision depends on the organization's infrastructure, storage platform, operational requirements, and application needs.

### Important limitation of our experiment

We used `hostPath` because we are working with a single-node Minikube learning environment.

It is not a general production storage recommendation.

In a multi-node production cluster, a node-local path may not be accessible from another node. Production workloads generally need an appropriate storage backend that satisfies their availability, durability, performance, and access requirements.

Also, the PV's declared capacity is Kubernetes storage metadata; it does not by itself reserve or enforce a physical 1G quota on the hostPath directory.

---

## 15. Experiment B — Final Conclusion

**Experiment B successfully resolved the Unbound PersistentVolumeClaim reproduced in Experiment A using static provisioning.**

We manually created:

```text
gamehub-static-pv
```

The PV had:

- Capacity: `1G`
- Access mode: `ReadWriteOnce`
- StorageClass: Empty (`""`)
- Reclaim policy: `Retain`
- Volume type: `hostPath`

Kubernetes automatically matched this PV with the existing:

```text
gamehub-unbound-pvc
```

The PVC transitioned from `Pending` to `Bound`.

The Pod and Deployment were reported as recovered after the storage dependency was satisfied.

Most importantly:

- We did not delete or recreate the original PVC.
- We did not modify the existing PostgreSQL PV or PVC.
- We did not modify the default `standard` StorageClass.
- We manually provisioned the PV.
- Kubernetes automatically performed the binding.

**The key learning:** Static provisioning requires the storage administrator or deployment engineer to make a suitable PV available. Kubernetes can then automatically bind that PV to a compatible PVC.

---

## 16. Experiment A and Experiment B — Combined Learning

| Area | Experiment A | Experiment B |
|---|---|---|
| Objective | Reproduce an unbound PVC | Resolve the unbound PVC |
| PV | No suitable PV available | Manually created PV |
| Provisioning | No storage provisioned for the claim | Static provisioning |
| PVC | Pending | Bound |
| Pod | Pending | Running |
| Deployment | 0/1 Available | 1/1 Available |
| PVC recreated? | No | No |
| Kubernetes binding | No matching PV | Automatic PV-to-PVC binding |

Together, these experiments demonstrate the complete troubleshooting lifecycle:

**Reproduce the failure → Identify the root cause → Apply the storage fix → Verify PVC binding → Verify workload recovery.**

---

## 17. Next Learning Direction

The next useful step is to explore what happens to a PV and its underlying storage when a PVC is deleted.

This will help us understand:

- PV lifecycle.
- PVC lifecycle.
- `Retain` versus `Delete` reclaim policies.
- `Released` versus `Available` PV states.
- What an engineer must do before reusing retained storage.

We should continue with a separate, controlled experiment without disturbing the existing GameHub PostgreSQL storage or the resources we want to preserve.