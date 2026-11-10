
# Kubernetes Probes — Beginner-Friendly Notes

## 1. First, what are probes?

Imagine Kubernetes is managing a shopping mall. Inside the mall, there are different shops:

- Frontend is like the customer-facing entrance or service counter.
- Auth is like the identity-check counter.
- Game is like the game-service counter.
- PostgreSQL is like the records room where customer information is stored.

Kubernetes needs a way to check whether each application is starting, ready to serve requests, and still functioning.

A **probe** is a health check that Kubernetes performs on a container.

There are three main probes:

## 2. Startup probe — Has the shop finished opening?

Imagine a shop needs time to open in the morning. The staff must arrive, switch on the lights, arrange products, and start the billing machine.

While this is happening, the shop is not ready yet. That does not mean the shop is broken. It simply needs time to start.

The startup probe checks whether the application has finished starting.

- If the startup probe succeeds, Kubernetes allows the readiness and liveness checks to take over.
- While the startup probe is still failing, Kubernetes does not run the liveness or readiness probes for that container.
- If it keeps failing until the configured failure threshold is reached, Kubernetes restarts the container.

**In simple words:** Has the application finished starting?

## 3. Readiness probe — Can the shop serve customers right now?

Imagine the shop has opened, but the billing machine is temporarily busy restarting. The shop itself is not broken, but it cannot serve customers at this moment.

The readiness probe checks whether the container is ready to receive normal traffic.

- If readiness succeeds, the Pod can receive traffic through its Kubernetes Service.
- If readiness fails, Kubernetes marks the Pod as not ready and stops sending normal Service traffic to it.
- Kubernetes does not restart the container just because its readiness probe fails.

When the check succeeds again, the Pod can receive traffic again.

**In simple words:** Can the application handle requests right now?

## 4. Liveness probe — Is the shop still functioning?

Imagine the billing machine has frozen completely. Nobody can use it, and waiting longer will not fix it. The machine needs to be restarted.

The liveness probe checks whether the container is still functioning in a way that should allow it to keep running.

- If liveness succeeds, the container continues running.
- If it fails repeatedly until the configured failure threshold is reached, Kubernetes restarts the container.

**In simple words:** Is the application still working, or does its container need a restart?

## 5. How does Kubernetes actually perform these checks?

This is an important distinction: not every probe runs a command.

Kubernetes supports different probe methods. In our GameHub YAML files, we use TCP checks for Frontend, Auth, and Game, and an Exec check for PostgreSQL.

### A. Exec probe — Kubernetes runs a command inside the container

**Mall example:** A supervisor goes inside the shop and asks an employee to perform a specific test.

For PostgreSQL, our YAML uses:

```yaml
exec:
  command:
    - sh
    - -c
    - 'pg_isready -U "$POSTGRES_USER" -d "$POSTGRES_DB"'
```

What happens?

1. Kubernetes asks the container runtime to execute the command inside the PostgreSQL container.
2. The command `pg_isready` checks whether PostgreSQL is accepting connection attempts.
3. The command returns an exit code.
4. Exit code `0` means the check succeeded. A non-zero exit code means it failed.

**Where does the command run?**

Inside the PostgreSQL container — not in your Windows PowerShell window. The kubelet on the Minikube node coordinates the check through the container runtime.

Important: `pg_isready` tells us whether PostgreSQL is accepting connection attempts. It does not prove that every database query or every application operation will work.

### B. TCP probe — Kubernetes checks whether it can connect to a port

**Mall example:** The supervisor does not go inside the shop or ask anyone to run a command. The supervisor simply checks whether the shop's door can be opened.

In a TCP probe, Kubernetes tries to establish a network connection to the Pod's IP address and the configured port.

For our GameHub containers:

- Frontend: port `80`
- Auth: port `8080`
- Game: port `8081`

What happens?

1. The kubelet attempts to connect to the container's Pod IP and configured TCP port.
2. If the connection is established, the check succeeds.
3. If the connection cannot be established, the check fails.

**What is it actually checking?**

It checks whether something is accepting TCP connections on that port. It does not send a login request, call an API, or verify that the application is returning the correct business response.

For example, a successful TCP check on Auth port `8080` does not prove that a user can log in successfully.

### C. HTTP probe — Kubernetes sends an HTTP request

**Mall example:** The supervisor walks to the counter and asks a specific question. The shop must respond in an acceptable way.

An HTTP probe sends an HTTP GET request to a configured path on the container.

For example, if an application has a health endpoint, the probe could request:

```text
GET /health
```

What happens?

1. The kubelet sends an HTTP GET request to the Pod.
2. The application responds with an HTTP status code.
3. A status code from `200` through `399` is considered successful.
4. Other status codes are considered failures.

**What is it actually checking?**

It checks whether the configured HTTP endpoint responds with an accepted status code. How much this proves depends on what the endpoint itself checks.

For example, a `/health` endpoint might only say that the web process is alive. A more carefully designed health endpoint could also check whether an important dependency is reachable.

Important for our GameHub project: the application code we reviewed did not have a dedicated `/health` or `/healthz` endpoint. We should not configure an HTTP probe to use such a path unless we add that endpoint first.

## 6. Quick comparison of the probe methods

### Exec
- **What Kubernetes does:** Runs a command.
- **Where the check happens:** Inside the container.
- **Our example:** PostgreSQL runs `pg_isready`.

### TCP
- **What Kubernetes does:** Tries to establish a connection to a port.
- **Where the check happens:** The kubelet attempts a connection to the Pod's IP and port.
- **Our examples:** Frontend `80`, Auth `8080`, Game `8081`.

### HTTP
- **What Kubernetes does:** Sends an HTTP GET request to a path.
- **Where the check happens:** The kubelet sends the request to the Pod's HTTP endpoint.
- **Example:** A GET request to `/health`, if the application provides that endpoint.

## 7. What our GameHub probes check

| Component | Probe method | What is checked |
|---|---|---|
| Frontend | TCP | Can Kubernetes connect to port 80? |
| Auth | TCP | Can Kubernetes connect to port 8080? |
| Game | TCP | Can Kubernetes connect to port 8081? |
| PostgreSQL | Exec | Does `pg_isready` report that PostgreSQL is accepting connections? |

Remember: these checks are useful, but they do not prove that the entire GameHub application works end to end. We still need to test the actual frontend, APIs, authentication, game operations, and database interactions.

## 8. Remember the difference

- **Startup:** Has the application finished starting?
- **Readiness:** Can it receive traffic right now?
- **Liveness:** Is it still functioning, or should Kubernetes restart its container?

And remember the methods:

- **Exec:** Run a command inside the container.
- **TCP:** Try to connect to a port.
- **HTTP:** Send an HTTP GET request to a path.
