# agents

Harbor agent subclasses used by the configs, for example per-trial Databricks token minting.

- `databricks_agents.py` (item 2): `DatabricksClaudeCode`, `DatabricksCodex`, `DatabricksPi`, `DatabricksOpenCode`. Each mints a Databricks token on the Harbor host per trial with `scripts/databricks_token.sh`. See [docs/02-model-serving.md](../docs/02-model-serving.md).
