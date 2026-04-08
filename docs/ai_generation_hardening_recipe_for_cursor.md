# AI Generation Hardening Recipe

## Purpose

This document defines a **practical, hobby-project-scale recipe** for making AI code generation in the TRS-AI BASIC appliance reasonably reliable without turning the project into a full prompt-engineering or model-training research effort.

The goal is **not** to achieve Cursor-level robustness for arbitrary niche BASIC synthesis.
The goal is to make `AILOAD`, `AIFIX`, and `AIMERGE` behave **reasonably well** for the appliance’s needs by combining:

- stronger generic prompts
- a small host-side validator
- one automatic retry cycle
- explicit user-driven retries via `AIFIX`

This recipe is meant to be implemented directly by Cursor.

---

## Project Constraint Summary

The implementation must respect the following constraints:

- prompts should remain **generic** for MBASIC 5.21 generation/fix/merge
- no elaborate task-specific prompt synthesis from user intent
- it is acceptable to include generally useful language help in prompts, such as:
  - conservative language reference slices
  - BNF / EBNF-style syntax hints
  - high-value keyword lists
  - small canonical examples
- host-side validation is allowed and encouraged
- exactly **one automatic retry cycle** is supported
- `AIFIX` remains available for additional user-driven retries and nudges

---

## Success Criteria

The AI generation system is considered “reasonable” for the appliance if it achieves the following:

1. obvious syntax drift is reduced
2. repeated “fix” attempts do not mindlessly return identical broken code
3. generation degrades toward simpler valid MBASIC rather than ambitious invalid MBASIC
4. host-side validation catches a few obvious classes of junk before acceptance
5. one automatic retry improves success rate without creating complex orchestration
6. failures are honest and controlled instead of looking random or incompetent

---

# Core Strategy

## Recommendation

Implement a **three-layer reliability system**:

### Layer 1: stronger generic prompts (more details are provided later in this document)
Use one generic prompt each for:
- `AILOAD`
- `AIFIX`
- `AIMERGE`

These prompts should explicitly bias toward conservative syntax and simpler valid programs.

### Layer 2: lightweight host-side validator
After AI output is received, run a small validator before accepting it.

### Layer 3: one automatic retry cycle
If the initial result fails validation or parse, run exactly one automatic retry with a more conservative repair instruction.

That is enough for a hobby appliance.

---

# What Not To Build

Do **not** build any of the following at this stage:

- dynamic prompt assembly based on inferred task type
- large prompt-routing framework
- patch-stack repair system
- multi-agent planning architecture
- complex grammar slicing engine
- many-shot example retrieval system
- fine-tuning pipeline
- per-task prompt specialization logic

This recipe is intentionally minimal.

---

# Part 1: Prompt Hardening

## Overall Prompt Design Rules

All three prompts (`AILOAD`, `AIFIX`, `AIMERGE`) should share the following philosophy:

### Shared behavioral directives

- target a **strict parser/runtime**
- optimize for **validity first**
- prefer **simpler valid MBASIC** over ambitious uncertain MBASIC
- do not borrow syntax from nearby BASIC dialects when uncertain
- if unsure, degrade gracefully
- output only one JSON object with the full numbered program

### Shared content aids allowed in prompt

It is acceptable to include these generally helpful language aids in all prompts (exhaustive in all areas has diminishing returns):

- keyword inventory
- statement inventory
- intrinsic function inventory
- type suffix rules
- operator inventory
- a small compact syntax contract for high-risk constructs
- a few tiny canonical examples of valid style

### Important note

The purpose of these aids is **nudging**, not proving correctness.
The host validator and parser still own acceptance.

---

## AILOAD Prompt Guidance

### Objective

Generate a complete MBASIC 5.21 program for the user request.

### Required behavioral emphasis

Add directives equivalent to the following:

