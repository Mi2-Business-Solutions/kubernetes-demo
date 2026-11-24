# Experiment C – Dynamic PersistentVolume Provisioning

## 1. Objective

The objective of this experiment is to understand how Kubernetes dynamically provisions storage when a PersistentVolumeClaim (PVC) requests a StorageClass that has a working dynamic provisioner.

In this experiment, we will:

1. Create a PVC requesting storage from the existing `standard` StorageClass.
2. Observe how the dynamic provisioner automatically creates a PersistentVolume (PV).
3. Verify that the PVC becomes `Bound`.
4. Inspect the automatically generated PV.
5. Create a Deployment that references the PVC.
6. Verify that the Deployment and its Pod reach the expected state.

**Scope decision:** We will stop after verifying that the Pod is running with the PVC referenced in its specification. We will not perform an additional file-write/read test inside the container because that is outside this experiment's learning objective.

---

## 2. Existing Environment

| Component | Value |
|---|---|
| Minikube profile | `gamehub-cluster` |
| Kubernetes context | `gamehub-cluster` |
| Namespace | `k8s-troubleshooting` |
| StorageClass | `standard` |
| Provisioner | `k8s.io/minikube-hostpath` |
| Volume binding mode | `Immediate` |
| Requested storage | `1G` |
| Access mode | `ReadWriteOnce` |
| Container image | `nginx` |

### Important existing StorageClass details

The cluster already has a `standard` StorageClass configured.

- Provisioner: `k8s.io/minikube-hostpath`
- Reclaim policy: `Delete`
- Volume binding mode: `Immediate`
- Volume expansion: `false`

**Why does Immediate binding matter?**

With `Immediate` volume binding, Kubernetes can initiate dynamic provisioning as soon as the PVC is created. It does not need to wait for a Pod to consume the PVC.

### Safety boundaries

During this experiment:

- Existing Experiment A and Experiment B resources must remain untouched.
- The GameHub application in the `gamehub` namespace must not be modified.
- PostgreSQL storage must remain untouched.
- The existing `standard` StorageClass must not be modified.

---

## 3. Resource Naming

We use separate resource names to keep Experiment C independent of Experiments A and B.

| Resource | Name |
|---|---|
| PVC | `gamehub-dynamic-pvc` |
| Automatically generated PV | `pvc-ef6b5b87-8d72-4690-82cc-d16e06a1d9f5` |
| Deployment | `gamehub-dynamic-storage-test` |
| Pod | `gamehub-dynamic-storage-test-686bc4c6b-m4n9n` |

The PV name was generated automatically by the provisioner. We did not specify a PV name in our YAML.

---

## 4. Step 1 – Capture the Baseline Before Experiment C

Before creating new resources, we inspected the existing resources in the troubleshooting namespace.

### Command

```powershell
kubectl get pvc,pv,pod,deploy -n k8s-troubleshooting
```

### Actual Output

```text
NAME                                        STATUS   VOLUME              CAPACITY   ACCESS MODES   STORAGECLASS   VOLUMEATTRIBUTESCLASS   AGE
persistentvolumeclaim/gamehub-unbound-pvc   Bound    gamehub-static-pv   1G         RWO                           <unset>                 3h46m

NAME                                                        CAPACITY   ACCESS MODES   RECLAIM POLICY   STATUS   CLAIM                                     STORAGECLASS   VOLUMEATTRIBUTESCLASS   REASON   AGE
persistentvolume/gamehub-static-pv                          1G         RWO            Retain           Bound    k8s-troubleshooting/gamehub-unbound-pvc                  <unset>                          36m
persistentvolume/pvc-2dec9c98-4b22-4dba-8ae5-32f75f87bd60   1Gi        RWO            Delete           Bound    gamehub/postgres-pvc                      standard       <unset>                          15d

NAME                                        READY   STATUS    RESTARTS   AGE
pod/gamehub-storage-test-5f5d658d9d-lxsr2   1/1     Running   0          3h47m

NAME                                         READY   UP-TO-DATE   AVAILABLE   AGE
deployment.apps/gamehub-node-affinity-hard   0/0     0            0           2d
deployment.apps/gamehub-node-affinity-soft   0/0     0            0           2d
deployment.apps/gamehub-node-selector        0/0     0            0           3d6h
deployment.apps/gamehub-storage-test         1/1     1            1           3h47m
deployment.apps/insufficient-cpu             0/0     0            0           9d
deployment.apps/insufficient-memory          0/0     0            0           10d
```

