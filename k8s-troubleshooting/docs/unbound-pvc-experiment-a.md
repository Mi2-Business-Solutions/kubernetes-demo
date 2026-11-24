# Experiment A — Reproducing an Unbound PersistentVolumeClaim (PVC)

## 1. Objective

The objective of this experiment is to intentionally reproduce an **Unbound PersistentVolumeClaim (PVC)** and understand how an unbound PVC affects a Pod.

We will create:
- A PVC requesting storage.
- A Deployment that references the PVC.
- No matching PersistentVolume (PV).

We expect the PVC and the Deployment's Pod to remain in `Pending` state.

The purpose is to understand the failure before attempting to resolve it through static provisioning in Experiment B.

---

## 2. Experiment Environment

| Component | Value |
|---|---|
| Kubernetes cluster | `gamehub-cluster` |
| Namespace | `k8s-troubleshooting` |
| PVC name | `gamehub-unbound-pvc` |
| Deployment name | `gamehub-storage-test` |
| Container image | `nginx:latest` |
| Storage request | `1G` |
| Access mode | `ReadWriteOnce` |
| StorageClass | Empty string (`""`) |
| Matching PV | Not available |

**Important:** This experiment is isolated in the `k8s-troubleshooting` namespace. Existing GameHub application resources and PostgreSQL storage must not be modified.

---

## 3. Understanding the Initial Cluster State

### 3.1 Check the current Kubernetes context

Command:

```powershell
kubectl config current-context
```

Expected context:

```text
gamehub-cluster
```

This confirms that we are working with the intended Minikube cluster.

### 3.2 Verify the namespace

Command:

```powershell
kubectl get namespace k8s-troubleshooting
```

The namespace existed, so there was no need to create it.

### 3.3 Inspect existing PersistentVolumes

Command:

```powershell
kubectl get pv
```

Observed output:

```text
NAME                                       CAPACITY   ACCESS MODES   RECLAIM POLICY   STATUS   CLAIM                  STORAGECLASS
pvc-2dec9c98-4b22-4dba-8ae5-32f75f87bd60   1Gi        RWO            Delete           Bound    gamehub/postgres-pvc   standard
```

**Observations:**

- One PV was listed.
- Its capacity was `1Gi`.
- Its status was `Bound`.
- It was already claimed by `gamehub/postgres-pvc`.
- It belonged to the `standard` StorageClass.

Therefore, this PV was not available for our experiment.

We did not modify or delete it.

**Conclusion:** No suitable available PV was shown for our experiment.

---

## 4. Important StorageClass Decision

Our Minikube cluster has a default StorageClass named `standard`.

Its provisioner is:

```text
k8s.io/minikube-hostpath
```

If `storageClassName` is omitted from a PVC, Kubernetes can assign the default StorageClass. That can allow dynamic provisioning.

However, our objective is to reproduce an unbound PVC without using the default StorageClass.

Therefore, we explicitly configured:

```yaml
storageClassName: ""
```

This is different from omitting the field.

| Configuration | Meaning |
|---|---|
| `storageClassName` omitted | Eligible for default StorageClass assignment |
| `storageClassName: standard` | Explicitly requests the `standard` StorageClass |
| `storageClassName: ""` | Explicitly requests no StorageClass |

**Important:** An empty StorageClass does not mean that the PVC cannot bind to any PV. It can still bind to a suitable existing PV that has no StorageClass. Our experiment is designed without such a PV.

---

## 5. YAML Manifest

Filename:

`experiment-a-unbound-pvc.yaml`

Location:

`k8s-troubleshooting/manifests/unbound-pvc/`

