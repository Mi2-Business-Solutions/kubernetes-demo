# Kubernetes Pod Scheduling – Affinity, Anti-Affinity, Taints and Tolerations

## 1. Understanding the basic analogy

Imagine a company with multiple office rooms.

We can compare Kubernetes scheduling with how employees are assigned to office rooms.

| Office analogy | Kubernetes |
|---|---|
| Office room | Node |
| Employee | Pod |
| Room identification tag | Node label |
| Employee identification tag | Pod label |
| Employee's room preference | Affinity |
| Employee's room avoidance | Anti-affinity |
| Room access restriction | Taint |
| Employee's permission to tolerate restriction | Toleration |

**Important:** Kubernetes uses these mechanisms to decide where pods should run and which nodes should accept them.

---

## 2. Node Affinity – Pod wants a particular node

### Office analogy

Imagine an employee named PostgreSQL.

PostgreSQL says:

"I want to work in the Database Room."

The company has labelled one room as `database`.

PostgreSQL chooses that room based on its label.

### Kubernetes meaning

Node affinity allows a pod to specify which nodes it prefers or requires based on node labels.

### Business example

A company wants database workloads to run on nodes specifically designated for database workloads.

### Visual representation

```text
       PostgreSQL Pod
              |
              | Wants database node
              v
       +------------------+
       | Node 1           |
       | label: general   |
       +------------------+
              X
       +------------------+
       | Node 2           |
       | label: database |
       +------------------+
              ^
              |
         Selected node
```

**Remember:** The pod decides which node it wants.

---

## 3. Node Anti-Affinity – Pod wants to avoid a particular node

### Office analogy

Imagine an employee named Frontend.

Frontend says:

"I don't want to work in the Database Room. Give me another suitable room."

It avoids the room labelled `database`.

### Kubernetes meaning

Node anti-affinity is commonly used to describe a node avoidance requirement or preference. In Kubernetes, this is implemented using node affinity with the `NotIn` or `DoesNotExist` operators.

### Business example

Ordinary application workloads should avoid nodes reserved for database infrastructure.

### Visual representation

```text
        Frontend Pod
              |
              | Avoid database nodes
              |
       +------------------+
       | Node 1           |
       | label: general   |
       +------------------+
              |
          Can run here

       +------------------+
       | Node 2           |
       | label: database |
       +------------------+
              X
          Avoid this node
```

**Remember:** The pod says which nodes it wants to avoid.

---

## 4. Pod Affinity – Pod wants to stay near another pod

### Office analogy

Imagine two employees:

- Auth employee
- Game employee

Auth says:

"I want to work in the same room as Game because we frequently communicate."

The company tries to assign both employees to the same room.

### Kubernetes meaning

Pod affinity allows a pod to prefer or require scheduling near other pods based on their labels and topology.

### Business example

Two closely related application components may benefit from being scheduled in the same availability zone or on the same node.

### Visual representation

```text
       Node 1
   +-------------------+
   | Auth Pod          |
   | Game Pod          |
   +-------------------+

       Node 2
   +-------------------+
   | Other workloads   |
   +-------------------+
```

**Remember:** The pod wants to stay near another matching pod.

---

## 5. Pod Anti-Affinity – Pod wants to stay away from another pod

### Office analogy

Imagine a company running two Frontend employees (replicas).

Frontend replica 1 is working in Room 1.

Frontend replica 2 says:

"I don't want to share the same room with another Frontend replica. Put me in another room."

Why?

If Room 1 becomes unavailable, both replicas should not go down together.

### Kubernetes meaning

Pod anti-affinity allows a pod to avoid scheduling near other matching pods.

### Business example

A company runs multiple replicas of its application and wants them distributed across different nodes to improve availability.

### Visual representation

```text
       Node 1                 Node 2
   +---------------+      +---------------+
   | Frontend Pod 1|      | Frontend Pod 2|
   +---------------+      +---------------+

       Separate nodes

   If Node 1 fails, Node 2
   can continue serving traffic.
```

**Remember:** The pod wants to stay away from another matching pod.

---

## 6. Taints – Node restricts entry

### Office analogy

Imagine the company has a special GPU Room.

The company puts a restriction on the room:

"Only authorized employees can enter."

Even if a Frontend employee wants to enter, the room rejects them unless they have permission to tolerate the restriction.

### Kubernetes meaning

A taint is applied to a node to repel pods that do not have a matching toleration.

### Business example

GPU hardware is expensive. A company wants to reserve GPU nodes for machine learning workloads instead of allowing ordinary application pods to consume those resources.

### Visual representation

```text
          GPU Node
    +---------------------+
    |                     |
    |   RESTRICTED ROOM   |
    |                     |
    |   Taint applied     |
    |                     |
    +---------------------+
              |
       No matching
       toleration
              |
              X
       Frontend Pod
       Cannot enter
```

