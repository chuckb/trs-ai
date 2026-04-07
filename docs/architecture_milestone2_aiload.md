# Milestone 2: `AILOAD` and host/guest configuration

This document supplements [Milestone 1 dependencies](./architecture_milestone1_dependencies.md) for **Milestone 2** in the [concept doc](./trs80_ai_basic_appliance_concept.md): `AILOAD` with a remote (OpenAI-compatible) HTTP backend, a **fixture** backend for tests, response parsing/validation, and build-time injection of API secrets.

---

## Guest (appliance image)

- MBASIC is still started with **`/usr/bin/python3`** only—**no venv** in the image ([`mkosi.postinst.chroot`](../appliance/mkosi/mkosi.postinst.chroot)).
- **`/etc/trs-ai/ai.env`** is sourced by [`/usr/local/bin/trs-ai-basic`](../appliance/mkosi/mkosi.postinst.chroot) before launching MBASIC (only if the file is **readable** by the console user). The image sets mode **`0644`** on `ai.env`. **Unprivileged `mkosi` builds** cannot reliably `chown` to `root:basic` in the build namespace (`chown` returns **EINVAL**), so **`0640` `root:root`** would block the autologin user and **`TRS_AI_BACKEND` / `TRS_AI_API_KEY` would never load**—Python would fall back to the **fixture** backend and `AILOAD` would always show `AILOAD_OK`. World-readable mode trades strict ACLs for a working remote config on typical appliance builds.
- **Default (checked in)** env comes from [`appliance/mkosi/build-assets/default-ai.env`](../appliance/mkosi/build-assets/default-ai.env): `TRS_AI_BACKEND=fixture` so **`AILOAD`** returns a fixed tiny program (`AILOAD_OK`) without network or keys.
- **HTTPS** for a real API uses the distro CA bundle; [`mkosi.conf`](../appliance/mkosi/mkosi.conf) includes the **`ca-certificates`** package.

### Networking (DHCP, DNS, and why `AILOAD` used to fail)

Remote **`AILOAD`** needs **DNS resolution** and a **default route** to reach `TRS_AI_BASE_URL`. Several image/build issues showed up as **`Temporary failure in name resolution`** or the **fixture** program even when `ai.env` was correct:

1. **`systemd-resolved` is a separate RPM on Fedora** (`systemd-resolved`). The unit **`systemd-resolved.service`** is not shipped by the base **`systemd`** package alone. Without it, **`systemctl enable`** in finalize fails and **`/etc/resolv.conf`** as managed by resolved does not exist as expected.
2. **`/etc/resolv.conf` in `mkosi.build`:** Do **not** write a static `resolv.conf` into `$DESTDIR` when **`systemd-resolved`** is installed: its `%posttrans` creates a **stub symlink** to `/run/systemd/resolve/stub-resolv.conf`. Merging the build tree then hit **`cp: not writing through dangling symlink … /etc/resolv.conf`** because the workspace symlink had no live target. The package-owned stub is used instead.
3. **No DHCP client stack:** The minimal package set originally had **`iproute`** / **`iputils`** but nothing to bring up Ethernet or learn DNS. The image now includes **`systemd-networkd`** and **`systemd-resolved`**, with [`10-ethernet.network`](../appliance/mkosi/mkosi.postinst.chroot) matching **`Type=ether`** and **`DHCP=ipv4`** (QEMU user/slirp is friendlier to IPv4 DHCP than IPv6).
4. **`systemd-networkd` stayed off after image build:** Fedora’s **`systemctl preset-all`** (during `mkosi` image construction) **disables** `systemd-networkd` by default (NetworkManager-oriented policy). **`[Install]` / `systemctl enable` alone** (including a postinst preset) can be **undone by preset-all** before the tree is finalized. Mitigations that **persist** on the booted root:
   - **[`multi-user.target.d/10-trs-ai-networkd.conf`](../appliance/mkosi/mkosi.postinst.chroot)** — adds **`Wants=systemd-networkd.socket systemd-networkd.service`** so multi-user startup **pulls** networkd even when the unit is still **vendor-preset: disabled**.
   - **[`mkosi.finalize.chroot`](../appliance/mkosi/mkosi.finalize.chroot)** — runs **after** preset-all and uses **`SYSTEMD_OFFLINE=1 systemctl enable`** plus explicit **`*.wants`** symlinks for the socket, service, **systemd-network-generator**, and resolved (correct **`sysinit.target`** linkage for resolved).
   - **[`mkosi.conf`](../appliance/mkosi/mkosi.conf) `[Runtime]`** — **`KernelCommandLineExtra=systemd.wants=systemd-networkd.socket systemd.wants=systemd-networkd.service`** so **`mkosi vm`** also requests those units from the kernel command line (belt-and-suspenders with the drop-in).
5. **Host QEMU networking:** [`run-vm.sh`](../appliance/scripts/run-vm.sh) uses **`mkosi vm --runtime-network=user`** (and **`RuntimeNetwork=user`** is set in `mkosi.conf`). That supplies QEMU **user/slirp** and a **virtio** NIC so the guest can DHCP. Without a NIC or user networking, **`enp0s1`** never gets a route and DNS never works.

