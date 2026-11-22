# OpenCode + DeepSeek workflow for MacGameBridge

## Setup

1. Install or update OpenCode. DeepSeek's current integration guide recommends OpenCode `v1.18.30` or newer.
2. From the MacGameBridge repository root, run `opencode`.
3. In the OpenCode prompt, run `/connect`, choose the `deepseek` provider, and enter the API key when prompted.
4. Select the Flash model offered by the provider. DeepSeek's current API model ID is `deepseek-flash` (served by the current V4.1 Flash model); `deepseek-v4-pro` is available for more demanding analysis. The provider picker may display a friendlier model label.
5. Do not put API keys in this repository, `AGENTS.md`, prompts, screenshots, or commits. Use OpenCode's provider credential flow.

## Recommended division of work

- **Plan agent:** ask it to inspect the repository and propose a small implementation plan. It should not edit source files.
- **Build agent:** ask it to implement one bounded milestone, preserve public JSON contracts, add tests, and show the diff.
- **Reviewer agent:** use `reviewer` for a read-only pass. The project agent definition denies editing and shell commands.
- **Human verification:** inspect the diff, run the documented build and tests locally, and decide whether to commit. Never let an agent commit or push without your explicit review.

## Suggested implementation prompt

> Read `AGENTS.md`, `docs/ARCHITECTURE.md`, the current milestone document, and the affected Swift files first. Implement only the requested milestone. Preserve the existing CLI behavior and JSON contracts unless the plan explicitly calls for a versioned change. Do not install software, use sudo, alter system settings, delete user data, launch games, modify Wine prefixes or CrossOver bottles, or bypass DRM/anti-cheat. Add deterministic tests using temporary directories. Run the relevant build and test commands only after asking for shell approval. Finish with a summary, changed-file list, exact test results, limitations, and uncommitted diff.

## Suggested review prompt

> Use the `reviewer` subagent to review the current diff. Look for correctness, false-positive runtime detection, macOS path and symlink edge cases, Swift 6 issues, and missing tests. Do not modify files. Report only actionable findings with file and line references.

## Cost and model selection

Use Flash for routine code exploration, small implementation steps, test generation, and documentation. Reserve Pro for architecture trade-offs, difficult compiler failures, security-sensitive review, or reconciling conflicting technical evidence. API use is metered separately from the OpenCode client; check DeepSeek's current pricing before larger sessions.

## Safety settings

A useful project-level OpenCode shell policy is to ask before shell commands, allow read-only Git inspection, and deny pushes:

```jsonc
{
  "$schema": "https://opencode.ai/config.json",
  "permissions": [
    { "action": "shell", "resource": "*", "effect": "ask" },
    { "action": "shell", "resource": "git status *", "effect": "allow" },
    { "action": "shell", "resource": "git diff *", "effect": "allow" },
    { "action": "shell", "resource": "git push *", "effect": "deny" }
  ]
}
```

Review the permissions supported by the installed OpenCode version before applying configuration. The rules above follow the current V2 permission format.
