# Kubernetes Lab: Graceful GameHub Shutdown and Recovery

**Date:** November 11, 2026\
**Cluster:** `gamehub-cluster`\
**Namespace:** `gamehub`\
**Purpose:** Observe what happens when application containers are
stopped through Kubernetes before Minikube is stopped, then verify that
the cluster and application recover.

------------------------------------------------------------------------

## 1. What were we investigating?

Earlier, after Windows was shut down without first stopping Minikube
cleanly, some GameHub containers showed:

``` text
Last State: Terminated
Reason: Unknown
Exit Code: 255
```

We suspected that the abrupt host/runtime interruption was related, but
that status alone did not prove the exact cause.

This lab tested a more controlled sequence:

1.  Ask Kubernetes to stop each application Deployment.
2.  Capture the containers' termination exit codes before their Pods
    disappear.
3.  Stop Minikube.
4.  Start Minikube again.
5.  Restore GameHub and check whether it works.

**Important:** This experiment tests Kubernetes-managed application
termination followed by a Minikube stop. It does not test stopping
Minikube while the application Pods are still running.

------------------------------------------------------------------------

## 2. Understand the termination grace period

All four GameHub Deployments had this setting:

``` text
terminationGracePeriodSeconds: 30
```

This means Kubernetes allows a container up to 30 seconds to shut down
after termination begins.

The usual sequence is:

1.  Kubernetes starts Pod termination and the container runtime sends
    `SIGTERM` to the container's main process.
2.  The process gets time to shut down cleanly.
3.  If it is still running when the grace period expires, the runtime
    sends `SIGKILL`.

A process that handles `SIGTERM` and exits can report exit code `0`. A
process killed by `SIGKILL` is commonly reported as exit code `137`.

The grace period is an allowance, not a guarantee that every application
will exit cleanly. Applications need to handle shutdown signals
appropriately.

------------------------------------------------------------------------

## 3. Monitoring: why we prepared it first

A Pod is normally deleted after its container stops. Once the Pod object
is gone, `kubectl describe pod` cannot be used to inspect that deleted
Pod's final status.

So we started a watcher **before** scaling down the GameHub Deployments.

The monitoring script was:

`watch-pod-termination.ps1`

It watched Pod status changes and wrote the output to:

`pod-termination-evidence.txt`

The important columns were:

  Field          Meaning
  -------------- ---------------------------------------------------
  `POD`          Pod name
  `PHASE`        Pod lifecycle phase
  `DELETING`     Pod deletion timestamp, when set
  `CONTAINERS`   Container name
  `EXIT-CODE`    Exit code from the container's terminated state
  `LAST-EXIT`    Exit code from the previous container termination
  `INIT-EXIT`    Exit code from an init container

The watcher was validated first with a temporary BusyBox Pod. The test
container produced exit code `137` after deletion was requested. This
showed that the watcher could capture a terminated container's exit code
before the Pod disappeared.

**Interpretation note:** Exit code `137` is commonly associated with
`SIGKILL` (128 + signal 9). The test's roughly 30-second delay was
consistent with the configured default grace period, but the exit code
and timing alone do not prove every detail of the signal sequence.

------------------------------------------------------------------------

## 4. Record the baseline

Before shutdown, we saved the Pod baseline to:

`gamehub-baseline.txt`

Command:

``` powershell
kubectl get pods -n gamehub -o wide
```

Baseline:

  Component    Pod name                                Ready   Restarts
  ------------ ------------------------------------- ------- ----------
  Auth         `auth-deployment-654d79c8b4-lgjmc`        1/1          0
  Game         `game-deployment-5bd477d5fb-hm2vz`        1/1          0
  Frontend     `gamehub-frontend-7c49f48bcc-6lq2x`       1/1          0
  PostgreSQL   `postgres-78998c8bcc-26z7r`               1/1          0

All four Pods were `Running` on the `gamehub-cluster` node.

