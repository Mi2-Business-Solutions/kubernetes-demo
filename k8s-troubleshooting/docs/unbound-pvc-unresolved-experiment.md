### Unresolved Reference Scenario: YouTube – PVC Pending Despite a StorageClass

**Status:** Unclear – kept for further investigation.

#### What was demonstrated?

The instructor created a YAML file containing:

1. A PersistentVolumeClaim named `myebsvolclaim`, requesting `1Gi` storage with `ReadWriteOnce` access mode.
2. A Deployment named `pvdeploy`, whose Pod references the PVC `myebsvolclaim`.

**Important:** The YAML contains a `PersistentVolumeClaim` and a `Deployment`. It does not contain a `PersistentVolume` resource.

The instructor demonstrated the following output:

```text
kubectl get pvc

NAME           STATUS    VOLUME
myebsvolclaim  Pending
```

```text
kubectl get pv

No resources found
```

The instructor also explained that the PVC was using the default StorageClass, but that the StorageClass was unable to create a PersistentVolume.

#### What did we observe?

The additional screenshot showed:

```text
kubectl get sc

NAME      PROVISIONER
standard  k8s.io/minikube-hostpath
```

The PVC output showed an empty `STORAGECLASS` column.

#### Why is this scenario unclear?

| Observation | Status |
|---|---|
| StorageClass exists | Confirmed |
| Default StorageClass assigned | Unknown |
| PV exists | No |
| PVC is Pending | Yes |
| Exact provisioning failure | Unknown |

There are some details that we cannot confirm from the available video transcript and screenshots:

1. **Default StorageClass assignment is unclear.**

   The instructor says that the PVC is using the default StorageClass. However, the screenshot does not show `standard` marked as `(default)`, and the PVC's `STORAGECLASS` column is blank.

   Therefore, we cannot confirm that the PVC was actually assigned the `standard` StorageClass.

2. **Dynamic provisioning failure is not established.**

   The `standard` StorageClass exists and specifies `k8s.io/minikube-hostpath` as its provisioner.

   However, the existence of a StorageClass does not prove that its provisioner is operational or that it attempted and failed to create storage.

   We do not have the PVC Events or provisioner logs to establish what happened.

3. **The exact reason for the PVC remaining Pending is unknown.**

   We know that no PV existed at the time of the screenshot, but we cannot establish whether:
   - No default StorageClass was assigned.
   - Dynamic provisioning was attempted but failed.
   - The provisioner was unavailable or unable to create storage.

4. **The instructor's explanation about the Pod is imprecise.**

   The Deployment references an existing PVC by its correct name. The problem shown is not that the PVC object is missing; it is that the existing PVC is not bound to a PV.

#### What information would help us investigate further?

If we reproduce this scenario or obtain more details, we should inspect:

```bash
kubectl describe pvc myebsvolclaim
kubectl describe pod <pod-name>
kubectl get storageclass standard -o yaml
```

The PVC Events and StorageClass configuration would help us identify whether the claim received a default StorageClass and whether provisioning was attempted.

#### Why are we leaving this scenario unresolved?

We do not want to assume a cause without sufficient evidence.

The scenario is useful because it raises an important troubleshooting question:

**Can a PVC remain Pending even when a StorageClass exists, and what happens when its configured dynamic provisioner cannot create storage?**

We will keep this scenario for tracking and return to it when we have enough evidence to reproduce and explain it accurately.

**For now, we will not include it as one of our four planned hands-on experiments. We will proceed with Experiment A separately.**