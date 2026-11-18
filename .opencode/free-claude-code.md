# Free Claude Code packaging notes

Upstream: <https://github.com/Alishahryar1/free-claude-code>

## Release and updater

FCC publishes `free_claude_code-<version>-py3-none-any.whl` on each `v<version>` GitHub release. `scripts/update.sh` reads the first plain `version =`, the first GitHub release `url`, interpolates the new version, and uses `nix store prefetch-file --json` for the new SRI hash. Keep those fields in the current form at the top of `packages/free-claude-code.nix`.

The additional fixed PyPI wheel URLs are intentionally not matched by the GitHub updater. Revisit them if upstream changes required SDK versions or adds imports. `pythonRelaxDeps = true` handles nixpkgs/Python patch-level metadata drift; import checks cover the server composition root, Copilot SDK, and NVIDIA voice integration.

## Nix server lookup patch

Upstream locates `fcc-server` beside `sys.executable`. In a Nix Python application, the interpreter and console scripts do not share that layout. `postPatch` patches the still-zipped wheel's `free_claude_code/cli/launchers/common.py` to fall back to `shutil.which("fcc-server")`.

Do not simplify this to a normal `postPatch` on an extracted directory: `wheelUnpackPhase` has only located the wheel at that point. The patch script also updates the modified file's hash and size in `RECORD`; `wheel unpack` verifies it later. Nix indented strings strip indentation from multiline Python byte strings, which is why the patch uses adjacent byte literals with explicit `\n`.

If this patch fails after an upstream update, inspect the new `server_command()` and adjust the exact byte pattern. The failure is intentional; do not silently skip the patch.

## Launcher architecture

The full package is built once and stays unchanged. The module's core package symlinks only `fcc-server` and `fcc-doctor`. Each enabled agent gets a tiny `runCommand` launcher that:

1. finds the expected command on its runtime `PATH`, or uses an explicit `${source}/bin/<expected-command>` override;
2. prepends the core, enabled optimization packages, and optional source package `bin` directories to a process-local `PATH`;
3. points FCC's canonical agent lookup at a private shim that execs the selected binary;
4. runs supported idempotent RTK/Headroom registration, then execs the full package's absolute `bin/fcc-<agent>` path.

Neither agents nor optimization tools are added to the profile. The core/launcher split also avoids collisions with unselected launchers in the full wheel.

## Current compatibility notes

- FCC requires OpenCode 2. Detection prefers `opencode2`, then tries `opencode`; the canonical-name shim is essential because FCC itself looks up only `opencode`. A v1 `opencode` fallback is rejected before FCC starts.
- Explicit sources remain useful for hermetic launcher behavior. OpenCode sources may contain either `bin/opencode2` or `bin/opencode`; other agents use their canonical binary name.
- Missing automatically detected binaries are runtime errors because the live user's `PATH` is not available as a pure Nix build input. An explicit source missing all expected binaries fails the tiny launcher build instead.
