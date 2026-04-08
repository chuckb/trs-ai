# M3 Supplement: AI Command Space and State Machine

## Purpose

This supplement defines the AI-facing command space and the state machine for pending AI-generated changes in the TRS-80-inspired AI BASIC appliance.

This document is specifically intended to support **Milestone 3 (M3)**, where the system moves beyond simple `AILOAD` and introduces reviewable AI-assisted program modification.

The goals are:

- preserve user control over source
- avoid opaque in-place rewrites
- keep the command model small and understandable
- avoid premature complexity such as stacked patch queues, partial commits, or interactive patch browsers
- ensure **syntax failures do not discard the model output**: failed generation stays recoverable via the same pending buffer and `AIFIX`

---

## Core Decision

Most AI-generated modifications to the current program are **not applied immediately** (`AIMERGE` / `AIFIX`).

`AILOAD` is still a **direct load into the current program** when generation **parses successfully**. When `AILOAD` **fails validation** (line format, parser errors, empty result), the implementation must **not** throw away the generated text. Instead:

- store the full failed program text in the **same single pending AI buffer** used by `AIMERGE` / `AIFIX`
- record **last syntax errors** (parser messages, line numbers) in a dedicated buffer for the next AI call
- leave the **current program** unchanged (restore the pre-`AILOAD` snapshot, which may be empty)

The user can then run **`AIFIX`** (optionally with a hint): the backend receives the **pending (broken) program** plus **last syntax errors** and returns a corrected full program into the same pending slot, after which `AIDIFF` / `AIAPPLY` apply as usual.

For the happy path:

- `AIMERGE` and `AIFIX` create or extend the **single pending change set** (validated before replacing pending)
- `AIDIFF` shows the difference between the current program and the pending result
- `AIAPPLY` replaces the current program with the pending result (only if pending is valid; see below)
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

A proposed replacement of the current program produced by one or more AI operations, **or**—after a failed `AILOAD`—the **same buffer** holding the **unparsed / invalid** generated source until the user fixes it (manually, via `AIFIX`, or by canceling).

The user can:

- inspect the current program with `LIST`
- inspect the **full** pending program with `AILIST` (same role as `LIST`, but for the pending buffer—including invalid / unparsed text)
- inspect the delta with `AIDIFF` (including when the pending text does not yet parse: the diff still compares stored text to the current program)
- commit the pending program with `AIAPPLY` once it is **syntactically valid** (if still invalid, the implementation should refuse apply, keep pending, and surface errors—see `AIAPPLY`)
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
- **If the result validates** (every non-empty line is numbered and parses under the interpreter’s rules):
  - replace the **current program** with the result
  - clear any previous pending change set
  - clear **last syntax errors**
- **If validation fails**:
  - **restore** the current program to what it was immediately before this `AILOAD` (may be empty)
  - copy the **raw generated program text** into the **pending AI buffer** (same slot as `AIMERGE` / `AIFIX`)
  - set **last syntax errors** to the parser / line-format messages produced during validation
  - set **error context** so `AIFIX` can use syntax errors without a separate user transcript
  - print the errors and a short message (e.g. that the broken program is pending and `AILIST` / `AIFIX` may help)

#### Rationale

`AILOAD` is the equivalent of loading a fresh program into memory when generation succeeds. On failure, treating the output as **pending** ties syntax recovery to the same review/fix path as `AIMERGE` / `AIFIX` and avoids losing the only copy of the model output; **`AILIST`** makes that pending text easy to inspect without loading it into the runnable program buffer.

#### Example

```text
AILOAD "Write a small lunar lander game"
```

After a failed load from an empty workspace:

```text
?Parse error at line 40
...
?AILOAD FAILED — USE AIFIX TO REPAIR
AILIST
AIFIX
AIDIFF
AIAPPLY
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

- choose the **base source** the same way as `AIMERGE`:
  - if a pending AI buffer exists, use **pending** as the base (including a **failed `AILOAD`** proposal that does not yet parse)
  - otherwise use the **current program** as the base
- build the prompt context for the backend with, at minimum:
  - the base source
  - **last syntax errors** (if any) — full list of parser / line messages from the last failed validation
  - **last runtime / execution error context** (if any), e.g. from a failed `RUN`
  - optional user **hint** string from the command line
- ask AI to produce a **corrected full program**
- **validate** the result; on success, replace the **pending AI program** with the corrected version (same rules as `AIMERGE`). On failure, keep or update messages and leave the user able to retry.

#### Recommended forms

```text
AIFIX
AIFIX "The loop never terminates"
AIFIX "This should reveal the answer after losing"
```

#### Important semantic

`AIFIX` participates in the same single pending buffer as `AIMERGE` and the **failed `AILOAD`** path.
It does not create a separate repair branch.

When the workspace had **no** current program and `AILOAD` failed, **pending** still holds the broken source and **AIFIX** is valid (base = pending); the old “no program in memory” response should **not** apply if pending is non-empty.

---

## Review and commit

### `AILIST`

List the **pending AI program** in **LIST**-like form (line numbers ascending, one line per program line).

#### Behavior

- if no pending AI program exists:
  - display a simple message such as `NO PENDING AI CHANGES`
- otherwise:
  - print each stored pending line in line-number order (the same full line text held in the pending buffer, whether or not it parses)
  - optional **line range**, using the **same conventions as `LIST`** (e.g. `AILIST 100`, `AILIST 100-200`, `AILIST -200`, `AILIST 100-`) when useful for large programs

#### Rationale

After a **failed `AILOAD`**, the user may have an **empty current program** while **pending** holds the only copy of the model output. `AIDIFF` emphasizes deltas; `AILIST` gives a direct, readable dump of the pending source without loading it into the runnable program buffer.

#### Important semantic

`AILIST` is **read-only**. It does not validate pending, mutate the current program, or change state.

---

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
  - **if pending does not validate** (still the same parse rules as load / `RUN` prep): refuse apply, print errors, **keep** pending and **last syntax errors** so the user can edit or `AIFIX` again
  - if pending validates: replace the current program with the pending AI program, clear the pending AI buffer and **last syntax errors**, return to `READY`

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

No current program and **no** pending AI buffer.

This may exist after startup or after `NEW` (or after `AICANCEL` / successful `AIAPPLY` from a state where current was empty—rare).

### `S1: CurrentProgramOnly`

The current program has at least one line.
No pending AI buffer (or pending is empty).

### `S2: PendingAIBuffer`

The pending AI buffer is **non-empty**. The current program may be empty or not.

Examples:

- `AIMERGE` / `AIFIX` produced a pending proposal while current still holds the old program.
- **`AILOAD` failed**: current was restored to its pre-load snapshot (possibly empty), and the generated text lives only in **pending** until fixed or canceled.

### `S3: ErrorContextAvailable`

This is not a separate top-level state.
It is a flag that may accompany `S1` or `S2` after a failed `RUN`, a **failed `AILOAD` / failed merge validation**, or an explicit user complaint.

**Last syntax errors** are set when validation fails (`AILOAD`, `AIMERGE`, `AIFIX` output, or `AIAPPLY`); **last runtime error context** is set when `RUN` fails.

Together these give `AIFIX` enough context to repair both **syntax** and **behavior**.

---

## State transitions

### Boot / startup

- startup -> `S0`

### `AILOAD`

- **Success** (generated source validates):
  - `S0` -> `S1`
  - `S1` -> `S1`
  - `S2` -> `S1`

  Current program becomes the generated result; pending is cleared; **last syntax errors** cleared.

- **Failure** (validation errors):
  - `S0` -> `S2` (current stays empty; **pending** holds failed generation; **last syntax errors** populated)
  - `S1` -> `S2` (current unchanged; **pending** holds failed generation)
  - `S2` -> `S2` (current unchanged; **pending** replaced by the new failed generation and new **last syntax errors**)

`AILOAD` clears a prior pending proposal only on **success**. On failure, the new failed output **becomes** the pending buffer.

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
- transition `S2` -> `S1` if the current program is non-empty, else `S2` -> `S0`

Reason:
A pending diff based on an older current program becomes ambiguous once the user edits the base program manually. The same rule applies when **pending** held only a failed `AILOAD`: discarding it leaves an empty workspace (`S0`).

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

- `S0` -> error/message: nothing to fix (no current and no pending)
- `S1` -> `S2` (pending updated on success)
- `S2` -> `S2` (pending updated on success; typical path after failed `AILOAD`)

`AIFIX` creates or updates the single pending proposal. It must accept **pending-only** (`S2` with empty current) when the pending buffer came from a failed `AILOAD`.

### `AILIST`

- `S0` -> message: no pending AI changes
- `S1` -> message: no pending AI changes
- `S2` -> `S2` (prints pending lines; no state change)

Read-only; same pending / no-pending messages as other review commands.

### `AIDIFF`

- `S0` -> message: no pending AI changes
- `S1` -> message: no pending AI changes
- `S2` -> `S2` with diff output only

### `AIAPPLY`

- `S0` -> message: no pending AI changes
- `S1` -> message: no pending AI changes
- `S2` -> `S1` **only if** pending validates; otherwise remain in `S2` with errors printed and **last syntax errors** updated

The pending AI program becomes the current program when apply succeeds.

### `AICANCEL`

- `S0` -> message: no pending AI changes
- `S1` -> message: no pending AI changes
- `S2` -> `S1` or `S0` (if current program is non-empty after cancel, `S1`; if current was empty, `S0`)

The pending AI program is discarded. **Last syntax errors** may be cleared when canceling the pending buffer (implementation choice; clearing avoids stale `AIFIX` context).

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
pending_ai_program_ast    (nullable)   # optional cache; may be absent if pending is invalid
last_syntax_errors        (nullable)   # structured list or multiline text from last validation failure
last_error_context        (nullable)   # runtime / execution failure context (e.g. after RUN)
last_ai_operation_summary (nullable)
```

