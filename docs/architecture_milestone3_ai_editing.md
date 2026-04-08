# Milestone 3: AI editing commands and pending buffer

This document supplements the [appliance concept](./trs80_ai_basic_appliance_concept.md) and the [M3 command-space supplement](./m3_ai_command_space_and_state_machine_supplement.md) for **Milestone 3** in-tree behavior.

## Summary

- **`AIMERGE`** and **`AIFIX`** call the AI backend and store the validated result in a **single pending program buffer**; they do not replace the runnable program until **`AIAPPLY`**.
- **`AIDIFF`** prints a line-oriented delta (by BASIC line number) between the **current** program and **pending**.
- **`AIAPPLY`** copies pending lines into the current program and clears pending; **`AICANCEL`** clears pending only.
- **`AILOAD`**, **`LOAD`**, and **`NEW`** clear pending (and `NEW` clears error context used by `AIFIX`). **`RUN`** always executes the **current** program, not pending.
- **Manual program changes** (numbered lines, `MERGE`, `DELETE`, `RENUM`, `EDIT` save, `AUTO` line entry) **discard** pending with the message `PENDING AI CHANGES DISCARDED DUE TO MANUAL EDIT`.
- **`AIEXPLAIN`** requests prose from the backend (does not alter the program). **`AISTATUS`** / **`AIHELP`** are informational.

## MBASIC implementation

- State: `InteractiveMode` holds `ai_pending_lines`, `ai_last_error_context` (set on `RUN` failure), and `ai_last_operation_summary`.
- Backends: [`mbasic/src/trs_ai/backends.py`](../mbasic/src/trs_ai/backends.py) — `merge_program`, `fix_program`, `explain_program` on the same env-selected backend as `generate` (`fixture` / `remote`).
- Diff helper: [`mbasic/src/trs_ai/program_diff.py`](../mbasic/src/trs_ai/program_diff.py).
- Tests: [`mbasic/tests/regression/ai/test_m3_ai_commands.py`](../mbasic/tests/regression/ai/test_m3_ai_commands.py).

## Guest (appliance)

Same as [Milestone 2](./architecture_milestone2_aiload.md): `/etc/trs-ai/ai.env`, `TRS_AI_BACKEND=fixture` by default; no venv on the guest.

## Host: tests and smoke

```bash
source ~/pyenvs/trs-ai/bin/activate   # or your venv
cd mbasic && python -m pytest tests/regression/ai/ -v
```

VM smoke (after `build-image.sh`):

```bash
./appliance/scripts/smoke-appliance-vm-m3.sh
```

The script uses **strict user prompts** for `AILOAD` / `AIMERGE` (no nested `"` in the typed BASIC string) so the model is steered toward a two-line `PRINT`/`END` program with token `M3_SMOKE_OK` and **no INPUT**—without changing global backend system prompts. After `RUN` it **does not require another `Ready` line**: the CLI often returns to `input()` without printing a second prompt (consistent with line-oriented BASIC behavior in the upstream docs, which use `Ok` in examples rather than mandating a prompt after every successful `RUN`). The harness waits for `M3_SMOKE_OK`, then briefly drains optional INPUT or `Ready`. For maximum reliability in CI, use **`TRS_AI_BACKEND=fixture`** on the guest.

Optional: `TRS_AI_PYTHON` points at the same venv’s `python3` if `PATH` is not enough.

## Quick checklist

- [ ] `AIMERGE` / `AIFIX` → `AI CHANGES PENDING`; `AIDIFF` shows `+`/`-` lines; `AIAPPLY` / `AICANCEL` behave as specified.
- [ ] `pytest` passes under a venv for `tests/regression/ai/`.
- [ ] Optional: `smoke-appliance-vm-m3.sh` against a built image with fixture backend.
