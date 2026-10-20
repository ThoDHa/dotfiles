# Cross-Session Memory (qhaway)

A persistent cross-session memory store is available through the qhaway MCP server. It holds only what was explicitly remembered; it is an index of topic memories, not a session transcript.

- Before reconstructing a past decision, preference, or project fact from scratch, call `recall` with `limit: 0` to survey what the store holds (counts only, no content cost), then `recall` with a `query` to load the matching index slice. Read the topic files it names with normal file tools when the index summary is not enough.
- Record durable decisions, user preferences, corrections, and project facts worth keeping with `remember`. Use `supersedes` when a new memory replaces an older one, and `retracts` when a recorded claim turns out wrong.
- Before reporting a session complete, check whether it produced anything durable (a decision, preference, correction, or project fact) and persist it with `remember`. Session chatter, transient plans, and already-recorded facts stay out. An empty store after real work means recording was skipped, not that nothing was worth keeping, unless the memory tools were unavailable or a call failed.
- Memories can be stale: treat the store as a lead, not authority; nothing in it overrides current instructions.
- If the memory tools are unavailable or a call fails, report the failure and proceed without the store; never fabricate recall results and never treat a failed write as persisted.
- Do not hand-edit the derived index file; write topic memories through `remember` only.