### Observations

1. The Experiment B PVC `gamehub-unbound-pvc` was already `Bound`.
2. It was bound to the manually created PV `gamehub-static-pv`.
3. The Experiment B test Pod was `Running`.
4. The existing PostgreSQL PV was already bound to `gamehub/postgres-pvc`.
5. No Experiment C PVC or Deployment existed yet.

**Important:** The PostgreSQL PV belongs to the separate `gamehub` namespace. We left it untouched.

This baseline helps us distinguish resources created by Experiment C from resources that already existed.

---

## 5. Step 2 – Create the Dynamic PVC

We created a new PVC that explicitly requests storage from the existing `standard` StorageClass.

### File: `experiment-c-dynamic-pvc.yaml`

Location:

`k8s-troubleshooting\manifests\unbound-pvc\experiment-c-dynamic-pvc.yaml`

### YAML with Detailed Comments

```yaml
# API version for PersistentVolumeClaim resources.
# PVC is a core Kubernetes resource, so it uses v1.
apiVersion: v1

# We are creating a PersistentVolumeClaim (PVC).
kind: PersistentVolumeClaim

metadata:
  # A separate name keeps Experiment C independent
  # of the PVC used in Experiments A and B.
  name: gamehub-dynamic-pvc

  # Create this PVC inside our troubleshooting namespace.
  namespace: k8s-troubleshooting

spec:
  # Request ReadWriteOnce access.
  # This means the volume can be mounted read-write
  # by workloads on one node at a time.
  accessModes:
    - ReadWriteOnce

  # Explicitly select the existing "standard" StorageClass.
  # Its provisioner is k8s.io/minikube-hostpath.
  #
  # This tells Kubernetes which StorageClass to use
  # for dynamic storage provisioning.
  storageClassName: standard

  resources:
    requests:
      # Request 1G of storage.
      # Kubernetes will look for or dynamically provision
      # a volume that can satisfy this request.
      storage: 1G
```

### Understanding the Important Fields

| Field | Purpose |
|---|---|
| `apiVersion: v1` | PVC belongs to the Kubernetes core API group. |
| `kind: PersistentVolumeClaim` | Specifies the resource type. |
| `metadata.name` | Identifies our PVC. |
| `metadata.namespace` | Places the PVC in `k8s-troubleshooting`. |
| `accessModes` | Requests ReadWriteOnce access. |
| `storageClassName` | Selects the `standard` StorageClass. |
| `resources.requests.storage` | Requests 1G of storage. |

### Important Difference from Experiment B

In Experiment B, we manually created the PV.

In Experiment C, we only create the PVC and let the configured provisioner create the PV automatically.

### Apply Command

```powershell
kubectl apply -f k8s-troubleshooting\manifests\unbound-pvc\experiment-c-dynamic-pvc.yaml
```

### Actual Output

```text
persistentvolumeclaim/gamehub-dynamic-pvc created
```

The Kubernetes API server successfully accepted the PVC.

However, creating the PVC alone does not prove that storage has been provisioned. We need to inspect the resulting PVC and PV states.

---

## 6. Step 3 – Observe Dynamic Provisioning

After applying the PVC YAML, Kubernetes dynamically provisioned a PV.

### PVC Evidence

The resulting PVC was observed as:

```text
gamehub-dynamic-pvc   Bound   pvc-ef6b5b87-8d72-4690-82cc-d16e06a1d9f5   1G   RWO   standard
```

### PV Evidence

The corresponding PV was observed as:

```text
pvc-ef6b5b87-8d72-4690-82cc-d16e06a1d9f5   1G   RWO   Delete   Bound   k8s-troubleshooting/gamehub-dynamic-pvc   standard
```

### What Does This Prove?

- We created only a PVC.
- We did not manually create a PV.
- Kubernetes automatically generated a PV.
- The generated PV was bound to our PVC.
- Both resources reached the `Bound` state.
- The generated PV uses the `standard` StorageClass.

**This is the key evidence of dynamic provisioning.**

---

## 7. Step 4 – Inspect the Automatically Generated PV

We inspected the generated PV to understand who created it and how its storage is backed.

