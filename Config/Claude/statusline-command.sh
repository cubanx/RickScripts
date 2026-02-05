#!/usr/local/microsoft/powershell/7/pwsh

Import-Module posh-git


# Read JSON input from stdin automatically available as $input
$inputString = $input -join ""

# Extract values using ConvertFrom-Json
$jsonObject = $inputString | ConvertFrom-Json
$currentDir = $jsonObject.workspace.current_dir

# Show git branch if in a git repo using posh-git
$gitBranch = ""
if ($currentDir) {
    Set-Location $currentDir
    $gitStatus = Get-GitStatus -Force
    if ($gitStatus) {
        # Customize colors to be brighter
        $GitPromptSettings.BranchColor.ForegroundColor = [ConsoleColor]::Cyan
        $GitPromptSettings.IndexColor.ForegroundColor = [ConsoleColor]::Green
        $GitPromptSettings.WorkingColor.ForegroundColor = [ConsoleColor]::Yellow
        
        # Use posh-git's built-in formatting with brighter colors
        $statusString = Write-VcsStatus $gitStatus
        $gitBranch = " | $statusString"
    }
}

if ($currentDir) {
    $dirName = Split-Path $currentDir -Leaf
    Write-Output "$dirName$gitBranch"
} else {
    Write-Output "Unknown$gitBranch"
}