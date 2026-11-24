# Docker vs Kubernetes Storage Integration — 3 Scenarios

## 1. Background: Why do both Docker and Kubernetes have volumes?

Containers are short-lived. If a container is deleted, its writable layer is lost.

To prevent data loss, we need storage that exists independently of the container lifecycle.

Docker provides Docker Volumes to achieve this.

Kubernetes also provides storage management through Volumes, PersistentVolumes (PV), PersistentVolumeClaims (PVC), StorageClasses and CSI drivers.

Both solve the persistent storage problem, but they manage storage differently.

**Important distinction:**
- Docker Volume provides storage to Docker-managed containers.
- Kubernetes provides storage management for Pods.
- Both can use the same underlying physical storage, but Kubernetes does not automatically discover or reuse Docker named volumes.

---

## Case 1: Kubernetes explicitly uses an existing Docker volume path

### What happens?

Suppose we already have a PostgreSQL database running in Docker.

1. Docker creates a named volume called `orders-data`.
2. PostgreSQL writes 100 customer records into that volume.
3. We move the application to Kubernetes.
4. We explicitly configure Kubernetes to mount the existing Docker volume's underlying host directory using `hostPath`.
5. PostgreSQL in the Kubernetes Pod accesses the existing database files.

Example Docker volume:

```bash
docker volume create orders-data
```

Example Kubernetes configuration:

```yaml
volumes:
  - name: database-storage
    hostPath:
      path: /var/lib/docker/volumes/orders-data/_data
      type: Directory
```

The actual directory must exist and be accessible on the node.

### What happens to the data?

Kubernetes accesses the existing storage instead of creating an independent empty storage location.

The existing 100 customer records can be accessed by PostgreSQL in Kubernetes.

The same Docker image can be used. Only the storage mounting configuration changes.

### Limitations

1. **Node dependency:** The Docker volume's underlying path is specific to the node where Docker created it.
2. **Node failure:** If the node becomes unavailable, another node cannot automatically access its local Docker volume.
3. **Data availability:** If the underlying disk fails, the data may be lost.
4. **Portability:** Moving the Pod to another node does not automatically move the Docker volume.
5. **Management:** Kubernetes is mounting a host directory; it is not automatically managing the Docker named volume through Docker Engine.

### Real-world business use case

Useful for local development, testing, or a single-node environment where existing local data needs to be reused.

It is generally not the preferred solution for highly available production databases.

---

## Case 2: Docker and Kubernetes use separate storage

### What happens?

Suppose PostgreSQL initially runs in Docker.

1. Docker creates a volume called `orders-data`.
2. The volume contains 100 customer records.
3. We migrate the application to Kubernetes.
4. We create a PVC for PostgreSQL.
5. We do not configure Kubernetes to use the existing Docker volume.
6. Kubernetes provisions or allocates separate storage.
7. PostgreSQL starts using the new Kubernetes storage.

Now there are two independent storage locations.

### Example

| Storage | Customer records |
|---|---:|
| Existing Docker volume | 100 |
| New Kubernetes storage | 0 initially |

Suppose Kubernetes receives 100 new customer records after deployment.

| Storage | Customer records |
|---|---:|
| Docker volume | 100 |
| Kubernetes storage | 100 |

If the old Docker application also continues receiving another 100 records, Docker will have 200 records while Kubernetes has 100.

These are independent datasets, not automatically synchronized copies.

### Limitations

1. **Existing data is not automatically migrated:** Kubernetes starts with its own storage.
2. **Data divergence:** If both environments continue accepting customer orders, their databases can become inconsistent.
3. **Migration required:** Existing database records must be transferred using backup and restore, replication, or another appropriate database migration method.
4. **Duplicate data:** If both environments remain active, maintaining consistency requires a deliberate synchronization strategy.
5. **Storage cost:** Both storage locations may continue consuming resources.

### Real-world business use case

This can be used during a migration from a Docker-based application to Kubernetes.