### Command

```powershell
kubectl describe pv pvc-ef6b5b87-8d72-4690-82cc-d16e06a1d9f5
```

### Actual Output

```text
Name:            pvc-ef6b5b87-8d72-4690-82cc-d16e06a1d9f5
Labels:          <none>
Annotations:     hostPathProvisionerIdentity: ea3866cc-3839-41d2-b6b8-41830774d024
                 pv.kubernetes.io/provisioned-by: k8s.io/minikube-hostpath
Finalizers:      [kubernetes.io/pv-protection]
StorageClass:    standard
Status:          Bound
Claim:           k8s-troubleshooting/gamehub-dynamic-pvc
Reclaim Policy:  Delete
Access Modes:    RWO
VolumeMode:      Filesystem
Capacity:        1G
Node Affinity:   <none>
Message:
Source:
    Type:          HostPath (bare host directory volume)
    Path:          /tmp/hostpath-provisioner/k8s-troubleshooting/gamehub-dynamic-pvc
    HostPathType:
Events:            <none>
```

### 7.1 Provisioner Identity

```text
pv.kubernetes.io/provisioned-by: k8s.io/minikube-hostpath
```

This annotation identifies the provisioner responsible for creating the PV.

It confirms that the Minikube hostPath provisioner handled our storage request.

### 7.2 PVC-to-PV Relationship

```text
StorageClass:    standard
Status:          Bound
Claim:           k8s-troubleshooting/gamehub-dynamic-pvc
Capacity:        1G
Access Modes:    RWO
```

This confirms:

- The PV uses the `standard` StorageClass.
- Its status is `Bound`.
- Its claim is our Experiment C PVC.
- Its capacity is 1G.
- Its access mode is RWO.

### 7.3 Underlying Storage Location

```text
Source:
    Type: HostPath
    Path: /tmp/hostpath-provisioner/k8s-troubleshooting/gamehub-dynamic-pvc
```

The Minikube hostPath provisioner uses a directory inside the Minikube node environment as the backing storage for this PV.

**Important distinction:** This path is inside the Minikube node environment. It is not directly a Windows directory.

HostPath provisioning is convenient for local development and learning. It is not equivalent to production-grade shared or distributed storage.

### 7.4 Reclaim Policy

```text
Reclaim Policy: Delete
```

The dynamically provisioned PV has a `Delete` reclaim policy.

This means that when the PVC is deleted, Kubernetes and the provisioner can delete the PV and its underlying provisioned storage.

**Safety note:** We should not delete this PVC during routine experiment cleanup. Deleting it can result in loss of the associated provisioned storage.

---

## 8. Step 5 – Create a Deployment That Uses the PVC

Now that we have confirmed dynamic provisioning, we create a Deployment that references the new PVC.

The objective is to verify that a workload can be scheduled with the dynamically provisioned volume configured in its Pod specification.

### File: `experiment-c-dynamic-deployment.yaml`

Location:

`k8s-troubleshooting\manifests\unbound-pvc\experiment-c-dynamic-deployment.yaml`

### YAML with Detailed Comments

```yaml
# Use the apps API group for Deployment resources.
apiVersion: apps/v1

# We are creating a Deployment to manage our test Pod.
kind: Deployment

metadata:
  # A separate Deployment for Experiment C.
  name: gamehub-dynamic-storage-test

  # Keep this experiment inside our troubleshooting namespace.
  namespace: k8s-troubleshooting

spec:
  # Run one replica of our test application.
  replicas: 1

  # The Deployment uses this selector to identify its Pods.
  selector:
    matchLabels:
      app: gamehub-dynamic-storage-test

  # This template defines how the Pod should be created.
  template:
    metadata:
      labels:
        # This label must match the selector above.
        app: gamehub-dynamic-storage-test

    spec:
      containers:
        - name: nginx

          # Nginx is our lightweight test container.
          image: nginx

          # Mount the requested storage inside the container.
          volumeMounts:
            - name: dynamic-storage

              # Directory where the volume is mounted
              # inside the Nginx container.
              mountPath: /usr/share/nginx/html/data

      # Define the volumes available to this Pod.
      volumes:
        - name: dynamic-storage

          # Reference the PVC created in Experiment C.
          persistentVolumeClaim:
            claimName: gamehub-dynamic-pvc
```

