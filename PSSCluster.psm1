<#
.Synopsis
   Function to validate if current node is suitable for PSSCluster.
.DESCRIPTION
   This command validate that required configuration is present on current node.
   Prerequisites are: Configured Failover Cluster, Cluster Quorum and Git locally installed.
.EXAMPLE
   Get-PSSPrerequisites
.INPUTS
   None
.OUTPUTS
   [Bool] Return if the current node is compliant for PSSCluster.
.COMPONENT
   This function belong to module named: PSSCluster
#>
Function Get-PSSPrerequisites{
    [CmdletBinding()]
    $Global:PSSReadyNode            = $false 
    $Prerequisites                  = [PSCustomObject]@{GitInstalled=$false;ClusterInstalled=$false;QuorumConfigured=$false}
    $SBGitInstalled                 = {$CheckError=0;Try{Invoke-Command -ScriptBlock {$null=Git} -ErrorAction Stop}Catch{$CheckError++;Return $false};if($CheckError -eq 0){return $true}}
    $SBClusterInstalled             = {$CheckError=0;Try{$null=Get-ClusterNode -Name $env:COMPUTERNAME -ErrorAction Stop}Catch{$CheckError++;Return $false};if($CheckError -eq 0){return $true}}
    $SBQuorumConfigured             = {$CheckError=0;Try{$null=Get-ClusterResource -Name 'File Share Witness' -ErrorAction Stop}Catch{$CheckError++;Return $false};if($CheckError -eq 0){return $true}}
    $Prerequisites.GitInstalled     = Invoke-Command $SBGitInstalled
    $Prerequisites.ClusterInstalled = Invoke-Command $SBClusterInstalled
    $Prerequisites.QuorumConfigured = Invoke-Command $SBQuorumConfigured
    if(-Not $Prerequisites.ClusterInstalled){$PSSMessage="Cluster is not installed and/or not correctly configured on this node.";Write-Error $PSSMessage;Write-PSSEvent -Type Error -ID 1 -Message $PSSMessage}
    if(-Not $Prerequisites.GitInstalled){$PSSMessage="GIT is not installed and/or not correctly configured on this node.";Write-Error $PSSMessage;Write-PSSEvent -Type Error -ID 1 -Message $PSSMessage}
    if(-Not $Prerequisites.QuorumConfigured){$PSSMessage="Cluster Quorum witness is not configured on this cluster. As best pratice, you should configure cluster witness. Please refer to microsoft documentation: https://docs.microsoft.com/en-us/windows-server/failover-clustering/file-share-witness.";Write-Warning $PSSMessage;Write-PSSEvent -Type Warning -ID 1 -Message $PSSMessage}
    if($Prerequisites.ClusterInstalled -eq $true -and $Prerequisites.GitInstalled -eq $true){$Global:PSSReadyNode=$true}
    Write-Host "Current node $($env:COMPUTERNAME) is ready for PSSCluster: $Global:PSSReadyNode"
}
<#
.Synopsis
   Function to create new PSSConfiguration for the current node.
.DESCRIPTION
   This command is used to create a new PSSConfiguration for the current node.
   The current node need to be compliant of the PSSCluster prerequisites.
   Use command: Get-PSSPrerequisites to get compliance status.
.EXAMPLE
   New-PSSConfiguration
.INPUTS
   None
.OUTPUTS
   None
.COMPONENT
   This function belong to module named: PSSCluster
