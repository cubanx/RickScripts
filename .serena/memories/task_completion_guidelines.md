# Task Completion Guidelines

## What to Do When a Task is Completed

### 1. No Formal Build/Test Process
- RickScripts is a simple PowerShell module with no build system, test framework, or linting tools
- No `npm run test`, `npm run lint`, or similar commands exist

### 2. Manual Verification Steps
- **Function Testing**: Load the function individually and test it manually
  ```powershell
  . ./Functions/YourFunction.ps1
  YourFunction -Parameter Value
  ```

- **Module Import Test**: Verify the entire module still loads correctly
  ```powershell
  Import-Module ./RickScripts.psd1 -Force
  Get-Module RickScripts
  ```

### 3. Code Quality Checks
- **Syntax Validation**: Ensure PowerShell can parse the file without errors
- **Dependency Verification**: Check that any new external tool dependencies are documented
- **Convention Adherence**: Follow established patterns in existing functions

### 4. Documentation Updates
- Update `CLAUDE.md` if new functions or significant changes are made
- Update module manifest (`RickScripts.psd1`) if new functions or aliases are added
- No separate documentation files needed (per CLAUDE.md instructions)

### 5. Git Workflow
- Commit changes with structured commit messages: `feat:`, `fix:`, `docs:`, etc.
- Maximum 50 characters for first line of commit message
- Push with upstream branch setting: `git push -u origin branch-name`

### 6. No Automated CI/CD
- This is a personal utility module with no continuous integration setup
- Manual testing and verification is the primary quality assurance method