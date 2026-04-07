# TRS-80-Inspired AI BASIC Appliance

## Purpose

Build a bootable, appliance-like computer environment that feels like a vintage TRS-80-class BASIC machine, but adds a first-class AI loading experience.

The core idea is:

- the user interacts with a BASIC-first machine, not a Linux shell
- programs are editable, listable, savable BASIC source
- instead of loading code from cassette, the machine can generate code through AI
- AI is a source generator and editor assistant, not an opaque execution engine

The signature command is:

```text
AILOAD "write me a lunar lander game"
```

The machine contacts an AI backend, receives BASIC source, loads it into the current program buffer, and leaves the user in control to `LIST`, edit, and `RUN`.

---

## Product Positioning

This is **not**:

- a Linux shell with retro colors
- a generic AI terminal dressed up as BASIC
- a perfect TRS-80 emulator
- an opaque “agent” that writes and runs arbitrary host code

This **is**:

- a BASIC-first machine that happens to run on Linux for expediency
- a retro-styled computer appliance with a constrained programming model
- a human-readable, editable source environment
- a platform where AI augments the traditional `LOAD` workflow

Target user experience:

1. Boot the image in QEMU.
2. Land directly in the BASIC environment.
3. Type BASIC lines, `RUN`, `LIST`, `SAVE`, etc.
4. Use `AILOAD` to generate programs.
5. Optionally use local or remote models.

---

## Design Principles

### 1. BASIC first

The machine must be useful even with AI disabled.

### 2. AI generates source, not arbitrary behavior

AI returns BASIC source in the machine’s dialect. The user can inspect, edit, save, diff, and run it.

### 3. The host OS stays hidden

Linux is an implementation detail. The appliance should boot directly to the BASIC screen.

### 4. Constrain the language for reliability

A small, regular dialect improves both interpreter simplicity and AI output quality.

### 5. Local AI is a feature, not a requirement

The appliance should support local models, but should not depend on bundling huge model weights in the first version.

### 6. Packaging should favor appliance feel over theoretical purity

A frozen Python app inside a minimal Linux image is acceptable for v1.

---

## Recommended Technical Direction

## Host Platform

### Recommendation

Use Linux under QEMU for the first implementation.

### Why

- fastest path to a bootable appliance
- easy networking for remote AI
- easy local service management for a local model backend
- avoids bare-metal detours

### Non-goal for v1

- custom kernel
- bare-metal runtime
- exact hardware emulation

---

## Interpreter Base

### Recommendation

Use **MBASIC** as the initial base, via fork and extension.

### Why MBASIC won over bwBASIC

MBASIC is a modern Python implementation with:

- a full REPL command model
- explicit interactive command handling
- modular structure for lexer, parser, runtime, interpreter, and UI backends
- direct command methods such as `NEW`, `SAVE`, `LOAD`, and `LIST`
- both line-oriented CLI and curses-based full-screen UI options

This makes it the better fit for adding new direct commands like `AILOAD`, `AIMERGE`, and `AIFIX`.

### Why not bwBASIC for v1

bwBASIC is attractive for its vintage feel and C implementation, but it appears more monolithic and older in structure. Extending it to integrate AI cleanly would likely mean more invasive command-dispatch work, more awkward networking or helper-process glue, and less pleasant iteration.

### Practical conclusion

Fork MBASIC and treat it as an implementation substrate, not as an immutable product.

---

## Language Strategy

## Recommendation

Do **not** aim for exact TRS-80 BASIC compatibility in v1.

Instead, define a **TRS-80-inspired appliance dialect** that preserves the feel while staying small and reliable.

### Required characteristics

- line-numbered program model
- immediate mode + stored program mode
- classic direct commands
- small statement vocabulary
- predictable syntax for AI generation

### Suggested minimum statement set

- `PRINT`
- `INPUT`
- `LET`
- `IF ... THEN`
- `GOTO`
- `GOSUB`
- `RETURN`
- `FOR`
- `NEXT`
- `END`
- `REM`

### Good optional additions

- `CLS`
- `RND`
- `INKEY$`
- `LOCATE`
- `BEEP`
- tiny drawing or semigraphics commands later

### Important constraint

The AI contract must target the exact supported dialect and reject or sanitize unsupported syntax.

---

