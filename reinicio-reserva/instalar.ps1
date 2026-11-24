# Corre UMA vez como ADMINISTRADOR. Cria a tarefa "\KCU\Reinicio de reserva":
# reinicia o PC todos os dias a hora escolhida (05:00), SO se ninguem o usou nos ultimos 30 min
# (espera ate 1 h por isso; se nao, salta esse dia). Mostra um aviso de 2 min; cancelar com:  shutdown /a
# Util para PCs que ficam ligados dias seguidos (por exemplo, quando o desligar noturno desistiu).
#   powershell -ExecutionPolicy Bypass -File instalar.ps1 [-Hora 05:00]
#   powershell -ExecutionPolicy Bypass -File instalar.ps1 -Remover
param([string]$Hora = '05:00', [switch]$Remover)
. (Join-Path $PSScriptRoot '..\comum\tarefa.ps1')
if (-not (Test-Admin)) { 'Corre isto como administrador.'; exit 1 }
if ($Remover) { Remover-Tarefa 'Reinicio de reserva'; exit 0 }
$acao = New-ScheduledTaskAction -Execute 'shutdown.exe' -Argument '/r /t 120 /c "Reinicio automatico. Para cancelar: shutdown /a"'
$def = New-ScheduledTaskSettingsSet -RunOnlyIfIdle -IdleDuration (New-TimeSpan -Minutes 30) -IdleWaitTimeout (New-TimeSpan -Hours 1) `
    -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -ExecutionTimeLimit (New-TimeSpan -Minutes 10) -MultipleInstances IgnoreNew
$def.IdleSettings.StopOnIdleEnd = $false   # depois de comecar, nao desiste por alguem mexer no rato
$quem = New-ScheduledTaskPrincipal -UserId "$env:USERDOMAIN\$env:USERNAME" -LogonType Interactive -RunLevel Highest
Register-ScheduledTask -TaskName 'Reinicio de reserva' -TaskPath '\KCU\' -Action $acao -Trigger (New-ScheduledTaskTrigger -Daily -At $Hora) `
    -Settings $def -Principal $quem -Force -Description 'Reinicia o PC se estiver parado ha 30 min.' | Out-Null
"Tarefa criada. Proxima corrida: " + (Get-ScheduledTaskInfo -TaskPath '\KCU\' -TaskName 'Reinicio de reserva').NextRunTime
