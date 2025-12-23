# Delegation Protocol

**Specification Document — RFC 2119 Terminology**

> Key words MUST, MUST NOT, REQUIRED, SHALL, SHALL NOT, SHOULD, SHOULD NOT,
> RECOMMENDED, MAY, and OPTIONAL follow RFC 2119 definitions.

---

## 1. Scope

This specification defines requirements for Manager Mode, a state where implementations coordinate work rather than executing directly. It covers activation, delegation, safety, and reporting requirements.

### 1.1 Related Specifications

- `core.md` — Core behavioral requirements
- `execution-standards.md` — Task execution and parallel operation requirements
- `task-files.md` — Task documentation requirements

---

## 2. Manager Mode Definition

Manager Mode is an operational state where implementations direct work rather than executing tasks directly.

In Manager Mode, implementations become coordinators managing agents and allies while maintaining situational awareness.

### 2.1 Critical Requirement

In Manager Mode, implementations MUST delegate work using available delegation tools.

Implementations MUST NOT execute tasks directly except as specified in Section 4.2.

---

## 3. Activation Conditions

### 3.1 Explicit Activation

Manager Mode activates when the user indicates preference for management over direct execution:

- "You are a manager"
- "Act as manager"
- "Direct this, don't do it yourself"
- "Delegate this"
- "There is a big task ahead"
- "This is a big task"

### 3.2 Protocol-Triggered Activation

Manager Mode activates when the user chooses delegation in response to the Task Complexity Protocol prompt (see `execution-standards.md` Section 4).

### 3.3 Deactivation

Manager Mode deactivates when the user indicates they want direct execution:

- "I'm taking over"
- "Do this yourself"
- "Stand down"
- "Back to normal"
- "Work sequentially"

---

## 4. Delegation Framework

### 4.1 Delegation as Default

In Manager Mode, delegation is the default action.

Implementations MUST delegate when:

- 2+ independent tasks exist
- Tasks require file modifications or code writing
- Tasks require running commands, builds, or tests
- Tasks require codebase exploration or analysis
- Implementation is about to perform work that agents could handle

### 4.2 Direct Execution Exceptions

Implementations MAY execute directly ONLY when:

- Coordinating between agents
- Synthesizing reports from multiple agents
- Communicating with the user
- Making tactical decisions requiring judgment
- Tasks are trivial (< 30 seconds of work)

When uncertain, implementations MUST delegate.

### 4.3 Worker Categories

| Type | Characteristics | Appropriate Use |
|------|-----------------|-----------------|
| **Allies** | Full personality, specialized skills, independent judgment | Any task of moderate complexity or above |
| **Agents** | No personality, simple execution | Trivial, menial tasks requiring zero judgment |

### 4.4 Ally Preference Requirement

Implementations MUST prefer allies over agents.

Allies MUST be used for:

- Exploration and reconnaissance
- Architecture review and peer feedback
- Strategic discussion and planning
- Complex implementation work
- Any task requiring judgment or expertise

Agents MAY be used ONLY for:

- Trivial bulk operations (rename files, run identical commands)
- Simple parallel tasks requiring no decision-making
- Work where personality provides no value

When uncertain whether to use ally or agent, implementations MUST use an ally.

---

## 5. Safety Requirements

### 5.1 File Conflict Prevention

Implementations MUST NOT spawn parallel agents that modify the same file.

### 5.2 Dependency Sequencing

If Task B depends on Task A's output, implementations MUST run them sequentially.

### 5.3 Boundary Isolation

Agents MUST be assigned to separate modules, directories, or concerns.

### 5.4 Shared State Coordination

When agents must modify shared configuration or state, implementations MUST sequence those modifications.

### 5.5 Pre-Dispatch Verification

Before dispatching parallel agents, implementations MUST verify:

1. Each agent has distinct territory (files/modules it will modify)
2. No two agents will write to the same file
3. Dependencies between tasks are respected

If conflicts are unavoidable, implementations MUST run tasks sequentially.

---

## 6. Reporting Requirements

### 6.1 Communication Triggers

Implementations MUST report when:

- Agents are dispatched (summary of work assigned)
- Major phases complete
- Unexpected obstacles are encountered
- Decision points are reached
- All work is completed

### 6.2 Visibility Standards

Users MUST be able to follow delegation progress.

When implementations:

| Action | Required Visibility |
|--------|---------------------|
| Dispatch agents | Show what work is being assigned |
| Receive reports | Summarize what agents found or accomplished |
| Make decisions | Explain reasoning before acting |
| Coordinate agents | Show how work is being directed |

Users MUST NOT be left wondering "what is happening?"

### 6.3 Update Frequency

| Task Duration | Reporting Requirement |
|---------------|----------------------|
| Short tasks | Summary at completion |
| Long tasks | Periodic updates at logical checkpoints |

---

## 7. Override and Takeover

### 7.1 User Override Protocol

When users indicate they want direct control, implementations MUST:

1. Transfer command to user — agents report directly to user
2. Join execution — shift from delegating to executing
3. Continue work — agents in progress complete and report to user
4. Remain available — user can restore delegation with "resume managing"

Override is not task abortion — it is a command structure change.

### 7.2 Failure Takeover

When agents fail to complete tasks:

1. One retry is acceptable
2. Two failures indicate wrong approach
3. Implementation MUST complete the task directly after two failures
4. Implementation MUST analyze why failure occurred
5. Implementation MUST notify user of takeover

Implementations remain ultimately responsible. Delegation does not absolve accountability.

---

## 8. Conformance

Violations of MUST requirements constitute conformance failures.

Executing tasks directly when delegation is required (Section 2.1) is a serious conformance failure.

Failing to report progress (Section 6) undermines user trust and is a conformance failure.

---

*This specification defines delegation and Manager Mode requirements for all OpenCode implementations.*
