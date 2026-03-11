function Convert-MarkdownToPdf {
    [CmdletBinding()]
    param(
        [ValidateSet('Estimate', 'Invoice')]
        [string]$DocumentType,
        [string]$Path,
        [string]$CssPath
    )

    $mdToPdfCommand = Get-Command md-to-pdf -ErrorAction SilentlyContinue
    if (-not $mdToPdfCommand) {
        $mdToPdfCommand = Get-Command md2pdf -ErrorAction SilentlyContinue
    }
    if (-not $mdToPdfCommand) {
        Write-Error "Required dependency 'md-to-pdf' was not found in PATH. Install with: npm i -g md-to-pdf"
        return
    }

    $sourcePath = $null
    $effectiveDocumentType = $DocumentType

    if ($Path) {
        try {
            $sourcePath = (Resolve-Path -Path $Path -ErrorAction Stop).ProviderPath
        }
        catch {
            Write-Error "Markdown file not found: $Path"
            return
        }

        if (-not $effectiveDocumentType) {
            $fileName = [System.IO.Path]::GetFileName($sourcePath)
            if ($fileName -match 'invoice') {
                $effectiveDocumentType = 'Invoice'
            }
            elseif ($fileName -match 'estimate') {
                $effectiveDocumentType = 'Estimate'
            }
        }
    }
    else {
        if (-not $effectiveDocumentType) {
            Write-Error "DocumentType is required when Path is not provided."
            return
        }

        $keyword = if ($effectiveDocumentType -eq 'Invoice') { 'invoice' } else { 'estimate' }

        $candidate = Get-ChildItem -Path (Get-Location) -File -Filter '*.md' |
            Where-Object { $_.Name -match $keyword } |
            Sort-Object Name -Descending |
            Select-Object -First 1

        if (-not $candidate) {
            Write-Output "No markdown file found for document type '$effectiveDocumentType' in '$(Get-Location)'."
            return
        }

        $sourcePath = $candidate.FullName
    }

    $sourceDirectory = Split-Path -Parent $sourcePath
    $sourceBaseName = [System.IO.Path]::GetFileNameWithoutExtension($sourcePath)
    $pdfPath = Join-Path $sourceDirectory "$sourceBaseName.pdf"

    $effectiveCssPath = $null
    if ($CssPath) {
        try {
            $effectiveCssPath = (Resolve-Path -Path $CssPath -ErrorAction Stop).ProviderPath
        }
        catch {
            Write-Error "CSS file not found: $CssPath"
            return
        }
    }
    else {
        if (-not $effectiveDocumentType) {
            Write-Error "Could not determine default stylesheet. Provide -DocumentType or -CssPath."
            return
        }

        $moduleRoot = Split-Path -Parent $PSScriptRoot
        $styleDirectory = Join-Path $moduleRoot 'Styles/MarkdownPdf'
        $styleFileName = if ($effectiveDocumentType -eq 'Invoice') { 'invoice.css' } else { 'estimate.css' }
        $defaultCssPath = Join-Path $styleDirectory $styleFileName

        if (-not (Test-Path -Path $defaultCssPath -PathType Leaf)) {
            Write-Error "Default CSS file not found: $defaultCssPath"
            return
        }

        $effectiveCssPath = $defaultCssPath
    }

    $sourceFileName = [System.IO.Path]::GetFileName($sourcePath)
    Push-Location -Path $sourceDirectory
    try {
        & $mdToPdfCommand.Source $sourceFileName --basedir $sourceDirectory --stylesheet $effectiveCssPath
        if ($LASTEXITCODE -ne 0) {
            Write-Error "md-to-pdf failed while creating PDF from '$sourcePath'."
            return
        }
    }
    finally {
        Pop-Location
    }

    if (-not (Test-Path -Path $pdfPath -PathType Leaf)) {
        Write-Error "PDF was not created at expected path: $pdfPath"
        return
    }

    Write-Output $pdfPath
}