- use only syntax you are confident is valid in this implementation
- prefer simple executable code over feature-rich uncertain code
- when uncertain, choose a simpler design that still satisfies the request as much as possible
- avoid syntax borrowed from adjacent BASIC dialects
- use file I/O only if the user explicitly needs persistence or file access
- when file I/O is required, prefer the simplest safe style available

### Strong recommendation

The generator prompt should include a short internal validation checklist such as:

- line numbers ascend
- arrays and variables use consistent names and suffixes
- control flow is balanced
- no uncertain file syntax is used unless necessary
- output is a complete runnable program
- program length reasonableness for features requested

### Minimum useful syntax contract block

Add a compact syntax reminder block for high-value constructs such as:

- numbered lines
- statement lists separated by `:`
- `LET <lvalue> = <expr>`
- `IF <expr> THEN <line-number-or-statement-list> [ELSE ...]`
- `FOR <var> = <expr> TO <expr> [STEP <expr>]`
- `NEXT [<var>]`
- conservative `OPEN` syntax if known

Do not try to include the whole language grammar.

---

## AIFIX Prompt Guidance

### Objective

Repair a full MBASIC program after parser failure, runtime failure, or user complaint.

### Required behavioral emphasis

Add directives equivalent to the following:

- return a complete corrected program
- if an error was reported, the output must be meaningfully different from the input
- if a specific line or construct failed, it must be changed, removed, or replaced
- do not repeat a known-invalid line unchanged
- preserve user intent where possible, but validity comes first
- when uncertain, simplify rather than preserve risky syntax

### Internal validation checklist

Require the fixer to internally check:

- reported failing construct changed
- unchanged output is not acceptable
- variables and suffixes remain consistent
- no previously reported invalid syntax remains

### Important outcome

This prevents the exact failure mode where the model returns the same broken program after being asked to fix it.

---

## AIMERGE Prompt Guidance

### Objective

Take an existing valid or mostly valid MBASIC program and add requested features or changes while returning a complete revised program.

### Required behavioral emphasis

Add directives equivalent to the following:

- return the complete revised program, not a patch
- preserve existing structure where practical
- make only the changes needed to satisfy the requested feature addition
- do not “upgrade” the whole program into riskier syntax
- if the requested enhancement would require uncertain syntax, choose a simpler implementation strategy
- validity is more important than ambitious refactoring

### Recommended merge-specific rule

The merge prompt should explicitly say:

- preserve line numbering style where practical
- keep unrelated code stable
- prefer additive changes over large rewrites

This helps `AIMERGE` feel controlled instead of destructive.

---

# Part 2: Small Prompt Content Improvements

## Generic language help that is worth including

Include a compact shared helper section in all prompts.

Recommended contents:

### 1. Dialect label

- JSON `dialect` field must be `AIBASIC-0.1`

### 2. Output schema

- one JSON object only
- full program only
- each program entry is one numbered line

### 3. Type suffix reminder

- string `$`
- integer `%`
- single `!`
- double `#`

### 4. Variable consistency reminder

- variables and arrays must keep the same names and suffixes everywhere they are used

### 5. Tiny syntax reminders

Examples:

- `10 PRINT "HELLO"`
- `20 IF X = 1 THEN GOTO 100`
- `30 FOR I = 1 TO 10`
- `40 NEXT I`

### 6. Optional conservative file I/O reminders

If your implementation currently only accepts a conservative subset, state it plainly.

Example pattern:

- valid `OPEN` forms in this implementation are limited to the supported modes below
- when uncertain, avoid advanced record-oriented file syntax

This can remain generic if phrased carefully.

---

## What not to include excessively

Avoid overloading the prompt with:

- very large prose language manuals
- giant raw BNF dumps
- many historical notes about Microsoft BASIC lineage
- huge examples that drown the actual user request

The goal is nudge + behavior constraints, not encyclopedic prompt stuffing.

---

# Part 3: Host-Side Validator

## Objective

Catch a few cheap classes of obviously bad output before accepting it.

This validator should be intentionally small and practical.

