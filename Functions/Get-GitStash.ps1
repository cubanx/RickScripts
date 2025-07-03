function Get-GitStash {
    [CmdletBinding()]
    param()
    $stashes = git stash list | fzf --ansi --height 40% --reverse --prompt 'Pick a stash: '
    if ($stashes) {
        $stashRef = $stashes -replace '^(stash@\{\d+\}).*', '$1'
        Write-Output $stashRef
    }
}
Set-Alias -Name ggs -Value Get-GitStash
