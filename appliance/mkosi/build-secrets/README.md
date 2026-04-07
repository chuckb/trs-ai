# Build-time AI env (staging)

`build-image.sh` copies `appliance/secrets/ai.env` (or the file named by `TRS_AI_BUILD_AI_ENV`) to **`ai.env` in this directory** immediately before `mkosi build`, so the secret is available under mkosi `BuildSources` as `trs-ai-secrets/`. The file **`ai.env` here is gitignored** and must not be committed.

Mkosi does not reliably forward arbitrary host environment variables into `mkosi.build`, so relying only on `export TRS_AI_BUILD_AI_ENV=...` can silently install the default fixture `default-ai.env` instead.