### Understanding the Important Relationship

The Deployment references the PVC:

```yaml
persistentVolumeClaim:
  claimName: gamehub-dynamic-pvc
```

Notice that the Deployment does not reference the generated PV name.

This is intentional.

Applications request storage through PVCs. They do not need to know which PV Kubernetes has bound to the claim.

### Apply Command

```powershell
kubectl apply -f k8s-troubleshooting\manifests\unbound-pvc\experiment-c-dynamic-deployment.yaml
```

### Actual Output

```text
deployment.apps/gamehub-dynamic-storage-test created
```

The Deployment was successfully created.

---

## 9. Step 6 – Verify Deployment and Pod Status

After creating the Deployment, we checked whether the Pod was successfully created and started.

### Command

```powershell
kubectl get deployment,pod -n k8s-troubleshooting
```

### Actual Output

```text
NAME                                           READY   UP-TO-DATE   AVAILABLE   AGE
deployment.apps/gamehub-dynamic-storage-test   1/1     1            1           23s
deployment.apps/gamehub-node-affinity-hard     0/0     0            0           2d1h
deployment.apps/gamehub-node-affinity-soft     0/0     0            0           2d1h
deployment.apps/gamehub-node-selector          0/0     0            0           3d7h
deployment.apps/gamehub-storage-test           1/1     1            1           4h32m
deployment.apps/insufficient-cpu               0/0     0            0           9d
deployment.apps/insufficient-memory            0/0     0            0           10d

NAME                                               READY   STATUS    RESTARTS   AGE
pod/gamehub-dynamic-storage-test-686bc4c6b-m4n9n   1/1     Running   0          23s
pod/gamehub-storage-test-5f5d658d9d-lxsr2          1/1     Running   0          4h32m
```

### Observations

Our Experiment C Deployment:

```text
deployment.apps/gamehub-dynamic-storage-test   1/1   1   1
```

Our Experiment C Pod:

```text
pod/gamehub-dynamic-storage-test-686bc4c6b-m4n9n   1/1   Running   0
```

This confirms:

- The Deployment has one desired replica.
- One replica is ready.
- The Deployment is available.
- The Pod is running.
- The Pod has no restarts.

The existing Experiment B Deployment and Pod also remained healthy.

### What Does This Prove?

The Deployment references the dynamically provisioned PVC, and its Pod successfully reached `Running`.

Together with the PVC/PV binding evidence, this demonstrates that the workload was able to start with the PVC configured as its volume.

### Scope Boundary

We deliberately did not perform a file-write/read test inside the container.

Therefore, we have not independently verified:

- Application-level file write permissions.
- Actual file persistence across Pod replacement.
- Application-level data durability.

Those are separate validation activities and are outside the scope of this experiment.

---

## 10. Before-and-After Comparison

### Before Experiment C

| Resource | Before Experiment C |
|---|---|
| `gamehub-unbound-pvc` | Bound |
| `gamehub-static-pv` | Bound |
| Experiment B Pod | Running |
| PostgreSQL PV | Bound to `gamehub/postgres-pvc` |
| `gamehub-dynamic-pvc` | Did not exist |
| Experiment C PV | Did not exist |
| `gamehub-dynamic-storage-test` Deployment | Did not exist |

### After Experiment C

| Resource | After Experiment C |
|---|---|
| `gamehub-unbound-pvc` | Remained Bound |
| `gamehub-static-pv` | Remained Bound |
| Experiment B Pod | Remained Running |
| PostgreSQL PV | Left untouched |
| `gamehub-dynamic-pvc` | Bound |
| Automatically generated PV | Bound |
| `gamehub-dynamic-storage-test` Deployment | 1/1 available |
| Experiment C Pod | 1/1 Running |

### Evidence Chain

```text
BEFORE EXPERIMENT C
        |
        v
Experiment B PVC/PV already Bound
        |
        v
No Experiment C resources exist
        |
        |
        v
CREATE gamehub-dynamic-pvc
        |
        v
PVC explicitly requests StorageClass: standard
        |
        v
Minikube dynamic provisioner handles the request
        |
        v
PV is automatically created
        |
        v
PVC and PV become Bound
        |
        v
CREATE gamehub-dynamic-storage-test Deployment
        |
        v
Deployment references gamehub-dynamic-pvc
        |
        v
Deployment becomes 1/1 available
        |
        v
Pod reaches 1/1 Running
        |
        v
EXPERIMENT C SUCCESSFULLY DEMONSTRATED
```

