# M3 Supplement: AI Command Space and State Machine

## Purpose

This supplement defines the AI-facing command space and the state machine for pending AI-generated changes in the TRS-80-inspired AI BASIC appliance.

This document is specifically intended to support **Milestone 3 (M3)**, where the system moves beyond simple `AILOAD` and introduces reviewable AI-assisted program modification.

The goals are:

- preserve user control over source
- avoid opaque in-place rewrites
- keep the command model small and understandable
- avoid premature complexity such as stacked patch queues, partial commits, or interactive patch browsers

---

## Core Decision

AI-generated modifications to the current program are **not applied immediately**.

Instead:

- `AIMERGE` and `AIFIX` create or extend a **single pending change set**
- `AIDIFF` shows the difference between the current program and the pending result
- `AIAPPLY` replaces the current program with the pending result
- `AICANCEL` discards the entire pending result

At this stage, there is only **one pending AI change buffer**.

Multiple `AIMERGE` or `AIFIX` operations do **not** create a stack. They accumulate into a single larger pending result.

This keeps the UX simple.

---

## High-Level Mental Model

The machine has two program views:

### 1. Current Program

The editable, runnable BASIC source currently loaded in memory.

### 2. Pending AI Program

A proposed replacement of the current program produced by one or more AI operations.

The user can:

- inspect the current program with `LIST`
- inspect the delta with `AIDIFF`
- commit the pending program with `AIAPPLY`
- discard it with `AICANCEL`

This is conceptually similar to a working tree plus a staged proposal, but without branching, patch stacks, or partial commits.

---

## Command Space

## Program creation

### `AILOAD "prompt"`

Generate a new program from a prompt.

#### Behavior

- sends prompt and dialect spec to the configured AI backend
- produces a full BASIC source result
- loads the result directly as the current program
- clears any previous pending change set

#### Rationale

`AILOAD` is the equivalent of loading a fresh program into memory. It is a top-level replacement action, not a patch-building operation.

#### Example

```text
AILOAD "Write a small lunar lander game"
```

---

## Program modification

### `AIMERGE "prompt"`

Request a feature addition, rewrite, or modification to the current program or to the already pending program.

#### Behavior

- if no pending change exists:
  - use the current program as the base
  - ask AI to produce a revised full program
  - store that as the pending AI program
- if a pending change already exists:
  - use the pending AI program as the base
  - ask AI to further revise that pending version
  - replace the pending AI program with the newly revised version

#### Important semantic

Repeated `AIMERGE` calls accumulate into a single larger pending proposal.

#### Example

```text
AIMERGE "Add scorekeeping"
AIMERGE "Limit the player to 5 guesses"
AIMERGE "Show the secret number when the player loses"
```

At this point, all three requests are reflected in the single pending AI program.

---

### `AIFIX`

Attempt to repair the current or pending program based on the most recent error or failure context.

#### Behavior

- if no pending change exists:
  - use current program as the base
- if pending change exists:
  - use pending AI program as the base
- include recent error state if available
- ask AI to produce a corrected full program
- store the result as the pending AI program

#### Recommended forms

```text
AIFIX
AIFIX "The loop never terminates"
AIFIX "This should reveal the answer after losing"
```

#### Important semantic

`AIFIX` participates in the same single pending buffer as `AIMERGE`.
It does not create a separate repair branch.

---

## Review and commit

### `AIDIFF`

Show the difference between the current program and the pending AI program.

#### Behavior

- if no pending AI program exists:
  - display a simple message such as `NO PENDING AI CHANGES`
- otherwise:
  - show a human-readable line-oriented diff
  - include added, removed, and changed lines

#### Purpose

This is the main trust-preserving review surface.

#### Example output shape

```text
- 20 N=5
+ 20 N=RND(10)

+ 25 C=0
+ 26 S=0

- 50 GOTO 30
+ 50 C=C+1
+ 55 IF C>=5 THEN PRINT "OUT OF GUESSES": PRINT "ANSWER=";N: END
+ 60 GOTO 30
```