#>
Function New-PSSConfiguration{
    [CmdletBinding()]
    Param()
    Get-PSSPrerequisites
    if(-Not$Global:PSSReadyNode){$PSSMessage="This node is not in ready state to be configured as PSSCluster.";Write-Error $PSSMessage;Write-PSSEvent -Type Error -ID 1 -Message $PSSMessage -ErrorAction Stop}
    if(Test-Path "$PSScriptRoot\Config.json"){$PSSMessage="This machine is already configured as PSSCluster. Use Remove-PSSConfiguration before creating new configuration.";Write-Error $PSSMessage;Write-PSSEvent -Type Error -ID 1 -Message $PSSMessage}
    $PSSStagedConfig = [PSCustomObject]@{ClusterMode=0;MasterRepository="C:\NULL";LocalRepository="C:\NULL"}
    While($PSSStagedConfig.ClusterMode -ne '1' -and $PSSStagedConfig.ClusterMode -ne '2'){
        Clear-Host
        Write-Host "1- Mode Active/Active"
        Write-Host "2- Mode Active/Passive"
        Write-Host ""
        $PSSStagedConfig.ClusterMode      = Read-Host "Cluster Mode [1-2]"
    }
    while((Test-path $PSSStagedConfig.MasterRepository) -eq $false -or $PSSStagedConfig.MasterRepository -notlike '\\*' ){
        Clear-Host
        $PSSStagedConfig.MasterRepository = Read-Host "Master Repository [UNC Path]"
    }
    while((Test-path $PSSStagedConfig.LocalRepository) -eq $false -or $PSSStagedConfig.LocalRepository.StartsWith('\\')){
        Clear-Host
        $PSSStagedConfig.LocalRepository  = Read-Host "Local Repository [Folder Path]"
    }
    if($PSSStagedConfig.MasterRepository -eq $PSSStagedConfig.LocalRepository){Write-Error -ErrorAction Stop -Message "The Master repository must be different than the local repository."}
    $Confirm                              = 'NULL'
    While($Confirm -ne 'Y' -and $Confirm -ne 'N'){
        Clear-Host
        $ClusterName                      = (Get-Cluster).Name
        $ClusterNodes                     = ($(Get-ClusterNode -Cluster (Get-Cluster).Name) -join ', ')
        [PSCustomObject]@{'Cluster Name'  = $ClusterName;'Cluster Nodes'=$ClusterNodes;'Cluster Mode'=$PSSStagedConfig.ClusterMode;'Master Repository'=$PSSStagedConfig.MasterRepository;'Local Repository'=$PSSStagedConfig.LocalRepository}
        $Confirm                          = (Read-Host "Do you want to configure PSSCluster with this configuration [y/n]").ToUpper()
    }
    if($Confirm -eq 'Y'){
        Write-Host "Applying PSSCluster Configuration. Please wait..."
        $PSSStagedConfig|ConvertTo-Json|Add-Content "$PSScriptRoot\Config.json"
        try{Write-PSSEvent -Type Information -ID 1 -Message "Test event log registration." -ErrorAction Stop}Catch{
            Try{
                $PSSMessageCount = 0
                Write-Host "Registering PSSCluster into Event Viewer under application."
                New-EventLog -LogName 'PSSCluster' -Source 'PSSCluster' -ErrorAction Stop
                Limit-EventLog -LogName 'PSSCluster' -MaximumSize 10Mb -RetentionDays 90 -OverflowAction OverwriteOlder -ErrorAction Stop
                }Catch{
                    $PSSMessageCount++;$PSSMessage="An error occur while registering event log source: 'PSSCluster'.";Write-Error $PSSMessage;Write-PSSEvent -Type Error -ID 1 -Message $PSSMessage
                }
                if($PSSMessageCount -eq 0){$PSSMessage="Successfully registered event log source: 'PSSCluster'.";Write-Host $PSSMessage;Write-PSSEvent -Type Information -ID 1 -Message $PSSMessage}
        }
        Get-PSSConfiguration
        if($Global:PSSClusterConfiguration -ne $null){$PSSMessage="Successfully created new PSSConfiguration on node: $($env:COMPUTERNAME).";Write-Host $PSSMessage;Write-PSSEvent -Type Information -ID 1 -Message $PSSMessage}
        Sync-PSSRepositories
    }
}
<#
.Synopsis
   Function to write PSSCluster events to local event logs. 
.DESCRIPTION
   This command is used internally of the module to write PSSCluster event to local event logs.
   PSSCluster eventlog must be created into event logs. EventLog is registered when the PSSCluster configuration is created. 
   Refer to command: New-PSSConfiguration
.EXAMPLE
   Write-PSSEvent -Type Error -ID 1 -Message 'Test message'
.EXAMPLE
   Write-PSSEvent -Type Warning -ID 2 -Message 'Test message'
.INPUTS
   [String] Type of event.
   [Int] ID of event.
   [String] Messsage content of the event.
.OUTPUTS
   None
.COMPONENT
   This function belong to module named: PSSCluster
