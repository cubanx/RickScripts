## Why

The Super Push implementation currently lives beside its Codex security broker, which risks duplicated behavior as the broker is reduced to policy wiring. RickScripts should own one reviewable, dependency-free cmdlet while dotfiles retains only the fixed no-argument Codex entry boundary.

## What Changes

- Add exported advanced function `Invoke-SuperPush` for deliberately confirmed, non-force fast-forward pushes of local `HEAD` to `refs/heads/main` in explicitly onboarded `Crisp-Inc/*` repositories.
- Add focused Pester coverage using local repositories and fakes only; no test accesses 1Password, GitHub credentials, GitHub settings, or a real remote.
- Keep all behavior in the exported function so humans can invoke the cmdlet directly and the later dotfiles broker can import the fixed RickScripts manifest and invoke it in a no-profile child without copying implementation.
- Defer dotfiles broker, Codex hook/policy/install wiring, GitHub App provisioning, selected-repository installation, ruleset changes, 1Password changes or access, and every real push to separately authorized follow-up work.

## Capabilities

### New Capabilities

- `super-push-cmdlet`: Canonical, human-invokable Super Push behavior, Codex credential isolation, one-push mutation, cleanup, and sanitized audit evidence.

### Modified Capabilities

None.

## Impact

- Adds `Functions/Invoke-SuperPush.ps1`, a `RickScripts.psd1` export, focused Pester tests, and OpenSpec artifacts.
- Adds no dependency; it uses PowerShell/.NET, `/usr/bin/git`, the existing 1Password CLI, and GitHub REST endpoints at runtime.
- The calling dotfiles task depends on this implementation becoming reviewable before replacing its prototype with the tiny broker and wiring.
