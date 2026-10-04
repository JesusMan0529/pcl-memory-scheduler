#Requires -Version 5.1
#Requires -RunAsAdministrator
param([Parameter(Mandatory = $true)][string]$PclPath)
$ErrorActionPreference = 'Stop'
$taskName = 'PCL-Memory-Optimize-Every5Minutes'
$installDirectory = Join-Path $env:ProgramFiles 'PCLMemoryScheduler'
$logDirectory = Join-Path $env:ProgramData 'PCLMemoryScheduler'
$resultPath = Join-Path $PSScriptRoot 'install-result.json'
$registered = $false
$createdInstallDirectory = $false
$createdLogDirectory = $false

function Set-ProtectedDirectoryAcl([string]$Path) {
    $acl = [Security.AccessControl.DirectorySecurity]::new()
    $acl.SetAccessRuleProtection($true, $false)
    $inheritance = [Security.AccessControl.InheritanceFlags]'ContainerInherit, ObjectInherit'
    foreach ($sid in @('S-1-5-18', 'S-1-5-32-544')) {
        $identity = [Security.Principal.SecurityIdentifier]::new($sid)
        $acl.AddAccessRule([Security.AccessControl.FileSystemAccessRule]::new(
            $identity, 'FullControl', $inheritance, 'None', 'Allow'))
    }
    $users = [Security.Principal.SecurityIdentifier]::new('S-1-5-32-545')
    $acl.AddAccessRule([Security.AccessControl.FileSystemAccessRule]::new(
        $users, 'ReadAndExecute', $inheritance, 'None', 'Allow'))
    Set-Acl -LiteralPath $Path -AclObject $acl
}

try {
    if (Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue) {
        throw "Task already exists: $taskName. Uninstall it before reinstalling."
    }
    if (Test-Path -LiteralPath $installDirectory) {
        throw 'Installation directory already exists. Refusing to overwrite it.'
    }
    $pclFile = Get-Item -LiteralPath $PclPath -ErrorAction Stop
    if ($pclFile.PSIsContainer -or $pclFile.Name -ne 'Plain Craft Launcher 2.exe' -or
        $pclFile.VersionInfo.ProductName -ne 'Plain Craft Launcher') {
        throw 'Select a Plain Craft Launcher 2.exe file from an installed PCL directory.'
    }
    New-Item -ItemType Directory -Path $installDirectory | Out-Null
    $createdInstallDirectory = $true
    Set-ProtectedDirectoryAcl $installDirectory
    if (Test-Path -LiteralPath $logDirectory) {
        if ((Get-Item -LiteralPath $logDirectory).Attributes -band [IO.FileAttributes]::ReparsePoint) {
            throw 'Refusing to use a redirected log directory.'
        }
    } else {
        New-Item -ItemType Directory -Path $logDirectory | Out-Null
        $createdLogDirectory = $true
    }
    Set-ProtectedDirectoryAcl $logDirectory
    $worker = Join-Path $installDirectory 'MemoryScheduler.exe'
    Copy-Item -LiteralPath $pclFile.FullName -Destination (Join-Path $installDirectory $pclFile.Name)
    $compiler = Join-Path $env:WINDIR 'Microsoft.NET\Framework64\v4.0.30319\csc.exe'
    $compilerOutput = & $compiler /nologo /target:winexe /optimize+ /platform:x64 "/out:$worker" (Join-Path $PSScriptRoot 'MemoryScheduler.cs') 2>&1
    if ($LASTEXITCODE -ne 0) { throw "Compilation failed: $compilerOutput" }
    Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'Uninstall.ps1') -Destination $installDirectory
    $action = New-ScheduledTaskAction -Execute $worker -WorkingDirectory $installDirectory
    $trigger = New-ScheduledTaskTrigger -AtStartup
    $trigger.Delay = 'PT30S'
    $principal = New-ScheduledTaskPrincipal -UserId 'SYSTEM' -LogonType ServiceAccount -RunLevel Highest
    $settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries `
        -StartWhenAvailable -MultipleInstances IgnoreNew -ExecutionTimeLimit ([TimeSpan]::Zero) `
        -RestartCount 3 -RestartInterval (New-TimeSpan -Minutes 1)
    Register-ScheduledTask -TaskName $taskName -Action $action -Trigger $trigger -Principal $principal `
        -Settings $settings -Description 'Run PCL --memory in the background every 5 minutes; start 30 seconds after boot.' | Out-Null
    $registered = $true
    $testStarted = [DateTimeOffset]::Now
    Start-ScheduledTask -TaskName $taskName
    $runsPath = Join-Path $logDirectory 'runs.csv'
    $deadline = [DateTime]::UtcNow.AddSeconds(110)
    do {
        Start-Sleep -Seconds 2
        if (Test-Path -LiteralPath $runsPath) {
            $firstRun = Import-Csv -LiteralPath $runsPath | Select-Object -Last 1
            if ($firstRun -and [DateTimeOffset]::Parse($firstRun.started) -ge $testStarted) { break }
            $firstRun = $null
        }
    } while ([DateTime]::UtcNow -lt $deadline)
    if (-not $firstRun -or $firstRun.result -ne 'success') {
        throw "First background invocation failed: $($firstRun | ConvertTo-Json -Compress)"
    }
    [ordered]@{success=$true;taskName=$taskName;worker=$worker;log=$runsPath;firstRun=$firstRun} |
        ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $resultPath -Encoding UTF8
}
catch {
    $failure = $_.Exception.Message
    if ($registered) {
        Stop-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
        Unregister-ScheduledTask -TaskName $taskName -Confirm:$false -ErrorAction SilentlyContinue
    }
    if ($createdInstallDirectory) {
        $resolvedInstall = [IO.Path]::GetFullPath($installDirectory)
        if ($resolvedInstall -eq [IO.Path]::GetFullPath((Join-Path $env:ProgramFiles 'PCLMemoryScheduler'))) {
            Remove-Item -LiteralPath $resolvedInstall -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
    if ($createdLogDirectory) {
        $resolvedLog = [IO.Path]::GetFullPath($logDirectory)
        if ($resolvedLog -eq [IO.Path]::GetFullPath((Join-Path $env:ProgramData 'PCLMemoryScheduler'))) {
            Remove-Item -LiteralPath $resolvedLog -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
    [ordered]@{success=$false;error=$failure} | ConvertTo-Json |
        Set-Content -LiteralPath $resultPath -Encoding UTF8
    exit 1
}
