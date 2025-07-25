function Clear-NodeModules {
    rm -rf ./**/node_modules
    pnpm install
}

Set-Alias cnm Clear-NodeModules