**Do not** replace **`/etc/resolv.conf`** in **`mkosi.postinst.chroot`** with **`rm` + symlink**: during the postinst chroot, mkosi often **bind-mounts** the host’s `resolv.conf`, which produces **`Device or resource busy`** on `rm`.

Before MBASIC starts, **`/usr/local/libexec/trs-ai-preflight.sh`** (installed from [`mkosi.postinst.chroot`](../appliance/mkosi/mkosi.postinst.chroot), invoked from `trs-ai-basic`) prints a **short** line when a default IPv4 route exists and, for **`TRS_AI_BACKEND=remote`**, when a **TLS handshake** to the API host from **`TRS_AI_BASE_URL`** succeeds (stdlib only; no API key in the probe).

### Environment variables (guest)

| Variable | Purpose |
|----------|---------|
| `TRS_AI_BACKEND` | `fixture` (default image) or `remote` for HTTP API |
| `TRS_AI_API_KEY` | Required when `remote` |
| `TRS_AI_BASE_URL` | Optional; default OpenAI-compatible chat completions URL |
| `TRS_AI_MODEL` | Optional model name |
| `TRS_AI_TIMEOUT_SEC` | Optional HTTP timeout |
| `TRS_AI_DIALECT_SPEC` | Optional dialect string sent to the backend (default `AIBASIC-0.1`) |

---

## Build-time secrets (host, not in git)

- Put API settings in **[`appliance/secrets/ai.env`](../appliance/secrets/)** (gitignored), **or** set **`TRS_AI_BUILD_AI_ENV`** to the absolute path of a file.
- Run **`./appliance/scripts/build-image.sh`**. The script **copies** that file into [`appliance/mkosi/build-secrets/ai.env`](../appliance/mkosi/build-secrets/README.md) before `mkosi build` so [`mkosi.build`](../appliance/mkosi/mkosi.build) can install it via **BuildSources**. This is required because **mkosi does not reliably forward arbitrary host environment variables** into `mkosi.build`; exporting `TRS_AI_BUILD_AI_ENV` alone can silently leave the image on **default-ai.env** (`TRS_AI_BACKEND=fixture`), which is why `AILOAD` would always load the fixed `AILOAD_OK` program.

If neither `TRS_AI_BUILD_AI_ENV` nor `appliance/secrets/ai.env` is present, the image gets the checked-in **default-ai** (fixture).

Example `ai.env` for remote use (shell `KEY=value` lines):

```bash
TRS_AI_BACKEND=remote
TRS_AI_API_KEY=sk-...
# TRS_AI_BASE_URL=https://api.openai.com/v1/chat/completions
# TRS_AI_MODEL=gpt-4o-mini
```

---

## Host: tests and smoke scripts

- **pytest** for MBASIC (including `tests/regression/ai/`) should run from a **virtual environment** with dev deps—see [README.md](../README.md) **Host Python**. Any venv path is fine; the image does not use it.
- **Optional live HTTP test:** `TRS_AI_RUN_LIVE=1` and `TRS_AI_API_KEY` enable [`test_aiload_remote_live.py`](../mbasic/tests/regression/ai/test_aiload_remote_live.py) (real network).
- **Milestone 2 VM smoke:** after a successful image build,

```bash
./appliance/scripts/smoke-appliance-vm-m2.sh
```

Use **`TRS_AI_PYTHON`** if you want a specific interpreter (e.g. project venv) without changing `PATH`:

```bash
TRS_AI_PYTHON="$HOME/pyenvs/trs-ai/bin/python3" ./appliance/scripts/smoke-appliance-vm-m2.sh
```

Milestone 1 smoke is unchanged: [`smoke-appliance-vm.sh`](../appliance/scripts/smoke-appliance-vm.sh).

---

## MBASIC implementation notes

- AI helpers live under [`mbasic/src/trs_ai/`](../mbasic/src/trs_ai/) (stdlib HTTP + JSON only for the remote backend).
- **`AILOAD "prompt"`** is a normal immediate-mode statement (lexer/parser/interpreter) loading lines into the current program buffer; invalid AI output rolls back the previous program and prints errors.

---

## Quick checklist

- [ ] Image boots to `Ready`; `AILOAD "…"` prints *Contacting AI* / *Program loaded* / `Ready` with default fixture.
- [ ] `LIST` shows numbered lines; `RUN` prints `AILOAD_OK` for the fixture program.
- [ ] `pytest` passes under a venv with `pip install -e ".[dev]"` from `mbasic/`.
- [ ] Optional: image built with `TRS_AI_BUILD_AI_ENV` and remote smoke / `TRS_AI_RUN_LIVE` for real API verification.
- [ ] Optional (remote): console shows preflight **network OK** / **cloud OK** before MBASIC; `AILOAD` reaches the real API (not fixture / not name resolution errors).