#>
Function Write-PSSEvent{
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory=$true)][ValidateSet('Error','FailureAudit','Information','SuccessAudit','Warning')][String]$Type,
        [Parameter(Mandatory=$true)][int]$ID,
        [Parameter(Mandatory=$true)][String]$Message
    )
    Write-EventLog -LogName 'PSSCluster' -EntryType $Type -EventId $ID -Message ($Message.Trim()+"`n`n RunAs: $($env:USERDOMAIN+'\'+$env:USERNAME)") -Source "PSSCluster" -ErrorAction Stop 
}
<#
.Synopsis
   Function to get the current PSSConfiguartion on the current node. 
.DESCRIPTION
   This command update PSSconfiguration on current node.
   PSSConfiguration must be already configured on the current node.
   Refer to command: New-PSSConfiguration
.EXAMPLE
   Get-PSSConfiguration
.INPUTS
   None
.OUTPUTS
   None
.COMPONENT
   This function belong to module named: PSSCluster
#>
Function Get-PSSConfiguration{
    [CmdletBinding()]
    Param()
    if(-Not(Test-Path "$PSScriptRoot\Config.json")){$PSSMessage="This machine is not configured as PSSCluster. Use New-PSSConfiguration to enroll this node as PSSCluster member.";Write-Error $PSSMessage;Write-PSSEvent -Type Error -ID 1 -Message $PSSMessage}
    else{
        Get-PSSPrerequisites
        if(-Not$Global:PSSReadyNode){
            $NodeStatus = (Get-ClusterNode -Name $env:COMPUTERNAME).State
            if($NodeStatus -eq 'Up'){
                $PSSMessage="Current node is not in ready state for PSSCluster. Enabling maintenance mode on current node: $($env:COMPUTERNAME).";Write-Error $PSSMessage;Write-PSSEvent -Type Error -ID 1 -Message $PSSMessage
                try{Suspend-ClusterNode -Name $env:COMPUTERNAME -Drain -Wait -Confirm:$false -Verbose -ErrorAction Stop}Catch{$PSSMessage="An error occur while enabling maintenance mode on current node: $($env:COMPUTERNAME).";Write-Error $PSSMessage;Write-PSSEvent -Type Error -ID 1 -Message $PSSMessage}
            }
        }
        $RunningConfiguration           = Get-Content "$PSScriptRoot\Config.json"|ConvertFrom-Json
        $Global:PSSClusterConfiguration = [PSCustomObject]@{RunningConfiguration=$RunningConfiguration;ClusterMasterNode=(Get-ClusterGroup -Name 'Cluster Group').OwnerNode.Name}
    }
}
<#
.Synopsis
   Function to synchronize local repositories from master repository.
.DESCRIPTION
   This command update and synchronize all local repositories from master repository.
   If the remote repository already exist locally, its content is pulled from master repository.
   If the remote repository do not exist locally, its content is cloned from master repository. 
   PSSConfiguration must be already configured on the current node.
   Refer to command: New-PSSConfiguration
.EXAMPLE
   Sync-PSSRepositories
.EXAMPLE
   Sync-PSSRepositories -Name 'Repository Name'
.INPUTS
   [String] Name of the repository to synchronize.
.OUTPUTS
   None
.COMPONENT
   This function belong to module named: PSSCluster
