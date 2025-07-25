function Remove-HistoryDuplicates {
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [switch]$Restore
    )
    
    # Get PSReadLine history file location
    $historyFile = (Get-PSReadLineOption).HistorySavePath
    $historyDir = Split-Path $historyFile -Parent
    $historyFileName = Split-Path $historyFile -Leaf
    $historyBaseName = [System.IO.Path]::GetFileNameWithoutExtension($historyFileName)
    $historyExtension = [System.IO.Path]::GetExtension($historyFileName)
    
    if (-not (Test-Path $historyFile)) {
        Write-Warning "History file not found: $historyFile"
        return
    }
    
    # Handle restore functionality
    if ($Restore) {
        # Find available backup files
        $backupPattern = "$historyBaseName.backup.*$historyExtension"
        $backupFiles = Get-ChildItem -Path $historyDir -Filter $backupPattern | Sort-Object Name
        
        if ($backupFiles.Count -eq 0) {
            Write-Warning "No backup files found"
            return
        }
        
        # Display available backups with fzf
        $backupOptions = @()
        foreach ($backup in $backupFiles) {
            $backupNumber = ($backup.Name -split '\.')[2]
            $backupDate = $backup.LastWriteTime.ToString("yyyy-MM-dd HH:mm:ss")
            $backupOptions += "$backupNumber : $backupDate : $($backup.Name)"
        }
        
        $selectedBackup = $backupOptions | fzf --ansi --height 40% --reverse --prompt 'Select backup to restore: '
        
        if (-not $selectedBackup) {
            Write-Output "No backup selected"
            return
        }
        
        $selectedBackupFile = $selectedBackup.Split(' : ')[2]
        $backupPath = Join-Path $historyDir $selectedBackupFile
        
        if ($PSCmdlet.ShouldProcess("$backupPath to $historyFile", "Restore backup")) {
            Copy-Item $backupPath $historyFile -Force
            Write-Output "Restored backup: $selectedBackupFile"
        }
        return
    }
    
    # Read all history items
    $historyItems = Get-Content $historyFile
    
    if ($historyItems.Count -eq 0) {
        Write-Output "No history items found"
        return
    }
    
    $originalCount = $historyItems.Count
    Write-Output "Original history contains $originalCount items"
    
    # Remove duplicates while preserving order (keeps last occurrence)
    $uniqueItems = @()
    $seen = @{}
    
    # Process from end to beginning to keep most recent occurrence
    for ($i = $historyItems.Count - 1; $i -ge 0; $i--) {
        $item = $historyItems[$i]
        if (-not $seen.ContainsKey($item)) {
            $seen[$item] = $true
            $uniqueItems = @($item) + $uniqueItems
        }
    }
    
    $duplicateCount = $originalCount - $uniqueItems.Count
    
    if ($duplicateCount -eq 0) {
        Write-Output "No duplicates found in history"
        return
    }
    
    Write-Output "Found $duplicateCount duplicate items"
    
    if ($PSCmdlet.ShouldProcess("$duplicateCount duplicate history items", "Remove")) {
        # Create backup before making changes
        $backupNumber = 1
        do {
            $backupFile = "$historyBaseName.backup.$backupNumber$historyExtension"
            $backupPath = Join-Path $historyDir $backupFile
            $backupNumber++
        } while (Test-Path $backupPath)
        
        # Create the backup
        Copy-Item $historyFile $backupPath -Force
        Write-Output "Created backup: $backupFile"
        
        # Clean up old backups (keep only 10 most recent)
        $allBackups = Get-ChildItem -Path $historyDir -Filter "$historyBaseName.backup.*$historyExtension" | 
            Sort-Object Name -Descending
        
        if ($allBackups.Count -gt 10) {
            $backupsToDelete = $allBackups | Select-Object -Skip 10
            foreach ($oldBackup in $backupsToDelete) {
                Remove-Item $oldBackup.FullName -Force
                Write-Output "Deleted old backup: $($oldBackup.Name)"
            }
        }
        
        # Write the deduplicated history back to file
        $uniqueItems | Set-Content $historyFile -Encoding UTF8
        
        Write-Output "Removed $duplicateCount duplicate items from history"
        Write-Output "History now contains $($uniqueItems.Count) unique items"
    }
}

Set-Alias rhd Remove-HistoryDuplicates