## Core User-Facing Commands

## Traditional machine commands

- `NEW`
- `LIST`
- `RUN`
- `SAVE "name"`
- `LOAD "name"`
- `FILES`
- `DEL "name"`
- `REN "old","new"`

## AI commands

### Required

- `AILOAD "prompt"`
- `AIMERGE "prompt"`
- `AIFIX`
- `AIEXPLAIN [line]`
- `AIDIFF`

### Model/backend commands

- `AIMODEL`
- `AIMODEL LIST`
- `AIMODEL PULL <model>`
- `AIMODEL USE <model>`
- `AIMODEL LOCAL`
- `AIMODEL REMOTE`
- `AISTATUS`

### Example session

```text
READY
AILOAD "Write a small number guessing game"
CONTACTING AI...
PROGRAM LOADED.
READY
LIST
RUN
```

---

## AI Behavior Contract

## Recommendation

AI should return **source only**, not shell commands, not commentary, not markdown.

### Preferred response format

Best:

```json
{
  "dialect": "AIBASIC-0.1",
  "program": [
    "10 PRINT \"HELLO\"",
    "20 END"
  ]
}
```

Acceptable fallback:

plain numbered BASIC lines.

### Rules for the backend prompt

The backend prompt must enforce:

- output only BASIC source or the structured payload
- every program line begins with a line number
- only supported statements and functions may be used
- no markdown fences
- no prose unless explicitly requested
- target a small program size by default

### Load behavior

`AILOAD` should:

1. send the user prompt plus dialect spec
2. receive the generated source
3. validate and sanitize it
4. load it into the current program buffer
5. not auto-run by default
6. return control to the user at `READY`

---

## Architecture Recommendation

## High-level components

### 1. Screen/UI layer

Responsible for:

- full-screen terminal presentation or line REPL
- prompt handling
- status messages
- optional split output/editor view later

### 2. Program editor/store

Responsible for:

- accepting numbered lines
- replacing/deleting lines
- listing sorted program text
- saving/loading files

### 3. Parser/interpreter

Responsible for:

- tokenization/parsing
- runtime execution
- variables, loops, stack, input/output

### 4. AI subsystem

Responsible for:

- prompt assembly
- backend selection
- request/response normalization
- validation of returned code
- diff/merge/fix operations

### 5. Backend abstraction

Create a small provider interface such as:

- `generate_program(prompt, dialect_spec)`
- `merge_program(existing_source, prompt)`
- `fix_program(existing_source, error_context)`
- `explain_program(existing_source, line)`
- `list_models()`
- `set_model(name)`

### 6. Storage/config

Responsible for:

- persistent BASIC programs
- AI provider settings
- selected local model
- optional user defaults

---

## AI Backend Strategy

## Recommendation

Implement a backend abstraction from the start.

### Initial backends

#### Remote backend

Use a hosted LLM API first because it is the fastest path to good generation quality.

#### Local backend

Support local models through **Ollama** first.

### Why Ollama first

- easy Linux installation and service model
- straightforward model pull/use workflow
- HTTP API that is easy to call from the appliance
- fits the appliance idea well

### Why not make local mandatory in v1

Bundling large model weights inflates the image and immediately creates hardware expectations around RAM, storage, and latency.

### Best v1 local strategy

Ship:

- the appliance
- the local AI runtime (optional but recommended)
- no large model weights by default

Then allow first-boot or in-machine installation via `AIMODEL PULL`.

### Future backend

Later, consider `llama.cpp` as a tighter lower-level runtime if reducing stack complexity becomes more important than convenience.

---

## Packaging and Appliance Strategy

## Recommendation

Treat this as a **bootable Linux appliance image** that launches directly into the BASIC machine.

### Packaging stack for v1

- Python application (forked MBASIC + appliance features)
- frozen/package-distributed via **Nuitka standalone** or **PyInstaller**
- copied into a small Linux image
- auto-launched on tty1 or by init/systemd

### Why this is acceptable

Although Python is not ideal for ultra-small systems, it is acceptable for a QEMU-first appliance if the user never sees Python directly.

### Recommended packaging preference

1. **Nuitka standalone** as primary recommendation
2. **PyInstaller** as acceptable fallback

### Do not do for v1