#>
Function Sync-PSSRepositories{
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory=$false)][String]$Name
    )
    if($Global:PSSClusterConfiguration -eq $null){Get-PSSConfiguration}
    if($Global:PSSClusterConfiguration -eq $null){$PSSMessage="An error occur while gathering running PSSConfiguration on node: $($env:COMPUTERNAME).";Write-Error $PSSMessage;Write-PSSEvent -Type Error -ID 1 -Message $PSSMessage}
    else{
        If($Name -ne ""){$MasterRepositories = Get-ChildItem $Global:PSSClusterConfiguration.RunningConfiguration.MasterRepository|? {$_.Attributes -eq 'Directory' -and $_.Name -eq $Name}}
        else{$MasterRepositories = Get-ChildItem $Global:PSSClusterConfiguration.RunningConfiguration.MasterRepository|? {$_.Attributes -eq 'Directory'}}
        $MasterRepositories|%{
            if(Test-Path ($Global:PSSClusterConfiguration.RunningConfiguration.LocalRepository+'\'+$_.Name)){
                Write-Host "Pulling repository: $($_.FullName)"
                Set-Location ($Global:PSSClusterConfiguration.RunningConfiguration.LocalRepository+'\'+$_.Name)
                Start-Process -FilePath "Git.exe" -ArgumentList "pull origin" -NoNewWindow -Wait
                $IsTaskRegistered = $true
                Try{$null=Get-ScheduledTask $_.Name -ErrorAction Stop}catch{$IsTaskRegistered=$false}
                if(-Not$IsTaskRegistered){$PSSMessage="Cannot find a registered scheduled task for resource: $($_.Name) under \PSSCluster\.";Write-Warning $PSSMessage;Write-PSSEvent -Type Warning -ID 1 -Message $PSSMessage}
            }
            else{
                Write-Host "Cloning repository: $($_.FullName)"
                Set-Location $Global:PSSClusterConfiguration.RunningConfiguration.LocalRepository
                Start-Process -FilePath "Git.exe" -ArgumentList "clone $($_.FullName)" -NoNewWindow -Wait
                Write-host "Registering Template schedule Task for resource: $($_.Name)"
                $PSSErrorCount = 0
                Try{
                    $Action    = New-ScheduledTaskAction -Execute "Powershell.exe" -Argument "-ExecutionPolicy Bypass -NoProfile -File '$($Global:PSSClusterConfiguration.RunningConfiguration.LocalRepository+'\'+$_.Name+'\Bootstrap.ps1')'" -ErrorAction Stop
                    $Settings  = New-ScheduledTaskSettingsSet -DontStopIfGoingOnBatteries -ErrorAction Stop
                    $null      = Register-ScheduledTask -User "System" -TaskName $_.Name -TaskPath "\PSSCluster" -Description "PSSCluster Resource: $($_.Name)" -Action $Action -Settings $Settings -ErrorAction Stop 
                }Catch{$PSSErrorCount++;$PSSMessage="An error occur registering scheduled task for resource: $($_.Name).";Write-Error $PSSMessage;Write-PSSEvent -Type Error -ID 1 -Message $PSSMessage}
                if($PSSErrorCount -eq 0){Write-Warning "You need to manually modify trigger and runas account for the schedule task into folder '\PSCluster\$($_.Name).'"}
            }
        }
    }
}
<#
.Synopsis
   Function to get active node for specific script.
.DESCRIPTION
   This command is used to know if the current node is the active node for the specified script.
   If no parameter is specified, it returns the owner of the script.
   ParameterPrincipally used while execution bootstrap script from repository code.
.EXAMPLE
   Get-PSSActiveNode -RepositoryName 'Repository Name'
.EXAMPLE
   Get-PSSActiveNode -RepositoryName 'Repository Name' -IsCurrent
.INPUTS
   [String] Repository Name.
   [Switch] To know if the current node is the owner of the repository provided.
.OUTPUTS
   [PSCustomObject] or [Bool] depending of parameters
.COMPONENT
   This function belong to module named: PSSCluster
#>
Function Get-PSSActiveNode{
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory=$true)][String]$RepositoryName,
        [Parameter(Mandatory=$false)][switch]$IsCurrent
    )
    if($Global:PSSClusterConfiguration -eq $null){Get-PSSConfiguration}
    if($Global:PSSClusterConfiguration -eq $null){$PSSMessage="Cannot get current PSSConfiguration for node $($env:COMPUTERNAME).";Write-Error $PSSMessage;Write-PSSEvent -Type Error -ID 1 -Message $PSSMessage}
    else{
        $ClusterGroup = Get-ClusterGroup -Name $RepositoryName
        if($Global:PSSClusterConfiguration.RunningConfiguration.ClusterMode -eq 1){if($IsCurrent){if($ClusterGroup.OwnerNode.Name -eq $env:COMPUTERNAME){Return $true}else{Return $false}}else{return $ClusterGroup.OwnerNode}}
        elseif($Global:PSSClusterConfiguration.RunningConfiguration.ClusterMode -eq 2){if($IsCurrent){if((Get-ClusterGroup -Name 'Cluster Group').OwnerNode.Name -eq $env:COMPUTERNAME){Return $true}else{return $false}}else{return (Get-ClusterGroup -Name 'Cluster Group').OwnerNode}}
    }
}
<#
.Synopsis
   Function to remove current node's PSSConfiguration.
.DESCRIPTION
   This command is used to remove active and current PSSConfiguration.
   All repositories must be removed before removing PSSConfiguartion.
   Parameter: RemoveLocalRepository also remove all existing repository on the current node.
   Refer to command: Remove-PSSRepository.