## Required validation stages

### Stage 1: JSON/schema validation

Reject if:

- response is not valid JSON
- `dialect` field is missing or wrong
- `program` field is missing or not a list of strings
- any program entry does not begin with a line number

### Stage 2: line structure validation

Reject if:

- line numbers are duplicated
- line numbers are not parseable
- program is empty

### Stage 3: parser validation

Reject if:

- the program does not parse

### Stage 4: lightweight semantic lint checks

Add a few cheap checks such as:

- obvious variable suffix mismatch
- obvious array name mismatch
- unsupported or forbidden syntax strings if known
- fix output identical to prior input
- failing line unchanged after fix

## Important note

These lint checks should remain modest.
This is not a full semantic analyzer.

---

## Recommended initial lint rules

Implement these first:

### Rule 1: identical fix rejection

If `AIFIX` returns program text identical to the input program, reject it immediately.

### Rule 2: failing line unchanged rejection

If parser reported a specific failing line and the fixer returned the same line content unchanged, reject it.

### Rule 3: obvious suffix mismatch

If a variable or array is declared with one suffix and later assigned or referenced under the same base name with another incompatible suffix, flag it.

### Rule 4: forbidden syntax token rejection

If there are specific constructs you know your implementation does not accept, reject outputs containing them.

This can be a simple string or regex blacklist if needed.

---

# Part 4: One Automatic Retry Cycle

## Objective

When the first generation or fix attempt fails, perform exactly one automatic retry using a more conservative instruction.

This improves reliability without adding a complex orchestration system.

## Required policy

There is exactly one automatic retry.
No more.

After that, control returns to the user. When performing the retry, print a concise message to the console in the form and format of existing messeges, telling the user about the retry.

---

## Retry behavior for AILOAD

### Flow

1. generate program using generic `AILOAD` prompt
2. run validator and parser
3. if accepted, load it
4. if rejected, run one automatic retry
5. the retry prompt should say, in effect:
   - produce a simpler, more conservative version
   - prioritize parser-safe MBASIC syntax
   - avoid advanced or uncertain constructs
   - preserve the main user-visible behavior
6. validate and parse again
7. if accepted, load it
8. if rejected, fail honestly and keep the failure message visible

### Purpose

This gives the model one chance to back off from risky syntax.

---

## Retry behavior for AIFIX

### Flow

1. run generic `AIFIX`
2. validate
3. if accepted, use as pending/fixed output
4. if rejected, run one automatic retry
5. retry prompt should say, in effect:
   - the previous fix attempt failed
   - the corrected program must differ from input
   - the failing line or construct must change
   - simplify aggressively if needed
6. validate again
7. if still rejected, fail honestly

### Purpose

This stops the model from mindlessly returning the same broken code forever.

---

## Retry behavior for AIMERGE

### Flow

1. run generic `AIMERGE`
2. validate
3. if accepted, produce pending merged program
4. if rejected, run one automatic retry
5. retry prompt should say, in effect:
   - preserve more of the original program
   - make only minimal additive changes
   - choose simpler syntax if uncertain
6. validate again
7. if still rejected, fail honestly

### Purpose

This makes merge behavior less destructive and more conservative on retry.

---

# Part 5: User-Driven Retry via AIFIX

## Objective

After the automatic retry is exhausted, the user should still be able to steer the repair process manually.

## Policy

`AIFIX` remains the user’s manual override for extra recovery attempts.

The user can provide:

- specific parser messages
- specific complaints about behavior
- additional steering hints

Examples:

- `AIFIX "fix the syntax errors"`
- `AIFIX "do not use advanced file handling; keep it simple"`
- `AIFIX "the loop logic is wrong"`

### Important note

This manual retry capability should not add hidden complexity to the automatic pipeline.
It is simply another user-initiated pass through the same fixed infrastructure.

---

# Part 6: Recommended Host Pipeline

## AILOAD pipeline

### Implement exactly this