**Remember:** The node controls which pods it rejects.

---

## 7. Tolerations – Pod is allowed to enter

### Office analogy

Now imagine an ML employee.

The company gives this employee an access card.

The GPU Room has a restriction, but the ML employee has permission to tolerate that restriction.

The employee can now enter the GPU Room.

However, having an access card does not mean the employee will automatically go to that room.

It only means the employee is allowed to enter.

### Kubernetes meaning

A toleration allows a pod to be scheduled on a node that has a matching taint.

### Business example

Machine learning pods have tolerations that allow them to run on dedicated GPU nodes.

### Visual representation

```text
          GPU Node
    +---------------------+
    |                     |
    |   RESTRICTED ROOM   |
    |                     |
    |   Taint applied     |
    |                     |
    +---------------------+
              ^
              |
        Matching
        toleration
              |
          ML Pod
       Allowed to enter
```

**Important:** A toleration does not guarantee scheduling on that node. It only removes the taint-based restriction.

---

# 8. Complete comparison

| Concept | Who makes the decision? | Meaning |
|---|---|---|
| Node affinity | Pod | I want this node. |
| Node anti-affinity | Pod | I want to avoid this node. |
| Pod affinity | Pod | I want to stay near another pod. |
| Pod anti-affinity | Pod | I want to stay away from another pod. |
| Taint | Node | I reject certain pods. |
| Toleration | Pod | I can tolerate the restriction. |

## 9. Why combine taints, tolerations and node affinity?

### Business scenario: Dedicated PostgreSQL node

Imagine a company has three nodes:

| Node | Purpose |
|---|---|
| Node 1 | General workloads |
| Node 2 | Database workloads |
| Node 3 | GPU workloads |

The company wants PostgreSQL to run exclusively on Node 2.

It also wants to prevent unrelated application pods from accidentally running there.

### Configuration strategy

**Step 1: Apply a taint to Node 2.**

The node rejects pods without matching tolerations.

**Step 2: Add a toleration to PostgreSQL.**

PostgreSQL is now allowed to run on Node 2.

**Step 3: Add node affinity to PostgreSQL.**

PostgreSQL is directed to Node 2 using its database label.

### Visual representation

```text
          PostgreSQL Pod
                 |
        +--------+--------+
        |                 |
    Toleration        Node Affinity
        |                 |
   Permission          Selection
        |                 |
        +--------+--------+
                 |
                 v
       +--------------------+
       | Node 2             |
       | Database Node      |
       |                    |
       | Taint applied      |
       +--------------------+
                 |
        PostgreSQL allowed
```

### What happens to other pods?

```text
Frontend Pod
     |
     | No matching toleration
     |
     X
     |
Database Node
```

The frontend pod cannot be scheduled on Node 2 because of its taint.

This gives the company two protections:

1. PostgreSQL is directed to the database node.
2. Unrelated pods are prevented from entering the database node.

---

# 10. Three types of taint effects

| Effect | Behaviour |
|---|---|
| NoSchedule | New pods without matching tolerations cannot be scheduled. Existing pods continue running. |
| PreferNoSchedule | Kubernetes tries to avoid scheduling pods without matching tolerations but may still schedule them. |
| NoExecute | Pods without matching tolerations are not scheduled, and existing non-tolerating pods can be evicted. |

---

# 11. Important Kubernetes scheduling takeaway

Remember these two groups:

### Group 1: Pod placement decisions

- Node affinity
- Node anti-affinity
- Pod affinity
- Pod anti-affinity

These determine where a pod should or should not run.

### Group 2: Node access restrictions

- Taints
- Tolerations

These determine whether a pod can tolerate a node's restrictions.

**The most important distinction:**

Affinity tells Kubernetes where a pod wants to go.

Taints tell Kubernetes which pods a node wants to keep away.

Tolerations allow pods to enter nodes despite matching taints.

---

# 12. Knowledge check

### Question 1

A company has a GPU node with a taint. A frontend pod has no matching toleration.

What happens?

Answer: The frontend pod cannot be scheduled on that node because of the taint.

### Question 2

A PostgreSQL pod has node affinity selecting the database node. Can an unrelated frontend pod still be scheduled on that database node?

Answer: Yes. PostgreSQL's node affinity does not restrict other pods.

### Question 3

A pod has a matching toleration for the GPU node. Does that guarantee that it will run on the GPU node?

Answer: No. A toleration only permits scheduling despite the taint. Node affinity or another placement rule can direct it there.

### Question 4

Why combine taints, tolerations and node affinity?

Answer: To reserve a node for intended workloads, allow authorized pods to use it, and direct those pods to the correct node.

---

**Final takeaway:** Kubernetes scheduling is not just about finding an available node. It is also about controlling workload placement, protecting resources, and maintaining application availability.