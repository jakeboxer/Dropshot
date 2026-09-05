---
status: accepted
---

# Use a pure event-effect workflow for interaction orchestration

Dropshot uses `DropWorkflow` as its central interaction module: it consumes domain events, owns interaction state, and emits declarative effects, while a single `@MainActor` coordinator executes those effects through narrow platform adapters that neither own nor infer workflow state. We chose this separation over direct imperative orchestration in AppKit-facing components so overlapping Accepted Drops, stale completions, cancellation, and terminal feedback remain deterministic and testable through public behavior without coupling tests to AppKit implementation details. This adds an explicit event/effect layer and coordinator boundary, but gives subsequent Vertical Slices one durable seam for extending interaction behavior; GitHub issues [#1](https://github.com/jakeboxer/Dropshot/issues/1) and [#11](https://github.com/jakeboxer/Dropshot/issues/11) record the specification, and `docs/vertical-slices/11-default-conversion-tracer.md` records the first implementation evidence.