```yaml
# ============================================================
# EXPERIMENT A: Reproduce an Unbound PersistentVolumeClaim
# ============================================================
#
# Objective:
# Intentionally create a PVC that cannot find suitable storage.
#
# Expected result:
# PVC -> Pending
# Pod -> Pending
#
# Important:
# We are NOT creating a PersistentVolume in this experiment.
# We are also preventing the default StorageClass from being used.
#
# ============================================================


# ------------------------------------------------------------
# RESOURCE 1: PersistentVolumeClaim
# ------------------------------------------------------------

apiVersion: v1
kind: PersistentVolumeClaim

metadata:
  name: gamehub-unbound-pvc
  namespace: k8s-troubleshooting

spec:

  # Request read-write access from a single node.
  accessModes:
    - ReadWriteOnce

  # Explicitly request storage without a StorageClass.
  # This prevents default StorageClass assignment.
  storageClassName: ""

  # Request one decimal gigabyte of storage.
  resources:
    requests:
      storage: 1G


---
# ------------------------------------------------------------
# RESOURCE 2: Deployment
# ------------------------------------------------------------

apiVersion: apps/v1
kind: Deployment

metadata:
  name: gamehub-storage-test
  namespace: k8s-troubleshooting

spec:

  # We need only one Pod for this experiment.
  replicas: 1

  selector:
    matchLabels:
      app: gamehub-storage-test

  template:
    metadata:
      labels:
        app: gamehub-storage-test

    spec:

      containers:
        - name: nginx
          image: nginx:latest

          # Mount the PVC inside the nginx container.
          volumeMounts:
            - name: application-storage
              mountPath: /usr/share/nginx/html

      # Reference the PVC created above.
      volumes:
        - name: application-storage
          persistentVolumeClaim:
            claimName: gamehub-unbound-pvc
```

### 5.1 Storage quantity validation issue

Initially, the YAML contained:

```yaml
storage: 1GB
```

When we applied the manifest, Kubernetes returned:

```text
PersistentVolumeClaim in version "v1" cannot be handled
as a PersistentVolumeClaim:
quantities must match the regular expression ...
```

The reason was that `1GB` is not a valid Kubernetes quantity suffix.

We corrected it to:

```yaml
storage: 1G
```

For reference:

| Quantity | Meaning |
|---|---|
| `1G` | One gigabyte (decimal) |
| `1Gi` | One gibibyte (binary) |
| `1GB` | Invalid Kubernetes quantity |
| `1Gb` | Invalid Kubernetes quantity |

We retained the intended one-gigabyte storage requirement using `1G`.

---

## 6. Applying the Manifest

Command:

```powershell
kubectl apply -f "k8s-troubleshooting\manifests\unbound-pvc\experiment-a-unbound-pvc.yaml"
```

### First attempt

The Deployment was created, but PVC creation failed because of the invalid `1GB` quantity.

Observed output:

```text
deployment.apps/gamehub-storage-test created

Error from server (BadRequest):
PersistentVolumeClaim in version "v1" cannot be handled
as a PersistentVolumeClaim:
quantities must match the regular expression ...
```

**Important observation:**

The manifest contains two resources separated by `---`.

Kubernetes processes these resources independently. The failure to create the PVC did not automatically roll back the Deployment.

The Deployment was successfully created even though the PVC creation failed.

### Second attempt

After correcting `1GB` to `1G`, we applied the same manifest again.

Observed output:

```text
persistentvolumeclaim/gamehub-unbound-pvc created
deployment.apps/gamehub-storage-test unchanged
```

This confirms:

- The PVC was successfully created.
- The Deployment already existed, so Kubernetes reported it as unchanged.

---

## 7. Inspecting the PVC

Command:

```powershell
kubectl get pvc gamehub-unbound-pvc -n k8s-troubleshooting
```

Observed output:

```text
NAME                  STATUS    VOLUME   CAPACITY   ACCESS MODES   STORAGECLASS
gamehub-unbound-pvc   Pending
```

### 7.1 Understanding the output

| Field | Observed value | Explanation |
|---|---|---|
| NAME | `gamehub-unbound-pvc` | PVC was created successfully |
| STATUS | `Pending` | Storage has not been bound |
| VOLUME | Empty | No PV has been assigned |
| CAPACITY | Empty | No bound volume capacity is reported |
| ACCESS MODES | Empty | No PV has been bound |
| STORAGECLASS | Empty / `<unset>` | PVC explicitly requests no StorageClass |

**Conclusion:**

The PVC object exists, but Kubernetes has not found a suitable PV to satisfy its request.

### 7.2 Inspecting PVC Events

Command:

```powershell
kubectl describe pvc gamehub-unbound-pvc -n k8s-troubleshooting
```

Observed event:

```text
Type:    Warning
Reason:  FailedBinding

Message:
no persistent volumes available for this claim
and no storage class is set
```

### Understanding the event

| Event message | Explanation |
|---|---|
| No persistent volumes available for this claim | Kubernetes could not find a suitable PV for the PVC |
| No storage class is set | The PVC explicitly requests no StorageClass, so StorageClass-based dynamic provisioning cannot satisfy it |

**Important distinction:**

The PVC was not rejected during creation. It was created successfully but could not be bound.

---

## 8. Inspecting the Pod

Command:

```powershell
kubectl get pods -n k8s-troubleshooting
```

Observed output:

```text
NAME                                  READY   STATUS    RESTARTS
gamehub-storage-test-5f5d658d9d-lxsr2 0/1     Pending   0
```

### 8.1 Understanding the Pod status

| Field | Value | Explanation |
|---|---|---|
| READY | `0/1` | The one expected container is not ready |
| STATUS | `Pending` | Pod has not progressed to Running |
| RESTARTS | `0` | Container has not started and crashed |

The Pod references our PVC through its volume configuration:

```yaml
volumes:
  - name: application-storage
    persistentVolumeClaim:
      claimName: gamehub-unbound-pvc
```

The container also declares a volume mount:

```yaml
volumeMounts:
  - name: application-storage
    mountPath: /usr/share/nginx/html
```

The Pod depends on the PVC to provide the requested storage.

Since the PVC is still unbound, the Pod cannot proceed with volume setup and scheduling.

### 8.2 Inspecting Pod Events

Command:

```powershell
kubectl describe pod gamehub-storage-test-5f5d658d9d-lxsr2 -n k8s-troubleshooting
```

Important observations:

**Pod condition:**

```text
Conditions:
  Type           Status
  PodScheduled   False
```

This indicates that the Pod has not been scheduled to a node.

**Events:**

```text
Warning  FailedScheduling
0/1 nodes are available:
persistentvolumeclaim "gamehub-unbound-pvc" not found.
```

Later events:

```text
Warning  FailedScheduling
0/1 nodes are available:
pod has unbound immediate PersistentVolumeClaims.
```

### Why were there two different event messages?

This is important.

1. During the first manifest application, the Deployment was created but PVC creation failed.
2. The Deployment created its Pod.
3. Initially, the scheduler could not find the referenced PVC.
4. After correcting the storage quantity, the PVC was successfully created.
5. However, the PVC remained unbound because no suitable PV was available.
6. The scheduler then reported that the Pod had unbound immediate PersistentVolumeClaims.

The Events show how the failure evolved.

**Important:** This is not an nginx image-pull failure or a container crash. The Pod is blocked before it can start because its storage dependency has not been satisfied.

---

## 9. Final Resource Verification

Command:

```powershell
kubectl get pvc,pod,deploy -n k8s-troubleshooting
```

Observed output:

```text
NAME                                        STATUS    VOLUME   CAPACITY
persistentvolumeclaim/gamehub-unbound-pvc   Pending

NAME                                        READY   STATUS    RESTARTS
pod/gamehub-storage-test-5f5d658d9d-lxsr2   0/1     Pending   0

NAME                                         READY   UP-TO-DATE   AVAILABLE
deployment.apps/gamehub-storage-test         0/1     1            0
```

Other Deployments belonging to earlier troubleshooting experiments were also listed in the namespace. They had zero desired replicas and were not part of this experiment.

We did not modify or delete them.

### Final state

| Resource | State | Result |
|---|---|---|
| PVC | Pending | No PV bound |
| Pod | Pending | Not scheduled |
| Deployment | Created, 0/1 Available | Desired replica is not running |

---

## 10. Root Cause Analysis

The root cause of this experiment is:

**No suitable PersistentVolume is available to satisfy the PersistentVolumeClaim, and the PVC explicitly requests no StorageClass.**

The failure chain:

