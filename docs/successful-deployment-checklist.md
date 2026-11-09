# Kubernetes Successful Deployment Checklist

## Purpose

This document provides a step-by-step checklist to verify whether an application has been deployed successfully in Kubernetes.

**Important:** Successfully applying YAML files does not necessarily mean the application is working correctly.

We need to verify:
1. Kubernetes resources are created successfully.
2. Pods and containers are running correctly.
3. Services can communicate with the intended Pods.
4. The application is accessible.
5. The application's functionality works as expected.

---

# 1. Verify Deployment Status

### Command

```powershell
kubectl get deployments -n <namespace>
```

### What to check?

| Column | Meaning |
|---|---|
| NAME | Deployment name |
| READY | Ready replicas / desired replicas |
| UP-TO-DATE | Replicas using the latest Deployment configuration |
| AVAILABLE | Replicas available to serve requests |
| AGE | How long the Deployment has existed |

### Expected result

For a Deployment with one replica:

```text
NAME             READY   UP-TO-DATE   AVAILABLE
auth-deployment  1/1     1            1
```

This indicates that the desired replica is ready and available.

### Common issues

- `0/1`: No replica is ready.
- `1/2`: Only one of the two desired replicas is ready.
- `0/2`: Neither replica is ready.

### If something is wrong

Inspect the Deployment:

```powershell
kubectl describe deployment <deployment-name> -n <namespace>
```

Check its conditions, events, replica status and selector configuration.

---

# 2. Verify Pod Status

### Command

```powershell
kubectl get pods -n <namespace>
```

### What to check?

| Column | Meaning |
|---|---|
| NAME | Pod name |
| READY | Ready containers / total containers |
| STATUS | Current Pod phase or displayed status |
| RESTARTS | Number of container restarts |
| AGE | How long the Pod has existed |

### Common Pod statuses

| Status | Meaning |
|---|---|
| Running | Pod is running; check READY to confirm readiness |
| Pending | Pod is waiting to be scheduled or for another requirement |
| ImagePullBackOff | Kubernetes cannot pull the container image |
| ErrImagePull | Container image pull failed |
| CrashLoopBackOff | Container repeatedly crashes and restarts |
| Completed | Container has finished execution |

### Important checks

- Is the Pod in `Running` state?
- Does READY show the expected number of containers?
- Are there repeated restarts?
- Is the Pod running on the expected node?

**Note:** A Pod showing `Running` does not automatically mean the application inside it is ready to serve requests.

---

# 3. Inspect Pod Details and Events

Use this step when a Pod is not working as expected.

### Command

```powershell
kubectl describe pod <pod-name> -n <namespace>
```

### What to check?

1. **State:** Is the container running, waiting or terminated?
2. **Last State:** Did the container terminate previously?
3. **Reason:** Is there a specific failure reason?
4. **Events:** What actions or errors did Kubernetes report?

Pay particular attention to the Events section at the bottom.

### Common issues

- Failed image pull.
- Insufficient CPU or memory.
- Pod scheduling failure.
- Missing configuration.
- Volume mounting failure.
- Container startup failure.

Events help identify what Kubernetes encountered while creating or managing the Pod.

---

# 4. Check Container Logs

Logs help us understand what is happening inside the application.

### Command

```powershell
kubectl logs <pod-name> -n <namespace>
```

### What to check?

- Did the application start successfully?
- Are there startup errors?
- Are required environment variables missing?
- Are there database or API connection failures?
- Are there application exceptions?
- Is the application listening on the expected port?

### Check logs from a previous container instance

If a container restarted, its previous logs may contain the actual failure.

```powershell
kubectl logs <pod-name> -n <namespace> --previous
```

**Important:** Current logs show the current container instance. Previous logs help investigate an earlier crashed instance.

---

# 5. Verify Services

Services provide stable network access to Pods.

### Command

```powershell
kubectl get services -n <namespace>
```

### What to check?

| Field | What to verify |
|---|---|
| NAME | Correct Service name |
| TYPE | Correct Service type |
| CLUSTER-IP | Cluster-internal IP assigned |
| EXTERNAL-IP | Depends on the Service type and environment |
| PORT(S) | Correct Service port and NodePort, if applicable |

### Common Service types

| Type | Purpose |
|---|---|
| ClusterIP | Provides internal cluster communication |
| NodePort | Exposes the Service through a port on each node |
| LoadBalancer | Requests an external load balancer from a supported environment |

### Verify port mapping