---

### `AIAPPLY`

Commit the entire pending AI program.

#### Behavior

- if no pending AI program exists:
  - display a simple message such as `NO PENDING AI CHANGES`
- otherwise:
  - replace the current program with the pending AI program
  - clear the pending AI buffer
  - return to `READY`

#### Important semantic

`AIAPPLY` applies **all accumulated pending AI changes at once**.

There is no partial apply in M3.

---

### `AICANCEL`

Discard the entire pending AI program.

#### Behavior

- if no pending AI program exists:
  - display a simple message such as `NO PENDING AI CHANGES`
- otherwise:
  - clear the pending AI buffer
  - leave the current program unchanged
  - return to `READY`

#### Important semantic

`AICANCEL` cancels **all accumulated pending AI changes at once**.

There is no selective cancel in M3.

---

## Optional informational commands

These are not strictly required for M3 but fit well.

### `AISTATUS`

Show current AI state.

Suggested output fields:

- active backend: local or remote
- active model
- whether pending AI changes exist
- whether last AI action succeeded or failed

### `AIHELP`

Show AI command summary.

---

## Explicit Non-Goals for M3

Do **not** add these yet:

- multiple pending branches
- patch stack viewer
- per-merge history browser
- partial commit
- partial cancel
- hunk selection
- named AI sessions
- undo/redo of individual AI operations

These all add complexity without being necessary for the core workflow.

---

## State Machine

## States

### `S0: NoProgram`

No current program loaded.

This may exist after startup or after `NEW`.

### `S1: CurrentProgramOnly`

A current program exists.
No pending AI program exists.

### `S2: CurrentPlusPendingAI`

A current program exists.
A pending AI program also exists.

### `S3: ErrorContextAvailable`

This is not a separate top-level state.
It is a flag that may accompany `S1` or `S2` after a failed `RUN`, parse error, or explicit user complaint.

This flag gives `AIFIX` more context.

---

## State transitions

### Boot / startup

- startup -> `S0`

### `AILOAD`

- `S0` -> `S1`
- `S1` -> `S1`
- `S2` -> `S1`

`AILOAD` always replaces the current program and clears any pending AI proposal.

### Manual editing / `LOAD` / `NEW`

#### `NEW`
- `S0` -> `S0`
- `S1` -> `S0`
- `S2` -> `S0`

`NEW` clears both current and pending program state.

#### Manual line edits in `S1`
- remain in `S1`

#### Manual line edits in `S2`
Recommended behavior for M3:
- discard pending AI program
- transition `S2` -> `S1`

Reason:
A pending diff based on an older current program becomes ambiguous once the user edits the base program manually.

#### `LOAD`
- `S0` -> `S1`
- `S1` -> `S1`
- `S2` -> `S1`

`LOAD` replaces the current program and clears pending AI state.

### `AIMERGE`

- `S0` -> error/message: no program to merge into
- `S1` -> `S2`
- `S2` -> `S2`

`AIMERGE` either creates the first pending proposal or compounds the existing one.

### `AIFIX`

- `S0` -> error/message: no program to fix
- `S1` -> `S2`
- `S2` -> `S2`

`AIFIX` creates or updates the single pending proposal.

### `AIDIFF`

- `S0` -> message: no pending AI changes
- `S1` -> message: no pending AI changes
- `S2` -> `S2` with diff output only

### `AIAPPLY`

- `S0` -> message: no pending AI changes
- `S1` -> message: no pending AI changes
- `S2` -> `S1`

The pending AI program becomes the current program.

### `AICANCEL`

- `S0` -> message: no pending AI changes
- `S1` -> message: no pending AI changes
- `S2` -> `S1`

The pending AI program is discarded.

### `RUN`

- `S1` -> `S1`
- `S2` -> `S2`

Recommended rule:
- `RUN` always runs the **current program**, not the pending AI program