```text
PVC requests 1G storage
        |
        v
storageClassName: ""
        |
        v
No default StorageClass assignment
        |
        v
No suitable available PV
        |
        v
PVC remains Pending
        |
        v
Pod references the unbound PVC
        |
        v
Pod remains Pending
        |
        v
Deployment has 0 available replicas
```

---

## 11. Important Learnings

### Learning 1: Creating a PVC does not mean storage has been allocated

Kubernetes can successfully create a PVC object while leaving it in `Pending` state.

PVC creation and PVC binding are different operations.

### Learning 2: A PVC needs a suitable PV

A PVC and PV must satisfy the applicable matching requirements, including:

- Requested capacity.
- Access modes.
- StorageClass requirements.
- Other applicable volume constraints.

One PVC binds to one suitable PV. Kubernetes does not combine multiple smaller PVs to satisfy one larger PVC.

### Learning 3: Empty StorageClass and omitted StorageClass are different

```yaml
storageClassName: ""
```

Explicitly requests no StorageClass.

Omitting the field makes the PVC eligible for default StorageClass assignment.

### Learning 4: Dynamic provisioning depends on the StorageClass and provisioner

A StorageClass defines how storage should be provisioned.

The provisioner is responsible for creating the actual storage volume.

If a PVC explicitly requests no StorageClass, StorageClass-based dynamic provisioning cannot satisfy that claim.

### Learning 5: An unbound PVC can prevent Pod scheduling

The Pod references the PVC.

If the PVC cannot be bound, the scheduler reports:

```text
pod has unbound immediate PersistentVolumeClaims
```

The Pod can exist as an API object without being scheduled or running.

### Learning 6: Deployment creation does not guarantee application availability

Our Deployment was successfully created.

However:

```text
READY: 0/1
AVAILABLE: 0
```

This demonstrates that creating a Deployment is not the same as successfully running its application.

### Learning 7: Kubernetes Events help identify the failure

The PVC Events identified the binding problem.

The Pod Events identified the scheduling problem caused by the unbound claim.

Inspecting both resources gave us a clearer understanding of the failure chain.

---

## 12. Deployment Engineer's Perspective

When a Deployment is not becoming available and its Pod remains Pending, a deployment engineer should not immediately assume that the application image or container is the problem.

For applications that require persistent storage, the investigation should include:

1. Is the PVC successfully created?
2. Is the PVC Bound or Pending?
3. Does a suitable PV exist?
4. Is the PV already claimed by another PVC?
5. Does the PVC specify the intended StorageClass?
6. Does the StorageClass have a working provisioner?
7. What do the PVC Events report?
8. What do the Pod Events report?
9. Is the Pod waiting for storage before scheduling?

The objective is to identify the actual dependency preventing the application from becoming available.

---

## 13. Experiment A — Final Conclusion

**Experiment A successfully reproduced an Unbound PersistentVolumeClaim.**

We intentionally created a PVC that could not find a suitable PV and prevented it from using the default StorageClass.

As expected:

- PVC was created but remained `Pending`.
- No PV was assigned.
- The Pod referencing the PVC remained `Pending`.
- The scheduler reported unbound immediate PersistentVolumeClaims.
- The Deployment was created but had zero available replicas.

**The failure was caused by unavailable suitable storage, not by an nginx application failure.**

---

## 14. Next Experiment

### Experiment B — Resolve the Unbound PVC Using Static Provisioning

In Experiment B, we will resolve the same storage problem by manually creating a suitable PersistentVolume.

Planned approach:

1. Create a PV manually.
2. Configure it to have no StorageClass.
3. Ensure its capacity and access mode satisfy the existing PVC.
4. Observe how Kubernetes matches the PV with the Pending PVC.
5. Verify that the PVC becomes `Bound`.
6. Verify that the Pod can proceed with scheduling and startup.

**Important boundaries:**

- Continue using the isolated `k8s-troubleshooting` namespace.
- Do not modify the default `standard` StorageClass.
- Do not modify or delete the existing GameHub PostgreSQL PV or PVC.
- Preserve the existing Experiment A resources so we can observe how the same Pending PVC gets resolved.

The purpose of Experiment B is to understand how static provisioning resolves the failure reproduced in Experiment A.