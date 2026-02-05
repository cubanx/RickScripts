function Open-MergeRequest {
    [CmdletBinding()]
    param()

    if (-not (git rev-parse --is-inside-work-tree 2>$null)) {
        Write-Output "Not in a git repository"
        return
    }

    $branch = git rev-parse --abbrev-ref HEAD 2>$null
    $urls = @()

    if (Get-Command gh -ErrorAction SilentlyContinue) {
        $ghUrl = gh pr view --json url --jq '.url' 2>$null
        if (($LASTEXITCODE -ne 0 -or -not $ghUrl) -and $branch) {
            $ghUrl = gh pr list --head $branch --state open --limit 1 --json url --jq '.[0].url' 2>$null
        }
        if ($LASTEXITCODE -eq 0 -and $ghUrl) {
            $urls += $ghUrl
        }
    }

    if (Get-Command glab -ErrorAction SilentlyContinue) {
        $glUrl = glab mr view --json web_url --jq '.web_url' 2>$null
        if (($LASTEXITCODE -ne 0 -or -not $glUrl) -and $branch) {
            $glUrl = glab mr list --source-branch $branch --per-page 1 --output json 2>$null |
                ConvertFrom-Json |
                Select-Object -First 1 |
                ForEach-Object { $_.web_url }
        }
        if ($LASTEXITCODE -eq 0 -and $glUrl) {
            $urls += $glUrl
        }
    }

    $urls = $urls | Where-Object { $_ } | Select-Object -Unique

    if (-not $urls) {
        Write-Output "No PR/MR found for branch '$branch'"
        return
    }

    foreach ($url in $urls) {
        Start-Process $url
    }
}

Set-Alias omr Open-MergeRequest

