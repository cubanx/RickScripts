function Add-EnvTo1Password {
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [Parameter(Mandatory = $true)][string]$ProjectName,
        [Parameter(Mandatory = $true)][string]$Environment,
        [string]$EnvPath = ".env",
        [string]$Vault = "Employee"
    )

    if (!(Get-Command op -ErrorAction SilentlyContinue)) {
        Write-Error "1Password CLI 'op' not found. Please install it and ensure it's in your PATH."
        return
    }

    if (!(Test-Path $EnvPath)) {
        Write-Error ".env file not found at '$EnvPath'"
        return
    }

    # Ensure signed in
    try { op account list | Out-Null }
    catch { op signin }

    $envVars = @{}
    Get-Content $EnvPath | ForEach-Object {
        if ($_ -match '^([^#\s][^=]*)=(.*)$') {
            $key = $matches[1].Trim()
            $value = $matches[2].Trim() -replace '^["'']|["'']$', ''
            $envVars[$key] = $value
        }
    }

    if ($envVars.Count -eq 0) {
        Write-Warning "No variables found in '$EnvPath'."
        return
    }

    $itemName = "$ProjectName-$Environment"
    Write-Host "Preparing to add/update 1Password item: '$itemName' in vault '$Vault'"
    Write-Host "Found variables: $($envVars.Keys -join ', ')"

    # Check if item already exists
    $existingItem = op item get $itemName --vault $Vault --format json 2>$null
    
    $opArgs = @()
    if ($existingItem) {
        # Item exists, use 'edit'
        Write-Host "Item '$itemName' already exists. Updating fields."
        $opArgs += "item", "edit", $itemName, "--vault", $Vault
    }
    else {
        # Item does not exist, use 'create'
        Write-Host "Item '$itemName' does not exist. Creating new item."
        $opArgs += "item", "create", "--category", "Secure Note", "--title", $itemName, "--vault", $Vault, "--tags", "env-vars,env-vars/$ProjectName,env-vars/$Environment"
    }

    foreach ($key in $envVars.Keys) {
        $fieldName = $key.ToLower()
        $value = $envVars[$key]
        # Format for op cli is 'fieldname[type]=value'
        $opArgs += "$($fieldName)[password]=$value"
    }

    if ($PSCmdlet.ShouldProcess("1Password item '$itemName'", "Create/Update with $($envVars.Count) variables")) {
        & op @opArgs | Out-Null
        Write-Host "✅ Successfully created/updated 1Password item '$itemName'." -ForegroundColor Green
    }
}

Set-Alias ae1p Add-EnvTo1Password

