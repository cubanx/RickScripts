function Get-EnvFrom1Password {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$ProjectName,
        [Parameter(Mandatory = $true)][string]$Environment,
        [string]$EnvExamplePath = ".env.example"
    )

    if (!(Get-Command op -ErrorAction SilentlyContinue)) {
        Write-Error "1Password CLI not found"
        return
    }

    # Your personal 1Password references
    # This section should ideally be dynamically generated or configured elsewhere
    # For demonstration, we'll construct the item name based on ProjectName and Environment
    $itemName = "$ProjectName-$Environment"

    if (!(Test-Path $EnvExamplePath)) {
        Write-Error "'.env.example' file not found at '$EnvExamplePath'. Please provide a valid path or ensure the file exists."
        return
    }

    $expectedKeys = @()
    Get-Content $EnvExamplePath | ForEach-Object {
        if ($_ -match '^([A-Za-z_][A-Za-z0-9_]*)=.*$') {
            $key = $matches[1].Trim()
            $expectedKeys += $key
        }
        elseif ($_ -match '^([A-Za-z_][A-Za-z0-9_]*)$') {
            # Handle keys without values
            $expectedKeys += $matches[1].Trim()
        }
    }

    Write-Host "Setting up $ProjectName-$Environment environment..."

    # Ensure signed in
    try { op account list | Out-Null }
    catch { op signin }

    # Create .env file
    $content = @("# Generated from 1Password on $(Get-Date)", "")
    foreach ($key in $expectedKeys) {
        $opPath = "op://Private/$itemName/$($key.ToLower())" # Assuming field names are lowercase
        try {
            $value = op read $opPath
            $content += "$key=$value"
            Write-Host "✓ $key"
        }
        catch {
            Write-Warning "Could not read $key from $opPath. Skipping."
        }
    }

    $content | Out-File -FilePath ".env" -Encoding UTF8
    Write-Host "✅ .env file ready!"
}

Set-Alias ge1p Get-EnvFrom1Password

