#!/bin/bash
[ -t 0 ] || { echo "BLOCKED: No interactive terminal"; exit 1; }
read -p "Slack message requested. Allow? [y/N] " -n 1 -r </dev/tty
echo
[[ $REPLY =~ ^[Yy]$ ]] || { echo "BLOCKED: User denied"; exit 1; }