- ship as source + virtualenv + pip workflow
- require user-visible Python setup
- aim for bare-metal or static-micro-image purity immediately

### Boot behavior recommendation

- boot directly into the BASIC screen
- optional hidden escape hatch to a shell for maintenance/development
- no normal Linux login prompt in the default experience

---

## UX Recommendation for Local AI Setup

## Do not use a bootloader command for model management

Model management belongs in the appliance environment, not in GRUB or another bootloader.

### Better options

#### First-boot wizard

Example:

```text
TRS-AI BASIC SYSTEM 0.1

NO LOCAL AI MODEL INSTALLED.

1. USE REMOTE AI
2. INSTALL RECOMMENDED LOCAL MODEL
3. ADVANCED MODEL SETUP
4. CONTINUE WITHOUT AI
```

#### Or in-machine commands

`AIMODEL` should be the main control surface.

This keeps the appliance coherent and understandable.

---

## Safety and Trust Boundaries

## Required safety model

AI must not directly execute arbitrary host commands.

### Required rules

- AI outputs BASIC source, not shell code
- any host integration must be explicit and opt-in
- no hidden execution of arbitrary generated commands
- file access should remain scoped to the appliance workspace in v1

### Host escape hatch

If a developer mode exists, it should be explicit and clearly separate from the normal user experience.

---

## Recommended Milestones

## Milestone 1: BASIC appliance shell

Deliverable:

- bootable Linux image in QEMU
- direct launch into BASIC environment
- `NEW`, `LIST`, `RUN`, `SAVE`, `LOAD`
- local file persistence

Acceptance:

- boots to `READY`
- can enter lines, list, run, and save a small program

## Milestone 2: `AILOAD` with remote backend

Deliverable:

- backend abstraction
- remote provider
- `AILOAD` command
- structured prompt/response contract
- validation and loading into current buffer

Acceptance:

- `AILOAD` loads inspectable BASIC source into memory
- user can `LIST` and `RUN` it
- syntax failures are surfaced cleanly

## Milestone 3: editing AI commands

Deliverable:

- `AIMERGE`
- `AIFIX`
- `AIEXPLAIN`
- `AIDIFF`

Acceptance:

- user can request modifications to current source without losing control
- changes are visible and reviewable before run

## Milestone 4: appliance polish

Deliverable:

- retro screen treatment
- startup banner
- optional full-screen editor mode
- better file browser / `FILES`

Acceptance:

- environment feels like a dedicated machine, not a Python app

## Milestone 5: local model support

Deliverable:

- Ollama integration
- `AIMODEL` commands
- local/remote selection
- first-boot model guidance

Acceptance:

- local model can be selected and used for `AILOAD`
- remote remains available as fallback

## Milestone 6: advanced machine features

Optional:

- semigraphics or PETSCII-style display features
- simple sound hooks
- small bundled demos
- optional custom dialect features optimized for AI generation

---

## Cursor Planning Guidance

When using Cursor planning, keep the work split by subsystem and force visible progress.

### Good planning style

- one milestone per visible behavior
- minimal naming churn
- acceptance criteria tied to user-observable outcomes
- do not hide core behavior behind over-abstraction too early

### Preferred implementation sequence

1. get the machine booting into BASIC
2. prove direct command extension with `AILOAD`
3. add backend abstraction only as needed to support remote/local providers cleanly
4. add appliance polish after core behaviors work

### Avoid

- prematurely re-architecting into many speculative subsystems
- exact TRS-80 compatibility before the appliance works
- local-model complexity before remote `AILOAD` is proven
- bootloader-level AI control features

---

## Final Recommendation Summary

The concept we landed on is:

- a **TRS-80-inspired AI BASIC appliance**
- implemented first as a **bootable Linux/QEMU image**
- built on a **fork of MBASIC**
- packaged as a **frozen Python application** in a minimal distro image
- centered on `AILOAD` as the modern equivalent of cassette loading
- extended later with `AIMERGE`, `AIFIX`, `AIDIFF`, and `AIEXPLAIN`
- able to use **remote AI first**, with **local Ollama-backed AI** as an appliance feature
- designed so that AI always returns **editable BASIC source**, never opaque behavior

This gives the project a coherent identity, a practical implementation path, and a clear separation between retro-computing charm and modern AI functionality.