1. Build request using generic `AILOAD` prompt.
2. Send to model.
3. Validate JSON/schema.
4. Validate line structure.
5. Parse.
6. Run lightweight lint checks.
7. If all pass, accept.
8. If any fail, run one conservative retry.
9. Re-run validation and parse.
10. If still failing, return clear failure message.

## AIFIX pipeline

1. Build request using generic `AIFIX` prompt plus:
   - full current program
   - parser/runtime error context
   - optional user hint
2. Send to model.
3. Validate JSON/schema.
4. Reject if identical to input.
5. Reject if known failing line is unchanged.
6. Parse.
7. Run lightweight lint checks.
8. If all pass, accept.
9. If any fail, run one conservative retry.
10. Re-run validation and parse.
11. If still failing, return clear failure message.

## AIMERGE pipeline

1. Build request using generic `AIMERGE` prompt plus:
   - full current/pending program
   - merge request text
2. Send to model.
3. Validate JSON/schema.
4. Parse.
5. Run lightweight lint checks.
6. If accepted, store as pending merged program.
7. If rejected, run one conservative retry.
8. Re-validate.
9. If still failing, return clear failure message.

---

# Part 7: Failure Messaging

## Objective

Failures should look controlled and understandable, not random or Pythonic.

## Recommended messages

Examples:

- `AI GENERATION FAILED`
- `AI FIX FAILED`
- `AI MERGE FAILED`
- `AI FIX RETURNED NO CHANGES`
- `AI FIX DID NOT CHANGE FAILING LINE`
- `AI OUTPUT FAILED VALIDATION`
- `AI OUTPUT FAILED PARSE`

### Important tone rule

Messages should be terse and machine-like, consistent with the appliance UX.

---

# Part 8: Implementation Priorities for Cursor

## Priority 1

Replace the existing `AILOAD`, `AIFIX`, and `AIMERGE` prompts with stronger generic prompts that:

- bias toward conservative syntax
- forbid adjacent-dialect guessing
- require complete program output
- emphasize validity over cleverness

## Priority 2

Add a small shared validator module that performs:

- JSON/schema validation
- line-number validation
- parser invocation
- a few cheap lint checks

## Priority 3

Add one automatic retry path for all three operations.

## Priority 4

Add rejection logic for:

- identical fix output
- unchanged failing line after fix

## Priority 5

Standardize machine-style failure messages.

---

# Cursor Execution Notes

Cursor should implement this as a focused reliability pass, not a redesign.

### Required boundaries

- do not build a large new framework
- do not over-abstract prompt construction
- do not add task-type inference
- do not add multiple automatic retries
- do not add a complex semantic analyzer

### Desired outcome

The code should remain easy to understand and should materially improve generation behavior with modest implementation effort.

---

# Acceptance Criteria

This work is complete when all of the following are true:

1. `AILOAD`, `AIFIX`, and `AIMERGE` each use stronger generic prompts.
2. AI outputs are schema-validated before use.
3. Parsed program validity is required before acceptance.
4. A small host-side validator catches at least a few obvious junk cases.
5. `AIFIX` output identical to input is rejected.
6. `AIFIX` output that leaves the known failing line unchanged is rejected.
7. One automatic retry exists for each of `AILOAD`, `AIFIX`, and `AIMERGE`.
8. Retry behavior is conservative, not complex.
9. Failures surface clearly and honestly to the user.
10. The system behaves reasonably better without turning into a large prompt-engineering project.

---

# Final Recommendation Summary

To make AI generation reasonable for this project:

- strengthen the three generic prompts
- keep them generic, conservative, and validity-first
- include small helpful language nudges, not giant manuals
- add a tiny validator and parser gate
- reject identical or unchanged bad fixes
- perform one automatic conservative retry
- let `AIFIX` remain the user’s manual extra-retry path

This is the smallest recipe that is likely to move the system from embarrassing to acceptable for a hobby appliance.