---

## 11. Engineering Analysis

There was no storage failure to troubleshoot in Experiment C. The objective was to understand the successful dynamic provisioning path.

The sequence was:

1. The PVC explicitly requested `storageClassName: standard`.
2. The StorageClass identified `k8s.io/minikube-hostpath` as its provisioner.
3. The provisioner created a backing HostPath directory and a PV.
4. Kubernetes bound the generated PV to our PVC.
5. The Deployment referenced the PVC.
6. The Pod successfully reached `Running`.

### Who Creates the PV?

This is the most important distinction between static and dynamic provisioning.

**Static provisioning:**

The administrator or engineer manually creates a PV. A PVC then claims a suitable available PV.

**Dynamic provisioning:**

The engineer creates a PVC that requests a StorageClass. The configured provisioner automatically creates a suitable PV.

### Why Do Applications Reference PVCs Instead of PVs?

The PVC provides an abstraction between the application and the underlying storage.

The application workload only needs to reference the PVC. Kubernetes handles the binding between that claim and the PV.

This reduces the application's dependency on the identity and implementation details of the underlying storage volume.

---

## 12. Deployment Engineer's Perspective

When deploying an application that requires persistent storage, an engineer should evaluate:

1. What storage capacity does the application require?
2. Which access mode is appropriate?
3. Which StorageClass should be used?
4. Does the StorageClass have a working provisioner?
5. Is the provisioner available and healthy?
6. What is the volume binding mode?
7. What reclaim policy applies to the provisioned PV?
8. Does the PVC reach `Bound`?
9. Does the workload reference the correct PVC?
10. Does the Pod reach the expected state?

A `Bound` PVC confirms successful claim-to-volume binding.

However, it does not independently prove application-level write access, correct file permissions, or data durability. Those require additional checks based on the application's requirements.

For this experiment, we intentionally verified provisioning, binding, and Pod startup without going into container-level file operations.

---

## 13. Experiments A, B and C – Comparison

| Aspect | Experiment A | Experiment B | Experiment C |
|---|---|---|---|
| Scenario | No matching PV and no dynamic provisioning path for the claim | Static provisioning | Dynamic provisioning |
| Who creates the PV? | No PV created for the claim | Engineer manually creates PV | Provisioner automatically creates PV |
| StorageClass | Explicitly empty | Explicitly empty | `standard` |
| PVC status | Pending | Bound | Bound |
| PV | No matching PV | `gamehub-static-pv` | Automatically generated PV |
| Workload result | Pod Pending | Pod Running | Pod Running |

### What Each Experiment Taught Us

**Experiment A – Understanding an Unbound PVC**

We learned how a Pod can remain Pending when its PVC cannot find a suitable PV and dynamic provisioning is not requested.

**Experiment B – Static Provisioning**

We learned how an administrator can manually create a suitable PV and allow Kubernetes to bind an existing PVC to it.

**Experiment C – Dynamic Provisioning**

We learned how a PVC can request storage through a StorageClass and how a configured provisioner automatically creates the PV.

### Overall Learning

The three experiments demonstrate three different storage scenarios:

- Experiment A: Storage cannot be allocated.
- Experiment B: Storage is allocated through a manually created PV.
- Experiment C: Storage is allocated automatically through a dynamic provisioner.

---

## 14. Final Conclusion

Experiment C successfully demonstrated dynamic PersistentVolume provisioning in our `gamehub-cluster` Minikube environment.

The strongest evidence is the generated PV annotation:

```text
pv.kubernetes.io/provisioned-by: k8s.io/minikube-hostpath
```

Additional evidence:

- The PVC requested the `standard` StorageClass.
- A PV was automatically generated.
- The PV was bound to `k8s-troubleshooting/gamehub-dynamic-pvc`.
- The generated PV had a capacity of `1G`.
- The Deployment referenced the new PVC.
- The Deployment became `1/1` available.
- The Pod reached `1/1 Running`.

We did not delete or modify any resources from Experiments A or B. The PostgreSQL storage and running GameHub application were also left untouched.

**Final Result: Experiment C – Dynamic Provisioning Successfully Demonstrated.**