# Agent instructions

This is a **public** repository. Read all of this before changing anything.

## Scope
- One item per branch (`item-<n>-<slug>`). Change only your item's files: its `configs/` directory, its `docs/0<n>-*.md` page, and any new files it needs.
- Shared files (`agents/`, `scripts/`, `tasks/smoke/`, `pyproject.toml`, `README.md`) may be changed, but keep those changes small and list them in the PR description, because other item branches change them too.
- Do not merge or push to `main`. Open a PR from your branch.

## Secrets and private details: never commit
- Tokens, client secrets, private keys, `.databrickscfg`, `connections.toml`.
- Workspace hostnames, AWS account IDs, ARNs, bucket names, Secrets Manager IDs, service-principal IDs, internal URLs. Read them from environment variables or arguments, and use placeholders such as `https://<workspace>.cloud.databricks.com` in docs.
- Private package mirrors and proxies (npm, PyPI, container registries, any corporate proxy): never write their URLs or hostnames in committed files, comments, docs, PR descriptions or commit messages, and don't name whose mirror it is. Put them in `.env.local` (gitignored; template in `.env.example`) and read them from the environment, for example `NPM_CONFIG_REGISTRY`, `UV_INDEX_URL`, `PIP_INDEX_URL`. In docs, write "set `NPM_CONFIG_REGISTRY` if your network needs a mirror".
- Lockfiles record the index they were resolved against, so `uv.lock` stays uncommitted unless it was generated against public PyPI.
- Job output (`jobs/`) is gitignored. Before quoting logs in docs, check them for any of the above.
- Tokens must be minted on the Harbor host and passed per trial. Never put a long-lived secret inside a task container.

## Databricks
- Run `databricks auth profiles` and ask the user which profile to use before the first Databricks call.
- Always pass `--profile` to the Databricks CLI.

## Tooling
- Python only through `uv`: `uv sync`, `uv run ...`, `uv add ...`. Never run `python`/`pip` directly.
- Shell scripts: `set -euo pipefail`, and keep them runnable on macOS (BSD tools) and Amazon Linux.
- Entry-point scripts load local settings first: `[[ -f "$repo/.env.local" ]] && { set -a; . "$repo/.env.local"; set +a; }`, where `$repo` is the repo root. They must still work without the file, because EC2 workers and other users won't have it.

## Shared machine
Several sessions run in parallel on one laptop and one AWS account.
- Use a unique `--jobs-dir` and job name per session, so job outputs and Docker image/container names don't collide.
- Don't prune Docker images, stop Colima, or delete EC2 instances or buckets that your session didn't create.
- Tag any AWS resource you create with `Project=harbor-databricks-integration` and `Item=<n>`, and tear it down when finished.

## Git
- Identity in this repo: `tfayyaz` / `tahirfayyaz@gmail.com` (set per clone).
- Commit in small, working steps with clear messages.

## Done means
A doc page that shows the exact commands for local and EC2 runs, and the results table from runs you actually did. Report failures as failures.
