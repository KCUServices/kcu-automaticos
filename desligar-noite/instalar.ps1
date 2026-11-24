# Corre UMA vez como ADMINISTRADOR. Cria a tarefa "\KCU\Desligar noite" (todos os dias a hora escolhida).
#   powershell -ExecutionPolicy Bypass -File instalar.ps1 [-Hora 01:00]
#   powershell -ExecutionPolicy Bypass -File instalar.ps1 -Remover
# Testar sem desligar nada:  powershell -File desligar_noite.ps1 -Ensaio
# Para o PC voltar a ligar sozinho de manha, ativa na BIOS "RTC Alarm" / "Power On By RTC" (ver README).
param([string]$Hora = '01:00', [switch]$Remover)
. (Join-Path $PSScriptRoot '..\comum\tarefa.ps1')
if (-not (Test-Admin)) { 'Corre isto como administrador.'; exit 1 }
if ($Remover) { Remover-Tarefa 'Desligar noite'; exit 0 }
Registar-Tarefa -Nome 'Desligar noite' -Script (Join-Path $PSScriptRoot 'desligar_noite.ps1') `
    -Gatilho (New-ScheduledTaskTrigger -Daily -At $Hora) -LimiteMin 180 `
    -Descricao 'Desliga o PC de madrugada se ninguem o estiver a usar.'