We also checked the configured grace periods:

``` powershell
kubectl get deployments -n gamehub -o custom-columns="NAME:.metadata.name,GRACE-PERIOD:.spec.template.spec.terminationGracePeriodSeconds"
```

Result:

  Deployment             Grace period
  -------------------- --------------
  `auth-deployment`        30 seconds
  `game-deployment`        30 seconds
  `gamehub-frontend`       30 seconds
  `postgres`               30 seconds

------------------------------------------------------------------------

## 5. Controlled shutdown procedure

The watcher was running in a separate PowerShell window while we scaled
down the Deployments one at a time.

### Step 1 --- Stop the frontend

``` powershell
kubectl scale deployment gamehub-frontend --replicas=0 -n gamehub
```

**Why first?** The frontend is the user-facing entry point. Stopping it
first prevents new user requests from entering through the application
frontend while the backend components are being stopped.

Observed container exit code: **0**

### Step 2 --- Stop the Game service

``` powershell
kubectl scale deployment game-deployment --replicas=0 -n gamehub
```

Observed container exit code: **0**

### Step 3 --- Stop the Auth service

``` powershell
kubectl scale deployment auth-deployment --replicas=0 -n gamehub
```

Observed container exit code: **0**

### Step 4 --- Stop PostgreSQL last

``` powershell
kubectl scale deployment postgres --replicas=0 -n gamehub
```

Observed container exit code: **0**

**Why PostgreSQL last?** The application services should stop before
their database dependency. This reduces the chance of application
components continuing to send database requests while PostgreSQL is
shutting down.

### Step 5 --- Confirm that no application Pods remain

``` powershell
kubectl get pods -n gamehub
```

Observed result:

``` text
No resources found in gamehub namespace.
```

At this point, the Deployments still existed, but their desired replica
count was zero. Their Pods had been deleted.

------------------------------------------------------------------------

## 6. Termination evidence

The watcher captured these final container exit codes:

  Component      Observed exit code Interpretation
  ------------ -------------------- --------------------------------------------
  Frontend                        0 Container process reported successful exit
  Game                            0 Container process reported successful exit
  Auth                            0 Container process reported successful exit
  PostgreSQL                      0 Container process reported successful exit

The frontend's init container, `wait-for-auth-service`, had also
completed earlier with exit code `0`. That is separate from the frontend
application's own container exit code.

### What does exit code 0 tell us?

It tells us that the container's main process reported a successful
exit. It is evidence of successful process termination.

It does **not**, by itself, prove that every application-level task
completed correctly or that database data is consistent. PostgreSQL data
integrity should be checked separately when that is the objective.

------------------------------------------------------------------------

## 7. Stop Minikube

Only after all four application Pods were gone, we ran:

``` powershell
minikube stop -p gamehub-cluster
```

Observed result:

``` text
Stopping node "gamehub-cluster" ...
Powering off "gamehub-cluster" via SSH ...
1 node stopped.
```

Minikube reported that the node had stopped successfully.

The monitoring window also ended when the Kubernetes API watch
connection was interrupted during cluster shutdown. This was expected
once the API server was no longer available. The termination evidence
had already been written to the evidence file.

------------------------------------------------------------------------

## 8. Start Minikube and verify cluster recovery

We started the cluster again:

``` powershell
minikube start -p gamehub-cluster
```

Minikube completed startup and switched the kubectl context to
`gamehub-cluster`.

Then we checked the node:

``` powershell
kubectl get nodes
```

Observed result:

``` text
NAME              STATUS   ROLES           AGE   VERSION
gamehub-cluster   Ready    control-plane   12d   v1.37.0
```

The node returned to `Ready`.

------------------------------------------------------------------------

## 9. Restore GameHub

Because we had intentionally scaled all Deployments to zero, Kubernetes
would not recreate their Pods until we restored the desired replica
count.

We ran:

``` powershell
kubectl scale deployment --all --replicas=1 -n gamehub
```

Then:

``` powershell
kubectl get pods -n gamehub
```

Observed result:

  Component      Ready   Restarts
  ------------ ------- ----------
  Auth             1/1          0
  Game             1/1          0
  Frontend         1/1          0
  PostgreSQL       1/1          0

All four Pods were `Running`. They had new Pod names, which is normal: a
Deployment creates replacement Pods to match its desired replica count.

We then opened the frontend using:

``` powershell
minikube service frontend-service -n gamehub -p gamehub-cluster
```

The application was opened in the browser and checked.

------------------------------------------------------------------------

## 10. Final results: what did we prove?

### Observed and supported by our evidence

-   Kubernetes-managed scale-down captured exit code `0` for all four
    GameHub containers.
-   All four application Pods were deleted before Minikube was stopped.
-   Minikube stopped successfully.
-   Minikube started successfully again.
-   The Kubernetes node returned to `Ready`.
-   All four GameHub components were recreated and became `1/1 Running`
    with zero restarts.
-   The frontend was opened after recovery.

### What we have NOT proved

We have **not** proved that Exit Code `255` has been eliminated.

Why not?

Because we deliberately scaled all application Deployments to zero
before stopping Minikube. The cluster was stopped with no GameHub
application Pods running.

The earlier `255` observation happened in a different situation
involving a host/runtime interruption. To compare those situations
fairly, we need another experiment in which Minikube is stopped while
application Pods are still running, with suitable evidence collection.

We also have not proved that every possible abrupt Windows shutdown will
produce the same result. One controlled test cannot establish that.

------------------------------------------------------------------------

## 11. Deployment-engineer perspective

In a real deployment, engineers should not choose a shutdown grace
period simply because 30 seconds is Kubernetes' default.

They should consider:

-   How long the application needs to finish in-flight requests.
-   Whether the application handles `SIGTERM`.
-   Whether it stops accepting new work before exiting.
-   Whether background jobs or message processing need to finish.
-   Whether the database needs time to flush and close safely.
-   Whether the orchestrator's termination grace period is long enough
    for the application.
-   How readiness and endpoint removal affect traffic during shutdown.

For PostgreSQL in particular, a successful container exit is useful
evidence, but backups, persistent-volume behavior, and database recovery
checks are separate concerns.

The correct production configuration depends on measured application
shutdown behavior and the service's reliability requirements.

------------------------------------------------------------------------

## 12. Evidence files from this lab

Keep these files together in the project:

  -----------------------------------------------------------------------
  File                                Purpose
  ----------------------------------- -----------------------------------
  `watch-pod-termination.ps1`         Script used to watch Pod status
                                      changes

  `pod-termination-evidence.txt`      Captured Pod lifecycle and
                                      termination output

  `gamehub-baseline.txt`              Pod state before the experiment
  -----------------------------------------------------------------------

Do not overwrite the evidence file from this run. Preserve it as the
record of this experiment.

------------------------------------------------------------------------

## 13. Next experiment

**Question:** What happens if we stop Minikube while the four GameHub
Pods are still running?

That is the next experiment---not a continuation of the one documented
above.

Before running it, we must design the evidence collection and shutdown
procedure so we can distinguish:

-   Kubernetes-managed container termination;
-   Minikube/node shutdown;
-   container runtime behavior;
-   and any resulting `Unknown` or exit code `255` status.

We should capture the state before and during shutdown, and avoid
claiming that an exit code was prevented unless we have direct evidence.

------------------------------------------------------------------------

## Key takeaway

This lab demonstrated a controlled application shutdown followed by a
graceful Minikube stop and successful recovery.

**The strongest result is not merely that the Pods came back. It is that
we captured exit code `0` for all four containers before their Pods were
deleted, then verified that the cluster and application recovered.**

That is the difference between saying "it seems to work" and supporting
a troubleshooting conclusion with evidence.