.EXAMPLE
   Remove-PSSRepository
.EXAMPLE
   Get-PSSRepository -RemoveLocalRepository
.EXAMPLE
   Remove-PSSRepository -Confirm $false
.INPUTS
   [Switch] Parameter to remove local existing repositories.
   [Bool] To execute this command quietly without warning.
.OUTPUTS
   None
.COMPONENT
   This function belong to module named: PSSCluster
#>
Function Remove-PSSConfiguration{
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory=$false)][switch]$RemoveLocalRepository,
        [Parameter(Mandatory=$false)][bool]$Confirm=$true
    )
    if($Global:PSSClusterConfiguration -eq $null){Get-PSSConfiguration}
    if($Global:PSSClusterConfiguration -eq $null){$PSSMessage="Cannot get current PSSConfiguration for node $($env:COMPUTERNAME).";Write-Error $PSSMessage;Write-PSSEvent -Type Error -ID 1 -Message $PSSMessage}
    elseif((Get-PSSRepository).count -ge 1){$PSSMessage="Cannot remove current PSSConfiguration for node $($env:COMPUTERNAME) since repository still exist on this node. Use command: Remove-PSSRepository before removing PSSConfiguration. ";Write-Error $PSSMessage;Write-PSSEvent -Type Error -ID 1 -Message $PSSMessage}
    else{
        if($RemoveLocalRepository){Remove-PSSRepository -RemoveLocalOnly}
        $PSSErrorCount = 0
        try{Remove-Item "$PSScriptRoot\Config.json"}Catch{$PSSErrorCount++;$PSSMessage="An error occur while removing current PSSConfiguration on node: $($env:COMPUTERNAME).";Write-Error $PSSMessage;Write-PSSEvent -Type Error -ID 1 -Message $PSSMessage}
        if($PSSErrorCount -eq 0){$PSSMessage="Successfully removed running configuration for node: $($env:COMPUTERNAME).";Write-Host $PSSMessage;Write-PSSEvent -Type Information -ID 1 -Message $PSSMessage;Remove-Variable -Name 'PSSClusterConfiguration' -Force -Confirm:$false -Scope 'Global'}
    }
}
<#
.Synopsis
   Function to get script bootstrap template.
.DESCRIPTION
   This command is used to get bootstrap template for new repositories.
   It is used internally for the module.
   Refer to command: New-PSSRepository.
.EXAMPLE
   Get-PSSRepositoryTemplate -Name 'Repository Name'
.EXAMPLE
   Get-PSSRepository -RemoveLocalRepository
.INPUTS
   [String] Name of the template
.OUTPUTS
   [String] Return Raw string of the template 
.COMPONENT
   This function belong to module named: PSSCluster
#>
Function Get-PSSRepositoryTemplate{
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory=$true)][String]$Name
    )
Return @"
Import-module PSSCluster
Get-PSSConfiguration
Sync-PSSRepositories -Name "$Name"
if(-Not(Get-PSSActiveNode -IsCurrent -RepositoryName "$Name")){Write-Warning "This is not the active node"}else{
# Place your code here

}
"@
}

<#
.Synopsis
   Function to create new repository.
.DESCRIPTION
   This command is used to create new repository.
   It create the repository on the master repository and synchronize the repository to the local repository.
   It must be unique and not already exist locally. 
.EXAMPLE
   New-PSSRepository -Name 'Repository Name'
.INPUTS
   [String] Name of the new repository. 
.OUTPUTS
   None
.COMPONENT
   This function belong to module named: PSSCluster
