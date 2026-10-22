# scripts

Runners and helpers: `run_local.sh`, `ec2_run.sh`, Databricks token minting.

| Script | Purpose |
|---|---|
| `databricks_token.sh` | Print a short-lived Databricks token (Secrets Manager M2M, env M2M, or U2M profile) |
| `preflight.sh` | Check that an endpoint answers on the API its agent uses |
| `run_local.sh` | Render `__DATABRICKS_HOST__` in a job YAML and run `harbor run` locally |
| `run_smoke.sh` | Run `tasks/smoke` once per agent and print the rewards |
| `ec2_run.sh` | Run any command on a throwaway, tagged EC2 worker over SSM, then tear it down |
| `ec2_smoke.sh` | `run_smoke.sh` on EC2 with M2M credentials |

All of them load a gitignored `.env.local` at the repo root when it exists.