Reason:
Pending AI results should not execute until committed.

If the run fails, set the `ErrorContextAvailable` flag.

---

## Recommended Data Model

A minimal internal model for M3:

```text
current_program_text
current_program_ast
pending_ai_program_text   (nullable)
pending_ai_program_ast    (nullable)
last_error_context        (nullable)
last_ai_operation_summary (nullable)
```

### Notes

- the pending AI program should be stored as a full source result, not a patch script
- the diff should be computed from `current_program_text` vs `pending_ai_program_text`
- ASTs may be cached for validation and faster apply/run behavior

---

## Review and Apply Workflow Scenarios

## Scenario 1: feature growth through cumulative merges

Current program loaded.

```text
AIMERGE "Add scorekeeping"
AIMERGE "Limit to 5 guesses"
AIMERGE "Reveal the answer when the player loses"
AIDIFF
AIAPPLY
RUN
```

Interpretation:

- each merge revises the pending AI program
- `AIDIFF` shows the total combined effect
- `AIAPPLY` commits the whole combined result

---

## Scenario 2: fix after failed run

```text
RUN
?SYNTAX ERROR IN 120
AIFIX
AIDIFF
AIAPPLY
RUN
```

Interpretation:

- `AIFIX` uses current source plus recent error context
- the fixed version becomes pending
- user reviews before commit

---

## Scenario 3: merge then fix before apply

```text
AIMERGE "Add player lives"
AIFIX "The game should stop when lives reach zero"
AIDIFF
AIAPPLY
```

Interpretation:

- both operations act on the same pending program flow
- the final diff reflects the cumulative result
- no stack viewer is needed

---

## Scenario 4: user edits while pending changes exist

```text
AIMERGE "Add scorekeeping"
10 PRINT "HELLO"   ← user manually edits current program
```

Recommended result:

- system warns that pending AI changes are being discarded
- pending state is cleared
- machine returns to `S1`

Reason:
This avoids ambiguous rebasing behavior in M3.

---

## UX Messages

Keep messages short and machine-like.

Suggested examples:

- `AI CHANGES PENDING`
- `NO PENDING AI CHANGES`
- `AI CHANGES APPLIED`
- `AI CHANGES CANCELED`
- `PENDING AI CHANGES DISCARDED DUE TO MANUAL EDIT`
- `NO PROGRAM IN MEMORY`
- `AI MERGE FAILED`
- `AI FIX FAILED`

Avoid verbose assistant-style chatter in the command environment.

---

## Acceptance Criteria for M3

M3 is complete when all of the following are true:

1. `AIMERGE` creates a pending AI proposal instead of mutating the current program immediately.
2. repeated `AIMERGE` and `AIFIX` operations accumulate into one pending proposal.
3. `AIDIFF` shows the full current-vs-pending delta.
4. `AIAPPLY` commits the full pending proposal.
5. `AICANCEL` discards the full pending proposal.
6. `RUN` executes only the current committed program.
7. manual edits while pending AI changes exist discard the pending proposal.
8. no stack, patch browser, or partial commit exists in M3.
9. `LOAD` discards both current and pending buffers.
10. `SAVE` does not save pending changes, though does save the current program buffer.
11. Unit tests for each command test basic features of each, at least one fixtured test and one live smoke test exists. If the live smoke test cannot be run because keys cannot be found, print a reasonable message. 

---

## Final Recommendation

For M3, the command family should be:

- `AILOAD`
- `AIMERGE`
- `AIFIX`
- `AIDIFF`
- `AIAPPLY`
- `AICANCEL`
- optionally `AISTATUS` and `AIHELP`

The state model should remain intentionally simple:

- one current program
- one pending AI proposal
- cumulative merge/fix into that pending proposal
- whole-proposal apply or cancel only

This is enough to make the AI workflow understandable, reviewable, and trustworthy without dragging the project into version-control-like complexity too early.
