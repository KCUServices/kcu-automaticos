# Ajuda partilhada pelos instaladores: cria uma tarefa agendada escondida na pasta "\KCU\" do Agendador.
function Test-Admin { ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator) }
function Registar-Tarefa {
    param([string]$Nome, [string]$Script, $Gatilho, [int]$LimiteMin = 10, [string]$Descricao = '', [switch]$SoSeParado)
    $vbs = Join-Path $PSScriptRoot 'iniciar_oculto.vbs'   # $PSScriptRoot aqui = a pasta "comum"
    $acao = New-ScheduledTaskAction -Execute 'wscript.exe' -Argument ('//B //Nologo "{0}" "{1}"' -f $vbs, $Script)
    $def = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable `
        -ExecutionTimeLimit (New-TimeSpan -Minutes $LimiteMin) -MultipleInstances IgnoreNew
    $quem = New-ScheduledTaskPrincipal -UserId "$env:USERDOMAIN\$env:USERNAME" -LogonType Interactive -RunLevel Highest
    Register-ScheduledTask -TaskName $Nome -TaskPath '\KCU\' -Action $acao -Trigger $Gatilho -Settings $def `
        -Principal $quem -Force -Description $Descricao | Out-Null
    "Tarefa '$Nome' criada. Proxima corrida: " + (Get-ScheduledTaskInfo -TaskPath '\KCU\' -TaskName $Nome).NextRunTime
}
function Remover-Tarefa([string]$Nome) {
    Unregister-ScheduledTask -TaskPath '\KCU\' -TaskName $Nome -Confirm:$false -ErrorAction SilentlyContinue
    "Tarefa '$Nome' removida."
}
