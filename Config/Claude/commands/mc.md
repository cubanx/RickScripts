---
allowed-tools: Bash(~/.claude/memory-castle/mc*)
description: Memory Castle operations - auto-store last result or manual commands
argument-hint: [optional: command] [args...]
---

Memory Castle operations.

**Default (no args)**: Auto-store last result or current todo context
**With args**: Execute specific Memory Castle commands

Commands:
- **store "key" "value"** - Store memory with key-value pair
- **get "key"** - Retrieve memory by key  
- **status** - Show current project/worktree status
- **decision "title" "desc" "context" "rationale"** - Store decision
- **track "task-id" "name" --status "pending"** - Track progress

Usage examples:
- `/mc` - Auto-store last result/todo with generated key
- `/mc store "project-status" "working on memory castle integration"`
- `/mc get "project-status"`
- `/mc status`
- `/mc decision "use-typescript" "Use TS for new components" "React project" "Better type safety"`
- `/mc track "task-001" "implement login" --status "pending"`

When no arguments provided, will auto-detect and store:
- Last bash command result
- Current todo status  
- Recent file changes
- Current working context

With arguments, will execute: `~/.claude/memory-castle/mc $ARGUMENTS`