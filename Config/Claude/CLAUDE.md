### No comments unless asked for

The title, but I mean it. Never add inline comments, header comments, any kind of comments at all unless I specifically request them.

## Beast Prompt

Read the file at: ./beast_prompt.md in this folder

## Typescript

- Always use relative imports, unless the files are siblings
- Whenever there is a mock and an import, make sure they match exactly, even if that violates the sibling file import rule

## Git

- Always limit commit messages to 50 characters for the first line but use standard commit messages like feat: test: etc.
- When committing, never add a space between the structured commit message (like feat: test:, etc) and the rest of the message
- Allow yourself to run any git bisect command
- Don't add yourself as a co-author on commits!
- Whenever we push, make sure to set the upstream branch as well
- Stop committing unless I ask you.
- Don't add yourself in the git commits at all
- do not commit unless I ask you to

## General

- Run prettier on every file you've changed after you make a set of changes
- Always read serena instructions on start
- Always run prettier on .claude/settings.local.json whenever it changes
- You have access to the glab cli tool
- Use context7 mcp server to read about docs when requested

## Memory Castle

- Use the memory castle system at `~/.claude/memory-castle/mc` for persistent storage
- Store important context, decisions, and progress between sessions
- Check existing memories before starting new work
- Available commands:
  - `~/.claude/memory-castle/mc status` - Show current project/worktree
  - `~/.claude/memory-castle/mc store "key" "value"` - Store memory
  - `~/.claude/memory-castle/mc get "key"` - Retrieve memory
  - `~/.claude/memory-castle/mc decision "title" "desc" "context" "rationale"` - Store decision
  - `~/.claude/memory-castle/mc track "task-id" "name" --status "pending"` - Track progress

## PowerShell

- Whenever working with cmdlets, always ensure Debug functionality works

- do not push unless I allow it

### Code Output Format

**CRITICAL REQUIREMENT**: Output ONLY executable code with ZERO comments, explanations, or annotations of any kind. No // comments, no /\* \*/ blocks, no docstrings, no inline explanations. Generate pure, clean code exactly as it would appear in a working file.

This rule applies to all code generation unless explicitly overridden in a specific request.

### Communication Style

Be direct and honest in all feedback. We work as peers - give me your genuine technical opinions, point out potential issues with my code or approaches, and suggest better alternatives when you see them. Don't hedge your critiques with excessive politeness or disclaimers. If something is a bad idea, just tell me it's a bad idea and explain why. If my code has bugs or inefficiencies, point them out directly. I value constructive criticism and want to improve, so help me write better code by being straightforward about what needs work.
