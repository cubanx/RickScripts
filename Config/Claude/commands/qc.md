# /qc Command

## Description

Instructs the assistant to run a quick check on the prospector codebase

## Usage

```
/qc
```

## What it does

When invoked, this command directs the assistant to:

- run these commands in parallel from the root of the given repo we're in, use git to find the root if needed and remember it:
  <!-- - Check to see if firebase emulator is running, if not, run it with this: docker-compose up fb-emulator -d
  - ./scripts/ci/validation.sh --command prettier
  - ./scripts/ci/validation.sh --command lint
  - ./scripts/ci/validation.sh --command typecheck --filter prospector-app
  - ./scripts/ci/validation.sh --command vitest --filter prospector-app -->

  - pnpm -w prettier --check
  - pnpm -w lint
  - pnpm -w --filter=@world50/prospector-app typecheck
  - pnpm -w --filter=@world50/prospector-app test

If prettier fails with anything in .claude, .serena, .opencode, ignore that and report it clean.

## Example

```
/qc
```

After invoking this command, report back any suggested fixes to anything that failed

## Notes

- This command only works for the prospector app
