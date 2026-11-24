# Real-World Business Use Cases – Experiments A, B, C and D

Understanding Kubernetes storage is not just about creating PVs, PVCs and StorageClasses. As a deployment engineer, we need to understand why an organization would choose one storage approach over another.

Different applications have different storage requirements. The right approach depends on factors such as infrastructure ownership, cost, scalability, performance, availability and operational control.

---

## Experiment A – PVC Without a Matching PV or StorageClass

### What we did

We created a PVC without:
- A matching pre-created PersistentVolume.
- A usable StorageClass for dynamic provisioning.

The PVC remained in Pending status because Kubernetes could not find storage to satisfy the request.

### Real-world business use case

**Scenario: An organization uses manually managed storage and has not provisioned storage for a new application.**

Imagine a company running applications in its own data centre.

The infrastructure team manages physical storage and creates PersistentVolumes manually. Application teams submit PVC requests when they deploy their applications.

A developer deploys an application that requests 10Gi of storage, but the infrastructure team has not yet created a matching PV.

The PVC remains Pending.

This is useful because Kubernetes does not silently provide storage that does not exist or cannot be provisioned.

The application team can identify the issue and coordinate with the infrastructure team.

### Business perspective

- Storage is centrally controlled by the infrastructure team.
- Storage allocation may require approval.
- Applications cannot automatically obtain storage until an appropriate PV is available.
- The Pending PVC exposes a missing infrastructure dependency.

### When might this happen?

- An organization uses static storage provisioning.
- Dynamic provisioning is intentionally disabled.
- Storage capacity has not yet been allocated.
- A PVC requests a StorageClass or capacity that is unavailable.

**Business takeaway:** This scenario helps identify infrastructure readiness problems before an application can use its required storage.

---

## Experiment B – Static Provisioning

### What we did

We manually created a PersistentVolume and then created a PVC that matched it.

Kubernetes successfully bound the PVC to the available PV.

### Real-world business use case

**Scenario: A company wants complete control over which physical or pre-allocated storage is assigned to an application.**

Imagine a financial organization hosting an application that stores important business records.

The infrastructure team has already allocated a specific storage volume for this application.

The team wants to control:
- Which storage resource is assigned.
- How much capacity is allocated.
- Which access modes are supported.
- What happens to the volume when the PVC is deleted.

The infrastructure team creates a PV manually, and the application team creates a PVC that matches it.

Kubernetes binds the claim to the available volume.

### Business perspective

- Infrastructure teams have explicit control over storage allocation.
- Specific pre-existing storage resources can be assigned to workloads.
- Storage lifecycle and reclaim policies can be managed deliberately.
- This approach is useful when storage must be allocated or configured outside Kubernetes.

### When might this happen?

- On-premises data centres.
- Legacy storage systems.
- Environments with manually managed SAN or NAS storage.
- Applications requiring specific pre-allocated storage.
- Organizations with strict infrastructure allocation procedures.

**Business takeaway:** Static provisioning is useful when an organization prioritizes explicit storage control over automatic allocation.

---

## Experiment C – Dynamic Provisioning with Immediate

### What we did

We used the existing `standard` StorageClass, which had:

```yaml
volumeBindingMode: Immediate
```

When we created the PVC, Kubernetes dynamically provisioned storage.

The PVC became Bound, and our application workload was able to use it.

### Real-world business use case

**Scenario: A company wants application teams to request storage without waiting for infrastructure teams to create volumes manually.**

Imagine an organization running several applications on Kubernetes.

Different application teams deploy services that require persistent storage:

- A PostgreSQL database.
- A reporting application.
- An internal application that stores uploaded documents.

The infrastructure team configures a StorageClass connected to an appropriate storage provider.

When an application team creates a PVC, Kubernetes automatically requests storage from the configured provisioner.

The volume is created and bound without requiring an administrator to manually create a PV for every claim.

### Business perspective

- Reduces manual infrastructure work.
- Enables application teams to provision storage through Kubernetes.
- Supports repeatable and automated deployments.
- Makes it easier to scale application environments.
- Improves developer self-service.

### When might this happen?

- Development and testing environments.
- General-purpose application storage.
- Applications where storage can be provisioned independently of Pod scheduling.
- Organizations using cloud storage providers with dynamic provisioning.

**Business takeaway:** Dynamic provisioning with Immediate is useful when the organization wants simple, automated storage allocation without requiring a Pod scheduling decision first.

---

## Experiment D – Dynamic Provisioning with WaitForFirstConsumer

### What we did

