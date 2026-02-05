$ErrorActionPreference = 'SilentlyContinue'

# Fast exit when not in a git repo
if (-not (git rev-parse --is-inside-work-tree 2>$null)) {
    return
}

$parts = @()
$links = @{}
$branch = git rev-parse --abbrev-ref HEAD 2>$null

function Add-Link([string]$label, [string]$url) {
    if ([string]::IsNullOrWhiteSpace($url)) { return }
    $script:links[$label] = $url
}

# GitHub PR
if (Get-Command gh -ErrorAction SilentlyContinue) {
    $ghInfo = gh pr view --json number, url --jq '.number, .url' 2>$null
    if (($LASTEXITCODE -ne 0 -or -not $ghInfo) -and $branch) {
        $ghInfo = gh pr list --head $branch --state open --limit 1 --json number, url --jq '.[0].number, .[0].url' 2>$null
    }
    if ($LASTEXITCODE -eq 0 -and $ghInfo) {
        $ghLines = $ghInfo -split "`n" | Where-Object { $_ -ne '' }
        if ($ghLines.Count -ge 2) {
            $ghNumber = $ghLines[0]
            $ghUrl = $ghLines[1]
            $label = "#$ghNumber"
            $parts += $label
            Add-Link $label $ghUrl
        }
    }
}

# GitLab MR
if (Get-Command glab -ErrorAction SilentlyContinue) {
    $glInfo = glab mr view --json iid, web_url --jq '.iid, .web_url' 2>$null
    if (($LASTEXITCODE -ne 0 -or -not $glInfo) -and $branch) {
        $glInfo = glab mr list --source-branch $branch --per-page 1 --output json 2>$null |
            ConvertFrom-Json |
            Select-Object -First 1 |
            ForEach-Object { "$($_.iid)`n$($_.web_url)" }
    }
    if ($LASTEXITCODE -eq 0 -and $glInfo) {
        $glLines = $glInfo -split "`n" | Where-Object { $_ -ne '' }
        if ($glLines.Count -ge 2) {
            $glIid = $glLines[0]
            $glUrl = $glLines[1]
            $label = "!$glIid"
            $parts += $label
            Add-Link $label $glUrl
        }
    }
}

if ($parts.Count -gt 0) {
    $env:POSH_PR_MR_LINKS = ($links.GetEnumerator() | ForEach-Object { "$($_.Key)=$($_.Value)" }) -join ';'
    Write-Output ($parts -join ' ')
}
else {
    $env:POSH_PR_MR_LINKS = ''
}

