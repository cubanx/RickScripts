---
allowed-tools: Bash(~/.claude/memory-castle/mc*), Bash(printf*), Bash(echo*), Bash(head*), Bash(tail*)
description: Show compact Memory Castle dashboard
---

Show a compact Memory Castle dashboard with:

**Status**: Current project/worktree  
**Recent Memories**: Last 3 stored items  
**Active Tasks**: Current pending/in-progress tasks  

This provides a tight summary perfect for quick context checking without the verbose table output.

Example output:
```
═══ MEMORY CASTLE DASHBOARD ═══
Status: transmute-platform (main)
Recent: example_key, shared-context, test-key  
Tasks: 2 pending, 1 in-progress
```