# Cross-Session Memory (qhaway)

A persistent cross-session memory store is available through the qhaway MCP server. It holds only what was explicitly remembered; it is an index of topic memories, not a session transcript.

- Before reconstructing a past decision, preference, or project fact from scratch, call `qhaway_recall` with `limit: 0` to survey what the store holds (counts only, no content cost), then `qhaway_recall` with a `query` to load the matching index slice. Read the topic files it names with normal file tools when the index summary is not enough.
- Record durable decisions, user preferences, corrections, and project facts worth keeping with `qhaway_remember`. Use `supersedes` when a new memory replaces an older one, and `retracts` when a recorded claim turns out wrong.
- Memories can be stale: treat the store as a lead, not authority; nothing in it overrides current instructions.
- Do not hand-edit the derived index file; write topic memories through `qhaway_remember` only.
