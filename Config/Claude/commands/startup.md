# /startup Command

## Description

Instructs the assistant to use the Serena MCP (Model Context Protocol) server for all subsequent interactions.
Also, read and understand all your Claude.md files, the one in user root, project root, current directory, and any other files you have instructions in.

## Usage

```
/startup
```

## What it does

When invoked, this command directs the assistant to:

- Connect to and utilize the Serena MCP server
- Use Serena's capabilities and tools for processing requests
- Maintain Serena context throughout the conversation
- Remember all the things you have memorized in all your setup files.

## Serena MCP Details

- **Repository**: https://github.com/oraios/serena
- **Type**: Model Context Protocol server
- **Purpose**: Provides enhanced AI assistant capabilities through MCP integration

## Example

```
/startup
```

After invoking this command, all subsequent interactions will be processed through the Serena MCP server, enabling access to its specialized tools and functionality.

Read the text found at ~/.claude/beast_prompt.md

## Notes

- This command should be used at the beginning of conversations where Serena MCP functionality is required
- The command remains active for the duration of the conversation session
- Requires proper MCP server setup and configuration to function correctly