#>
Function New-PSSRepository{
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory=$true)][String]$Name
    )
    if($Global:PSSClusterConfiguration -eq $null){Get-PSSConfiguration}
    if($Global:PSSClusterConfiguration -eq $null){$PSSMessage="An error occur while gathering running PSSConfiguration on node: $($env:COMPUTERNAME).";Write-Error $PSSMessage;Write-PSSEvent -Type Error -ID 1 -Message $PSSMessage}
    else{
        $ProjectPath  = ($Global:PSSClusterConfiguration.RunningConfiguration.MasterRepository+'\'+$Name)
        $LocalProject = ($Global:PSSClusterConfiguration.RunningConfiguration.LocalRepository+'\'+$Name)
        if(-Not(Test-Path $Global:PSSClusterConfiguration.RunningConfiguration.LocalRepository)){$null=New-Item $Global:PSSClusterConfiguration.RunningConfiguration.LocalRepository -ItemType Directory}
        if((Test-Path $LocalProject)){$PSSMessage="Cannot create repository $($Name). The repository already exist locally.";Write-Error $PSSMessage;Write-PSSEvent -Type Error -ID 1 -Message $PSSMessage}
        else{
            if((Test-Path $ProjectPath)){$PSSMessage="Cannot create repository $($Name). The repository already exist on the master repository.";Write-Error $PSSMessage;Write-PSSEvent -Type Error -ID 1 -Message $PSSMessage}
            else{
                $PSSMessage = "Creating new repository named $($Name).";Write-Host $PSSMessage;Write-PSSEvent -Type Information -ID 1 -Message $PSSMessage
                $null       = New-Item $ProjectPath -ItemType Directory -Confirm:$false
                Set-Location $ProjectPath
                Write-Host "Initializing Master Repository: $Name"
                Start-Process -FilePath "Git.exe" -ArgumentList "init --bare" -NoNewWindow -Wait
                Write-Host "Adding Cluster Resource Group: $Name"
                $Null       = Add-ClusterGroup -Name $Name -GroupType GenericScript
                Write-Host "Adding Bootstrap file and commit"
                Sync-PSSRepositories -Name $Name
                Set-Location $LocalProject
                $Template   = Get-PSSRepositoryTemplate -Name $Name
                $Template|Add-Content "Bootstrap.ps1"
                Invoke-Command -ScriptBlock {
                    Try{
                        $null = Git.exe add Bootstrap.ps1
                        $null = Git.exe commit -m 'PSSCluster Commit'
                        $null = Git push origin
                    }catch{}
                } -ErrorAction SilentlyContinue
            }
        }
    }
}
<#
.Synopsis
   Function to remove repository.
.DESCRIPTION
   This command is used to remove repository.
   It remove the repository on the master repository, remove cluster resource and scheduled task.
.EXAMPLE
   Remove-PSSRepository -Name 'Repository Name'
.EXAMPLE
   Remove-PSSRepository -Name 'Repository Name' -Confirm $false
.EXAMPLE
   Remove-PSSRepository -Name 'Repository Name' -RemoveLocal
.EXAMPLE
   Remove-PSSRepository -Name 'Repository Name' -RemoveLocal -Confirm $false
.EXAMPLE
   Remove-PSSRepository -Name 'Repository Name' -RemoveLocalOnly
.INPUTS
   [String] Name of the new repository. 
   [Switch] Switch to also remove local repository.
   [Switch] Switch to remove only local repository. It do not remove it from master repository.
   [Bool] To execute this command quietly without warning.
.OUTPUTS
   None
.COMPONENT
   This function belong to module named: PSSCluster
#>
Function Remove-PSSRepository{
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory=$true)][String]$Name     = '',
        [Parameter(Mandatory=$false)][Switch]$RemoveLocal,
        [Parameter(Mandatory=$false)][Switch]$RemoveLocalOnly,
        [Parameter(Mandatory=$false)][Bool]$Confirm = $true
    )
    if($Global:PSSClusterConfiguration -eq $null){Get-PSSConfiguration}
    if($Global:PSSClusterConfiguration -eq $null){$PSSMessage="An error occur while gathering running PSSConfiguration on node: $($env:COMPUTERNAME).";Write-Error $PSSMessage;Write-PSSEvent -Type Error -ID 1 -Message $PSSMessage}
    else{
        $AllRepositories = Get-PSSRepository
        $FolderToClean   = @()
        if($RemoveLocalOnly){$FolderToClean += $AllRepositories|? {$_.Name -EQ $Name -and $_.Type -eq 'Local'}}
        else{
            $FolderToClean += $AllRepositories|? {$_.Name -EQ $Name -and $_.Type -eq 'Master'}
            if($RemoveLocal){$FolderToClean += $AllRepositories|? {$_.Name -EQ $Name -and $_.Type -eq 'Local'}}
        }
        if($Confirm){
            $FolderToClean
            while($Confirm){
                $FolderToClean|%{Write-Host "- $($_.Location)"}
                Write-Host
                $Choice = (Read-Host "These Folder will be deleted. Do you want to proceed [y/n]").ToUpper()
                if($Choice -eq 'Y'){$Confirm = $false}
            }
            if(-Not$Confirm){
                $PSSErrorCount = 0
                try{
                    $FolderToClean|%{Get-ChildItem -Recurse -Path $_.Location|Remove-Item -Recurse -Force -Confirm:$false -Verbose}
                    $FolderToClean|%{Remove-Item -Path $_.Location -Force -Confirm:$false -Recurse -ErrorAction Stop}
                }Catch{$PSSErrorCount++;$PSSMessage="An Error occur while removing repository $($_.Location).";Write-Error $PSSMessage;Write-PSSEvent -Type Error -ID 1 -Message $PSSMessage}
                if($PSSErrorCount -eq 0){$PSSMessage="Successfully removed  local repository $($_.Location).";Write-Host $PSSMessage;Write-PSSEvent -Type Information -ID 1 -Message $PSSMessage}
                if(-Not$RemoveLocalOnly){
                    $PSSErrorCount = 0
                    try{
                        $null = Remove-ClusterGroup -Name $Name -Force -Confirm:$false -Verbose -ErrorAction Stop
                    }Catch{$PSSErrorCount++;$PSSMessage="An Error occur while removing repository $($_.Location).";Write-Error $PSSMessage;Write-PSSEvent -Type Error -ID 1 -Message $PSSMessage}
                    if($PSSErrorCount -eq 0){$PSSMessage="Successfully removed cluster resource $($_.Location).";Write-Host $PSSMessage;Write-PSSEvent -Type Information -ID 1 -Message $PSSMessage}
                 }
                $PSSErrorCount = 0
                try{Unregister-ScheduledTask -TaskName $Name -ErrorAction Stop -Confirm:$false}catch{$PSSMessage="Cannot remove Schedule Task for resource: $Name.";Write-Warning $PSSMessage;Write-PSSEvent -Type Warning -ID 1 -Message $PSSMessage}
                if($PSSErrorCount -eq 0){$PSSMessage="Successfully removed sheduled task $($_.Location).";Write-Host $PSSMessage;Write-PSSEvent -Type Information -ID 1 -Message $PSSMessage;Write-Warning "You will need to manually clean local repository of other node in the cluster."}
            }
        }
        else{
            $PSSErrorCount = 0
            try{
                $FolderToClean|%{Get-ChildItem -Recurse -Path $_.Location|Remove-Item -Recurse -Force -Confirm:$false -Verbose}
                $FolderToClean|%{Remove-Item -Path $_.Location -Force -Confirm:$false -Recurse -ErrorAction Stop}
            }Catch{$PSSErrorCount++;$PSSMessage="An Error occur while removing repository $($_.Location).";Write-Error $PSSMessage;Write-PSSEvent -Type Error -ID 1 -Message $PSSMessage}
            if($PSSErrorCount -eq 0){$PSSMessage="Successfully removed  local repository $($_.Location).";Write-Host $PSSMessage;Write-PSSEvent -Type Information -ID 1 -Message $PSSMessage}
            $PSSErrorCount=0
            try{$null=Remove-ClusterGroup -Name $Name -Force -Confirm:$false -Verbose -ErrorAction Stop}Catch{$PSSErrorCount++;$PSSMessage="An Error occur while removing repository $($_.Location).";Write-Error $PSSMessage;Write-PSSEvent -Type Error -ID 1 -Message $PSSMessage}
            if($PSSErrorCount -eq 0){$PSSMessage="Successfully removed cluster resource $($_.Location).";Write-Host $PSSMessage;Write-PSSEvent -Type Information -ID 1 -Message $PSSMessage}
            $PSSErrorCount=0
            try{Unregister-ScheduledTask -TaskName $Name -ErrorAction Stop -Confirm:$false}catch{$PSSMessage="Cannot remove Schedule Task for resource: $Name.";Write-Warning $PSSMessage;Write-PSSEvent -Type Warning -ID 1 -Message $PSSMessage}
            if($PSSErrorCount -eq 0){$PSSMessage="Successfully removed sheduled task $($_.Location).";Write-Host $PSSMessage;Write-PSSEvent -Type Information -ID 1 -Message $PSSMessage;Write-Warning "You will need to manually clean local repository of other node in the cluster."}
            
        }
    }
}
<#
.Synopsis
   Function to get HA repositories configured on the master repository and local repository.