We created a dedicated StorageClass using:

```yaml
volumeBindingMode: WaitForFirstConsumer
```

The PVC initially remained Pending.

After creating a Pod that referenced the PVC, Kubernetes started the scheduling and provisioning workflow.

However, in our Minikube experiment, provisioning failed because the provisioner's ServiceAccount did not have permission to get Nodes.

We diagnosed the RBAC issue but deliberately did not modify cluster-level permissions.

### Real-world business use case

**Scenario: A company runs applications across multiple availability zones or nodes, and storage must be compatible with the location where the application runs.**

Imagine an organization running a database application in a multi-zone Kubernetes cluster.

The cluster has three nodes:

- Node A in Availability Zone 1.
- Node B in Availability Zone 2.
- Node C in Availability Zone 3.

The storage provider has topology constraints. A volume created in one availability zone might not be attachable to a Pod running in another zone.

If storage is provisioned before Kubernetes knows where the Pod should run, the volume might be created in an unsuitable location.

This can cause scheduling or volume attachment problems.

With `WaitForFirstConsumer`, Kubernetes can coordinate Pod scheduling with storage provisioning.

The scheduler considers the Pod's scheduling requirements and identifies a suitable node. The storage provisioner can then use the selected-node information and applicable topology constraints to provision compatible storage.

### Business perspective

- Helps avoid provisioning storage in an unsuitable topology.
- Supports workloads that use zone-aware or node-constrained storage.
- Coordinates workload placement with storage allocation.
- Is useful for applications that depend on storage locality or attachment constraints.

### When might this happen?

- Multi-availability-zone Kubernetes clusters.
- Cloud environments with zone-specific block storage.
- Local PersistentVolumes tied to particular nodes.
- Storage systems with topology constraints.
- Stateful workloads where storage location affects scheduling.

**Business takeaway:** WFFC is useful when the location of the workload matters to the storage provisioning decision.

### Important note about our experiment

Our Minikube experiment demonstrated the WFFC scheduling and provisioning workflow up to the point where the provisioner attempted to retrieve the selected node.

The actual volume provisioning did not complete because of an RBAC permission failure.

The real-world business scenario above describes why an organization might choose WFFC; it does not mean our Minikube experiment successfully provisioned a topology-aware volume.

---

## 5. Compare All Four Approaches from a Business Perspective

| Experiment | Storage approach | Business priority | Typical situation |
|---|---|---|---|
| A | PVC without matching storage | Identify missing infrastructure | Storage has not been allocated |
| B | Static provisioning | Explicit control | Pre-allocated storage managed by infrastructure |
| C | Dynamic provisioning – Immediate | Automation and self-service | General-purpose application storage |
| D | Dynamic provisioning – WFFC | Scheduling and storage topology coordination | Multi-zone or node-constrained storage |

## 6. How Would a Deployment Engineer Decide?

Consider these questions before selecting a storage approach:

| Question | What it helps determine |
|---|---|
| Is storage managed manually or automatically? | Static or dynamic provisioning |
| Does the application need a specific pre-allocated volume? | Whether static provisioning is appropriate |
| Should application teams provision storage independently? | Whether dynamic provisioning is appropriate |
| Does storage need to match the Pod's eventual location? | Whether WFFC is appropriate |
| Does the storage provider support the required access mode and topology? | Whether the chosen StorageClass can satisfy the workload |

### A practical decision-making example

Imagine a company deploying three different workloads:

1. **An internal reporting application:** It needs ordinary persistent storage and has no special node-placement requirements. Dynamic provisioning with Immediate may be sufficient.

2. **A legacy application with a dedicated pre-allocated storage volume:** Static provisioning may be appropriate because the infrastructure team wants to assign a particular existing volume.

3. **A database using zone-specific cloud block storage:** WFFC may be appropriate because the storage location must be compatible with the node selected for the database Pod.

The choice is driven by application and infrastructure requirements, not by which Kubernetes configuration is newer or more advanced.

---

## 7. Final Learning

These four experiments represent different storage situations that a deployment engineer may encounter:

- Experiment A teaches us to identify missing storage dependencies.
- Experiment B teaches us how manually managed storage can be assigned to workloads.
- Experiment C teaches us how to automate storage allocation.
- Experiment D teaches us how storage provisioning can coordinate with workload scheduling, and how to diagnose a provisioning failure.

**The real engineering skill is not simply knowing how to create a PVC. It is understanding the application's storage requirements, choosing an appropriate provisioning approach, and troubleshooting the complete storage lifecycle.**