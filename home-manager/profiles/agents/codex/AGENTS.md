# Global Instructions

## Nix environment

This machine is managed with Nix. Prefer `nix run` and `nix shell` to obtain
tools and dependencies instead of installing them with system package
managers or other non-Nix means.

## Python dependencies

Use `uv` to manage Python dependencies (`uv add`, `uv sync`, `uv run`). Do not
use `pip install` or create virtual environments manually.

## Commit discipline

Use concise commit titles with a short scope followed by a Chinese description,
for example `home-manager: 加入 rust 相关工具` or `refactor: 重构配置模块`.
Mention affected components when relevant. Follow an explicit repository commit
convention when one is defined.

For nontrivial changes, add a Chinese commit body separated from the title by a
blank line. Explain the problem or motivation, the resulting behavior, and
relevant validation. Use unindented bullet points when helpful. Describe the
final change rather than listing intermediate attempts. A title alone is enough
for a simple, self-explanatory change.

Commit coherent steps early while working. For larger work, start a development
branch with `git switch -c <branch-name>` and make focused commits there.

Once the requested task or logical theme is fully implemented and the required
checks pass, finish by integrating it into the local `main` branch. Squash the
theme's intermediate implementation, test, documentation, and corrective commits
into one coherent commit, rebase onto `main`, then fast-forward `main` to include
it and leave the working checkout on `main`. Write the final commit message to
describe the complete result. Group commits by logical purpose, not merely by
which files they touch; keep independent themes in separate commits.

Local integration is part of completing the task and is already authorized; do
not stop after committing on a development branch or ask for separate merge
confirmation. If the theme is incomplete or checks fail, continue working. If
integration is blocked, report the concrete blocker and remaining work. Follow
an explicit user instruction or repository workflow that requires a different
target branch or PR review. Push only when requested.

Keep task branches after local integration. When asked to push, push `main`
first. After the push succeeds, delete the relevant task branches fully merged
into `main` using `git branch -d`. Preserve unrelated branches. If deletion is
refused, keep the branch and report it; do not automatically use `-D`.
