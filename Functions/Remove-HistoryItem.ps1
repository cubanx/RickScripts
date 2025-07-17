function Remove-HistoryItem {
    [CmdletBinding(SupportsShouldProcess = $true)]
    param()
    
    # Get PSReadLine history file location
    $historyFile = (Get-PSReadLineOption).HistorySavePath
    
    if (-not (Test-Path $historyFile)) {
        Write-Warning "History file not found: $historyFile"
        return
    }
    
    # Read all history items
    $historyItems = Get-Content $historyFile
    
    if ($historyItems.Count -eq 0) {
        Write-Output "No history items found"
        return
    }
    
    # Create numbered list with most recent first (reverse order)
    $numberedItems = @()
    for ($i = $historyItems.Count - 1; $i -ge 0; $i--) {
        $numberedItems += "{0:D4}: {1}" -f ($historyItems.Count - $i), $historyItems[$i]
    }
    
    # Use fzf to select items to delete (allow multiple selection)
    $selectedItems = $numberedItems | fzf --multi --ansi --height 40% --reverse --prompt 'Select history items to delete (Tab for multi-select): '
    
    if (-not $selectedItems) {
        Write-Output "No items selected"
        return
    }
    
    # Extract the original commands from selected items
    $commandsToDelete = @()
    foreach ($item in $selectedItems) {
        if ($item -match '^\d{4}: (.+)$') {
            $commandsToDelete += $matches[1]
        }
    }
    
    Write-Output "Selected $($commandsToDelete.Count) items to delete:"
    $commandsToDelete | ForEach-Object { Write-Output "  $_" }
    
    if ($PSCmdlet.ShouldProcess("$($commandsToDelete.Count) history items", "Delete")) {
        # Create new history without the selected items
        $newHistory = @()
        foreach ($historyItem in $historyItems) {
            if ($historyItem -notin $commandsToDelete) {
                $newHistory += $historyItem
            }
        }
        
        # Write the updated history back to file
        $newHistory | Set-Content $historyFile -Encoding UTF8
        
        Write-Output "Deleted $($commandsToDelete.Count) items from history"
        Write-Output "Remaining items: $($newHistory.Count)"
    }
}

Set-Alias rhi Remove-HistoryItem