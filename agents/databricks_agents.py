"""Harbor 0.24 agents that call Databricks Model Serving with a per-trial token.

Import with ``import_path: databricks_agents:<Class>``; ``scripts/run_local.sh``
puts this directory on ``PYTHONPATH``.

Each class mints a fresh Databricks token on the Harbor host for every trial
with ``scripts/databricks_token.sh`` (U2M profile or OAuth M2M), refreshing it
after 30 minutes, so jobs can outlive the ~1 h token lifetime. The M2M client
secret never enters the task container; only the short-lived token does.

Set the token key in the job YAML to the placeholder ``minted-per-trial``.
``NPM_CONFIG_REGISTRY`` is copied from the host when set, so agent installs can
use a private npm mirror without hardcoding it in configs.
"""

from __future__ import annotations

import os
import subprocess
import time
from pathlib import Path

from harbor.agents.installed.claude_code import ClaudeCode
from harbor.agents.installed.codex import Codex
from harbor.agents.installed.opencode import OpenCode
from harbor.agents.installed.pi import Pi
from harbor.environments.base import BaseEnvironment

TOKEN_SCRIPT = Path(__file__).resolve().parents[1] / "scripts" / "databricks_token.sh"
REFRESH_AFTER_SEC = 30 * 60
PASSTHROUGH_ENV = ("NPM_CONFIG_REGISTRY",)


class _FreshDatabricksToken:
    """Write a freshly minted Databricks token into ``TOKEN_KEYS`` of the agent env."""

    TOKEN_KEYS: tuple[str, ...] = ()
    # None, not 0: monotonic time starts near zero on a freshly booted worker.
    _minted_at: float | None = None

    def _refresh_token(self) -> None:
        env: dict[str, str] = self._extra_env  # type: ignore[attr-defined]
        for key in PASSTHROUGH_ENV:
            if os.environ.get(key) and key not in env:
                env[key] = os.environ[key]
        if self._minted_at is not None and time.monotonic() - self._minted_at < REFRESH_AFTER_SEC:
            return
        token = subprocess.run(
            [str(TOKEN_SCRIPT)], check=True, capture_output=True, text=True
        ).stdout.strip()
        if self._minted_at is not None and (previous := env.get(self.TOKEN_KEYS[0])):
            # Harbor scrubs the jobs dir with the env it reads *after* the run,
            # which can already hold a newer token. Keep earlier ones under a
            # sensitive key so the token the agent actually used is scrubbed too.
            # The container already had these, so this exposes nothing new.
            n = sum(k.startswith("DATABRICKS_PREVIOUS_TOKEN_") for k in env)
            env[f"DATABRICKS_PREVIOUS_TOKEN_{n}"] = previous
        for key in self.TOKEN_KEYS:
            env[key] = token
        self._minted_at = time.monotonic()

    @property
    def extra_env(self) -> dict[str, str]:
        # Trial reads this for agent setup, the agent run, and the jobs-dir scrub.
        self._refresh_token()
        return dict(self._extra_env)  # type: ignore[attr-defined]


class _SkipUnusedAptNode:
    """Don't install the distro's nodejs/npm when the agent installer won't use them.

    On glibc images the stock Codex and OpenCode installers get Node 22 from nvm,
    and Claude Code downloads a native binary, but Harbor still apt-installs
    nodejs and npm first. On Ubuntu that is hundreds of packages and took 9-18 min
    on EC2. musl images still get them, because nvm's Node can't run there.
    """

    async def _uses_packaged_node(self, environment: BaseEnvironment) -> bool:
        result = await environment.exec(
            command="ldd --version 2>&1 | grep -qi musl || [ -f /etc/alpine-release ]",
            user="root",
        )
        return result.return_code == 0

    async def ensure_system_dependencies(
        self, environment: BaseEnvironment, dependencies: tuple[str, ...]
    ) -> None:
        if {"nodejs", "npm"} & set(dependencies) and not await self._uses_packaged_node(
            environment
        ):
            dependencies = tuple(d for d in dependencies if d not in ("nodejs", "npm"))
        await super().ensure_system_dependencies(environment, dependencies)  # type: ignore[misc]


class DatabricksClaudeCode(_FreshDatabricksToken, _SkipUnusedAptNode, ClaudeCode):
    TOKEN_KEYS = ("ANTHROPIC_AUTH_TOKEN",)

    async def _uses_packaged_node(self, environment: BaseEnvironment) -> bool:
        # The npm-mirror install below runs on the distro's npm.
        return bool(self._extra_env.get("NPM_CONFIG_REGISTRY")) or await super()._uses_packaged_node(
            environment
        )

    async def install(self, environment: BaseEnvironment) -> None:
        # The stock installer downloads the native binary from a CDN, which some
        # networks cut off mid-transfer. With an npm mirror configured, install
        # the npm package through it instead.
        if not self._extra_env.get("NPM_CONFIG_REGISTRY"):
            await super().install(environment)
            return
        if await self._installed_claude_satisfies_version(environment):
            return
        await self.ensure_system_dependencies(
            environment, ("curl", "bash", "nodejs", "npm", "procps")
        )
        version = f"@{self._version}" if self._version else ""
        await self.exec_as_agent(
            environment,
            command=(
                "set -euo pipefail; "
                f'npm install -g --prefix "$HOME/.local" @anthropic-ai/claude-code{version} && '
                "echo 'export PATH=\"$HOME/.local/bin:$PATH\"' >> ~/.bashrc && "
                'export PATH="$HOME/.local/bin:$PATH" && claude --version'
            ),
        )


class DatabricksCodex(_FreshDatabricksToken, _SkipUnusedAptNode, Codex):
    TOKEN_KEYS = ("OPENAI_API_KEY",)


class DatabricksPi(_FreshDatabricksToken, Pi):
    TOKEN_KEYS = ("OPENAI_API_KEY",)


class DatabricksOpenCode(_FreshDatabricksToken, _SkipUnusedAptNode, OpenCode):
    TOKEN_KEYS = ("OPENAI_API_KEY",)