.DESCRIPTION
   Function to get HA repositories configured on the master repository and local repository.
.EXAMPLE
   Get-PSSRepository
.EXAMPLE
   Get-PSSRepository -Name 'Repository Name'
.EXAMPLE
   Get-PSSRepository -Name 'Repository Name' -LocalRepository
.EXAMPLE
   Get-PSSRepository -Name 'Repository Name' -MasterRepository
.EXAMPLE
   Get-PSSRepository
.INPUTS
   [String] Only repository name
   [Switch] Include only local repository.
   [Switch] Include only master repository
.OUTPUTS
   [PSCustomObject[]] Array of detected repository based on filter parameters.
.COMPONENT
   This function belong to module named: PSSCluster
#>
Function Get-PSSRepository{
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory=$false)][String]$Name = '',
        [Parameter(Mandatory=$false)][Switch]$LocalRepository,
        [Parameter(Mandatory=$false)][Switch]$MasterRepository
    )
    if($Global:PSSClusterConfiguration -eq $null){Get-PSSConfiguration}
    if($Global:PSSClusterConfiguration -eq $null){$PSSMessage="An error occur while gathering running PSSConfiguration on node: $($env:COMPUTERNAME).";Write-Error $PSSMessage;Write-PSSEvent -Type Error -ID 1 -Message $PSSMessage}
    else{
        $PSSDatabase = @()
        if($Name -ne ''){
            if($LocalRepository){
                $Local  = Get-ChildItem $Global:PSSClusterConfiguration.RunningConfiguration.LocalRepository|? {$_.Attributes -eq 'Directory' -and $_.Name -eq $Name}
                $Local|%{$PSSDatabase+=[PSCustomObject]@{Type='Local';Name=$_.Name;Location=$_.FullName}}
            }
            elseif($MasterRepository){
                $Master = Get-ChildItem $Global:PSSClusterConfiguration.RunningConfiguration.MasterRepository|? {$_.Attributes -eq 'Directory' -and $_.Name -eq $Name}
                $Master|%{$PSSDatabase+=[PSCustomObject]@{Type='Master';Name=$_.Name;Location=$_.FullName}}
            }
            else{
                $Master = Get-ChildItem $Global:PSSClusterConfiguration.RunningConfiguration.MasterRepository|? {$_.Attributes -eq 'Directory' -and $_.Name -eq $Name}
                $Local  = Get-ChildItem $Global:PSSClusterConfiguration.RunningConfiguration.LocalRepository|? {$_.Attributes -eq 'Directory' -and $_.Name -eq $Name}
                $Master|%{$PSSDatabase+=[PSCustomObject]@{Type='Master';Name=$_.Name;Location=$_.FullName}}
                $Local|%{$PSSDatabase+=[PSCustomObject]@{Type='Local';Name=$_.Name;Location=$_.FullName}}
            }
        }
        else{
            if($LocalRepository){
                $Local  = Get-ChildItem $Global:PSSClusterConfiguration.RunningConfiguration.LocalRepository|? {$_.Attributes -eq 'Directory'}
                $Local|%{$PSSDatabase+=[PSCustomObject]@{Type='Local';Name=$_.Name;Location=$_.FullName}}
            }
            elseif($MasterRepository){
                $Master = Get-ChildItem $Global:PSSClusterConfiguration.RunningConfiguration.MasterRepository|? {$_.Attributes -eq 'Directory'}
                $Master|%{$PSSDatabase+=[PSCustomObject]@{Type='Master';Name=$_.Name;Location=$_.FullName}}
            }
            else{
                $Master = Get-ChildItem $Global:PSSClusterConfiguration.RunningConfiguration.MasterRepository|? {$_.Attributes -eq 'Directory'}
                $Local  = Get-ChildItem $Global:PSSClusterConfiguration.RunningConfiguration.LocalRepository|? {$_.Attributes -eq 'Directory'}
                $Master|%{$PSSDatabase+=[PSCustomObject]@{Type='Master';Name=$_.Name;Location=$_.FullName}}
                $Local|%{$PSSDatabase+=[PSCustomObject]@{Type='Local';Name=$_.Name;Location=$_.FullName}}
            }
        }
        $PSSDatabase
    }
}