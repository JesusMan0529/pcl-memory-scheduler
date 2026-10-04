#Requires -Version 5.1
#Requires -RunAsAdministrator
$ErrorActionPreference = 'Stop'
$taskName = 'PCL-Memory-Optimize-Every5Minutes'
$task = Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
if ($task) {
    Stop-ScheduledTask -TaskName $taskName
    $deadline = [DateTime]::UtcNow.AddSeconds(15)
    while ((Get-ScheduledTask -TaskName $taskName).State -eq 'Running') {
        if ([DateTime]::UtcNow -ge $deadline) { throw 'The background task did not stop.' }
        Start-Sleep -Milliseconds 250
    }
    Unregister-ScheduledTask -TaskName $taskName -Confirm:$false
}
$installDirectory = [IO.Path]::GetFullPath((Join-Path $env:ProgramFiles 'PCLMemoryScheduler'))
if ((Split-Path -Leaf $installDirectory) -ne 'PCLMemoryScheduler' -or
    (Split-Path -Parent $installDirectory) -ne [IO.Path]::GetFullPath($env:ProgramFiles)) {
    throw 'Unexpected installation directory.'
}
if (Test-Path -LiteralPath $installDirectory) {
    Remove-Item -LiteralPath $installDirectory -Recurse -Force
}
# Preserve the run history in ProgramData for inspection.