For example, a company creates new Kubernetes storage, restores the existing database backup into it, validates the data and then switches application traffic to Kubernetes.

The old Docker volume can be retained temporarily as a rollback or recovery option.

---

## Case 3: Docker volume is not defined; Kubernetes manages storage independently

### What happens?

Suppose we are deploying a completely new application directly into Kubernetes.

There is no existing Docker named volume.

1. We build or obtain the Docker image.
2. We create a Kubernetes PVC.
3. Kubernetes provisions storage dynamically through a StorageClass, or binds the PVC to an existing statically created PV.
4. The Pod mounts that storage.
5. The application writes data to the mounted directory.

Example PVC:

```yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: orders-pvc
spec:
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: 5Gi
```

Example Pod volume configuration:

```yaml
volumes:
  - name: database-storage
    persistentVolumeClaim:
      claimName: orders-pvc
```

The application writes to its mounted directory.

It does not need a Docker named volume.

### Static vs Dynamic Provisioning

| Static provisioning | Dynamic provisioning |
|---|---|
| Administrator creates a PV beforehand. | Storage is provisioned automatically through a StorageClass and provisioner. |
| PVC binds to an appropriate existing PV. | PVC triggers storage provisioning when required. |
| Storage is prepared in advance. | Storage is created on demand. |

### Limitations

1. **Storage configuration is required:** The PVC must request suitable storage.
2. **Storage provider dependency:** Dynamic provisioning requires a functioning StorageClass and provisioner.
3. **Capacity limitations:** The requested storage must be available.
4. **Access limitations:** The storage's access mode and topology must support the workload.
5. **Data lifecycle:** Storage retention and deletion behaviour depend on the PV reclaim policy and underlying storage provider.

### Real-world business use case

This is a common approach when deploying new applications directly into Kubernetes.

For example, a company deploys a new e-commerce application. PostgreSQL runs using a Docker image, while Kubernetes manages its persistent storage through PVC, PV and StorageClass.

---

## 4. Comparison of all three scenarios

| Factor | Case 1: Reuse Docker path | Case 2: Separate storage | Case 3: Kubernetes-only storage |
|---|---|---|---|
| Existing Docker volume | Yes | Yes | No |
| Kubernetes uses existing Docker data | Yes, if explicitly configured | No | Not applicable |
| New Kubernetes storage | Not necessarily | Yes | Yes |
| Data migration | Not necessarily | Required if old data is needed | Not applicable for a new application |
| Node dependency | High with local hostPath | Depends on Kubernetes storage provider | Depends on Kubernetes storage provider |
| Production suitability | Limited | Suitable with a proper migration plan | Common production approach |

---

## 5. Important concept: The Docker image and the storage are independent

We can use the same PostgreSQL Docker image in both Docker and Kubernetes.

The application writes database files to a configured directory:

```text
/var/lib/postgresql/data
```

In Docker:

```bash
-v orders-data:/var/lib/postgresql/data
```

In Kubernetes:

```yaml
volumeMounts:
  - name: database-storage
    mountPath: /var/lib/postgresql/data
```

The application does not need to know whether Docker or Kubernetes manages the storage.

The storage mounted at that path determines where the database files are written.

**Therefore, Docker images can run in Kubernetes without using Docker named volumes.**

---

## 6. Final conclusions

1. Kubernetes does not automatically override, extend or reuse Docker named volumes.
2. Kubernetes can access an existing Docker volume's underlying directory through explicit configuration, but this has node-specific limitations.
3. Docker and Kubernetes can maintain separate storage locations, but their data is not automatically synchronized.
4. Existing database data must be migrated when moving to separate Kubernetes storage.
5. Kubernetes can independently manage persistent storage without any Docker named volume.
6. The same Docker image can write to either Docker-managed or Kubernetes-managed storage, depending on the mount configuration.

**Key takeaway:**

Docker and Kubernetes have different storage management mechanisms, but they can use the same underlying storage infrastructure when correctly integrated. Docker images do not require Docker named volumes to run in Kubernetes.