### Notes

- the pending AI program should be stored as a **full source** result, not a patch script—even when that source does not yet parse (failed `AILOAD` or failed `AIMERGE` / `AIFIX` attempt)
- the diff should be computed from `current_program_text` vs `pending_ai_program_text` (line-oriented; invalid pending is still text)
- ASTs may be cached for validation and faster apply/run behavior when pending is valid
- **last_syntax_errors** is what the backend uses together with the base source for syntax-oriented `AIFIX`; keep it in sync whenever validation fails

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

## Scenario 2b: fix after failed `AILOAD` (syntax)

Empty or unchanged current program; model returned unusable source.

```text
AILOAD "Write a guess-the-number game"
?Parse error at line 40
...
AILIST
AIFIX
AIDIFF
AIAPPLY
RUN
```

Interpretation:

- `AILIST` shows the full pending source when the user wants a straight listing (not only a diff)
- failed `AILOAD` leaves **pending** = raw broken program and **last syntax errors** = parser output
- `AIFIX` uses **pending** as base and sends errors to the model
- after a successful fix, `AIAPPLY` commits to current (validation passes)

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
- `AILOAD FAILED` (or equivalent) plus a one-line hint that **pending** holds the broken program for `AILIST` / `AIFIX` / `AICANCEL`

Avoid verbose assistant-style chatter in the command environment.

---

## Acceptance Criteria for M3

M3 is complete when all of the following are true:

1. `AIMERGE` creates a pending AI proposal instead of mutating the current program immediately.
2. repeated `AIMERGE` and `AIFIX` operations accumulate into one pending proposal.
3. `AIDIFF` shows the full current-vs-pending delta.
4. `AILIST` lists the full pending program (`LIST`-style), including when pending is invalid; obeys the same no-pending message as other review commands.
5. `AIAPPLY` commits the full pending proposal when validation succeeds.
6. `AICANCEL` discards the full pending proposal.
7. `RUN` executes only the current committed program.
8. manual edits while pending AI changes exist discard the pending proposal.
9. no stack, patch browser, or partial commit exists in M3.
10. `LOAD` discards both current and pending buffers.
11. `SAVE` does not save pending changes, though does save the current program buffer.
12. Failed **`AILOAD`** places the generated text in the **pending** buffer and records **last syntax errors**; **`AIFIX`** works with pending-only state and passes those errors to the backend.
13. **`AIAPPLY`** rejects still-invalid pending with errors and does not clear pending.
14. Unit tests for each command test basic features of each, at least one fixtured test and one live smoke test exists. If the live smoke test cannot be run because keys cannot be found, print a reasonable message. 

---

## Final Recommendation

For M3, the command family should be:

- `AILOAD`
- `AIMERGE`
- `AIFIX`
- `AIDIFF`
- `AILIST`
- `AIAPPLY`
- `AICANCEL`
- optionally `AISTATUS` and `AIHELP`

The state model should remain intentionally simple:

- one current program
- one pending AI proposal (may hold **invalid** source after failed `AILOAD` until repaired or canceled)
- **last syntax errors** paired with validation failures for `AIFIX`
- cumulative merge/fix into that pending proposal
- whole-proposal apply or cancel only

This is enough to make the AI workflow understandable, reviewable, and trustworthy without dragging the project into version-control-like complexity too early.

### Optional implementation note (not required by M3)

An **automatic** parser-feedback retry loop (a few attempts before surfacing failure) can reduce how often users see failed `AILOAD`; even with that, the **pending buffer + last syntax errors** contract remains the fallback when automatic repair is exhausted.
