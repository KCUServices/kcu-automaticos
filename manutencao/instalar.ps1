# Corre UMA vez como ADMINISTRADOR. Cria as duas tarefas da manutencao:
#   "\KCU\Manutencao diaria"   todos os dias as 13:30   -> manutencao.ps1 -Diaria
#   "\KCU\Manutencao semanal"  domingo as 14:00         -> manutencao.ps1 -Semanal
#   powershell -ExecutionPolicy Bypass -File instalar.ps1 [-HoraDiaria 13:30] [-HoraSemanal 14:00]
#   powershell -ExecutionPolicy Bypass -File instalar.ps1 -Remover
# Testar sem apagar nada:  powershell -File manutencao.ps1 -Semanal -Ensaio
param([string]$HoraDiaria = '13:30', [string]$HoraSemanal = '14:00', [switch]$Remover)
. (Join-Path $PSScriptRoot '..\comum\tarefa.ps1')
if (-not (Test-Admin)) { 'Corre isto como administrador.'; exit 1 }
if ($Remover) { Remover-Tarefa 'Manutencao diaria'; Remover-Tarefa 'Manutencao semanal'; exit 0 }
Registar-Tarefa -Nome 'Manutencao diaria' -Script (Join-Path $PSScriptRoot 'manutencao_diaria.ps1') `
    -Gatilho (New-ScheduledTaskTrigger -Daily -At $HoraDiaria) -LimiteMin 120 -Descricao 'Limpeza leve de temporarios.'
Registar-Tarefa -Nome 'Manutencao semanal' -Script (Join-Path $PSScriptRoot 'manutencao_semanal.ps1') `
    -Gatilho (New-ScheduledTaskTrigger -Weekly -DaysOfWeek Sunday -At $HoraSemanal) -LimiteMin 120 -Descricao 'Limpeza completa e saude dos discos.'