For example:

```yaml
ports:
  - protocol: TCP
    port: 8080
    targetPort: 8080
```

- `port`: Port exposed by the Service.
- `targetPort`: Port on the destination Pod.

For a NodePort Service, Kubernetes also assigns a NodePort unless one is explicitly configured.

---

# 6. Verify Service Endpoints

This is an important check to confirm whether a Service has found its intended Pods.

### Command

```powershell
kubectl get endpoints -n <namespace>
```

### What to check?

- Does each Service have the expected endpoint IP and port?
- Is the endpoint list empty?
- Does the endpoint port match the application's listening port?

### Understand the relationship

```text
Service
   |
   | selector
   v
Pod labels
   |
   | match
   v
Matching Pods
   |
   v
Service Endpoints
```

For example:

Service selector:

```yaml
selector:
  app: auth-service
```

Pod labels:

```yaml
labels:
  app: auth-service
```

These labels must match for the Service to select the Pod.

### Common issue

If a Service has no endpoints, check:

1. Service selector.
2. Pod labels.
3. Whether the matching Pods are ready.

**Note:** In newer Kubernetes versions, EndpointSlices are the preferred API for representing endpoints. You can also inspect them using:

```powershell
kubectl get endpointslices -n <namespace>
```

---

# 7. Verify Application Accessibility

Now we move beyond Kubernetes resource status and check whether users can access the application.

For a Minikube NodePort Service:

```powershell
minikube service <service-name> -n <namespace>
```

This opens the Service URL in the browser.

### What to check?

- Does the frontend load?
- Does the application display correctly?
- Are there any browser errors?
- Are API requests successful?
- Can the frontend communicate with backend Services?

For more detailed investigation, use browser Developer Tools:

- Console: Check JavaScript errors.
- Network: Check failed API requests and HTTP status codes.

---

# 8. Verify End-to-End Application Functionality

A frontend page loading successfully does not guarantee that the complete application works.

Test the actual application workflows.

For example, in GameHub:

- Does the frontend load?
- Does authentication work?
- Can the application communicate with the Game service?
- Do API requests return expected responses?
- Are there any backend errors?

### Example application communication flow

```text
             Browser
                |
                v
         Frontend Service
                |
                v
           Frontend Pod
             (Nginx)
                |
          +-----+-----+
          |           |
          v           v
     Auth Service  Game Service
          |           |
          v           v
       Auth Pod    Game Pod
```

The complete application is considered functional only after the required components can communicate and the expected workflows succeed.

---

# 9. Quick Troubleshooting Reference

| Problem | First investigation |
|---|---|
| Deployment shows 0/1 READY | `kubectl describe deployment` |
| Pod is Pending | `kubectl describe pod` |
| Pod is CrashLoopBackOff | `kubectl logs` and `--previous` |
| Pod is ImagePullBackOff | Check image name, tag, registry access and Pod events |
| Pod repeatedly restarts | Check current and previous logs |
| Service has no endpoints | Check Service selectors and Pod labels |
| Frontend loads but API fails | Check Nginx logs, backend logs and Service connectivity |
| Application loads but functionality fails | Check API responses, application logs and dependencies |

---

# 10. Reusable Deployment Verification Checklist

Use this checklist every time you deploy an application.

- [ ] Deployment objects are created successfully.
- [ ] Desired replicas are available.
- [ ] Pods are in the expected state.
- [ ] All expected containers are Ready.
- [ ] No unexpected or repeated container restarts.
- [ ] Pod details and events do not show unresolved errors.
- [ ] Application logs show successful startup.
- [ ] Services are created with the correct type.
- [ ] Service ports and targetPorts are correct.
- [ ] Services have the expected endpoints.
- [ ] Application is accessible.
- [ ] Frontend-to-backend communication works.
- [ ] Expected application workflows work successfully.

---

# Important: Deployment Success vs Application Success

| Level | What it proves |
|---|---|
| YAML applied | Kubernetes accepted the resource configuration |
| Deployment available | Desired replicas are available |
| Pod Ready | Containers have passed their readiness checks, if configured |
| Service endpoints present | Service has selected eligible backend Pods |
| Application accessible | Application can be reached through its access path |
| End-to-end functionality verified | Required application workflows work successfully |

**Final takeaway:** Never conclude that an application is successfully deployed just because `kubectl apply` returns `deployment created` or because a Pod shows `Running`.

Verify the entire flow, from Kubernetes resources to actual application functionality.