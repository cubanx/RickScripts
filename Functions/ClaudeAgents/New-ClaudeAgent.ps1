function New-ClaudeAgent {
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [Parameter(Mandatory = $false)]
        [string[]]$AgentType = "all",
        
        [Parameter(Mandatory = $false)]
        [switch]$Force
    )
    
    $claudeAgentsPath = "$env:HOME/.claude/agents"
    if (!(Test-Path $claudeAgentsPath)) {
        Write-Debug "Creating Claude agents directory: $claudeAgentsPath"
        New-Item -ItemType Directory -Path $claudeAgentsPath -Force | Out-Null
    }

    # Load base template from file
    $templatePath = Join-Path $PSScriptRoot "BaseAgentTemplate.md"
    if (-not (Test-Path $templatePath)) {
        Write-Error "Base agent template not found at: $templatePath"
        return
    }
    
    $baseTemplate = Get-Content $templatePath -Raw

    # Load agent configurations from JSON files
    $frameworksPath = Join-Path $PSScriptRoot "Frameworks"
    $agents = @{}
    
    if (Test-Path $frameworksPath) {
        $agentFiles = Get-ChildItem -Path $frameworksPath -Filter "*.json"
        foreach ($file in $agentFiles) {
            $agentKey = [System.IO.Path]::GetFileNameWithoutExtension($file.Name)
            try {
                $agentConfig = Get-Content $file.FullName -Raw | ConvertFrom-Json
                $agents[$agentKey] = @{
                    displayName   = $agentConfig.displayName
                    shortName     = $agentConfig.shortName
                    description   = $agentConfig.description
                    contextAreas  = $agentConfig.contextAreas
                    researchAreas = $agentConfig.researchAreas
                }
                Write-Debug "Loaded agent configuration: $agentKey"
            }
            catch {
                Write-Warning "Failed to load agent configuration from $($file.Name): $($_.Exception.Message)"
            }
        }
    }
    else {
        Write-Error "Frameworks directory not found at: $frameworksPath"
        return
    }

    # Determine which agents to create
    $agentsToCreate = if ($AgentType -contains "all") { 
        $agents.Keys 
    }
    else { 
        $AgentType 
    }
    
    $createdAgents = @()
    $skippedAgents = @()
    
    # Generate each requested agent file
    foreach ($agentKey in $agentsToCreate) {
        if (-not $agents.ContainsKey($agentKey)) {
            Write-Warning "Unknown agent type: $agentKey"
            continue
        }
        
        $filePath = Join-Path $claudeAgentsPath "$agentKey-research.md"
        
        # Check if agent already exists
        if ((Test-Path $filePath) -and -not $Force) {
            Write-Debug "Agent '$agentKey' already exists. Use -Force to overwrite."
            $skippedAgents += $agentKey
            continue
        }
        
        $agent = $agents[$agentKey]
        
        # Create the agent content by formatting the base template
        $agentContent = $baseTemplate -f @(
            $agentKey,                              # {0} - name
            $agent.description,                     # {1} - description
            $agent.displayName,                     # {2} - display name
            $agent.shortName,                       # {3} - short name for "specialist"
            $agent.shortName,                       # {4} - features/patterns context
            $agent.contextAreas[0],                 # {5} - config/usage patterns
            $agent.contextAreas[1],                 # {6} - patterns context
            $agent.shortName,                       # {7} - documentation context
            $agent.contextAreas[2],                 # {8} - approaches context
            $agent.contextAreas[4],                 # {9} - organization context
            $agent.shortName,                       # {10} - research areas context
            $agent.researchAreas                    # {11} - research areas list
        )
        
        # Write the file
        if ($PSCmdlet.ShouldProcess("$filePath", "Create agent file")) {
            $agentContent | Out-File -FilePath $filePath -Encoding UTF8
            $createdAgents += $agentKey
            Write-Debug "Created: $agentKey.md"
        }
    }
    
    # Summary output
    if ($createdAgents.Count -gt 0) {
        Write-Debug "Successfully created $($createdAgents.Count) agent(s): $($createdAgents -join ', ')"
    }
    
    if ($skippedAgents.Count -gt 0) {
        Write-Debug "Skipped $($skippedAgents.Count) existing agent(s): $($skippedAgents -join ', ')"
    }
}

Set-Alias nca New-ClaudeAgent


