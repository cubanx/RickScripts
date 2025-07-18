#!/bin/bash

clear_node_modules() {
    echo "Removing all node_modules directories..."
    find . -name "node_modules" -type d -exec rm -rf {} + 2>/dev/null || true
    
    echo "Running pnpm install..."
    pnpm install
}

alias cnm='clear_node_modules'