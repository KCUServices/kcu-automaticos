# Corre UMA vez como ADMINISTRADOR. Cria a tarefa "\KCU\Sensores" (de 5 em 5 min, escondida).
# Antes: poe o LibreHardwareMonitorLib.dll (versao net472, e os .dll que vem com ele) em sensores\lhm e instala o smartmontools.
# Opcional: copia limites.exemplo.json para limites.json e muda os limites.
#   powershell -ExecutionPolicy Bypass -File instalar.ps1            instala
#   powershell -ExecutionPolicy Bypass -File instalar.ps1 -Remover   remove
# Testar sem escrever nada:  powershell -File sensores.ps1 -Ensaio   (como administrador)
param([switch]$Remover)
. (Join-Path $PSScriptRoot '..\comum\tarefa.ps1')
if (-not (Test-Admin)) { 'Corre isto como administrador.'; exit 1 }
if ($Remover) { Remover-Tarefa 'Sensores'; exit 0 }
if (-not (Test-Path (Join-Path $PSScriptRoot 'lhm\LibreHardwareMonitorLib.dll'))) { 'Aviso: falta lhm\LibreHardwareMonitorLib.dll (sem ele nao ha temperaturas).' }
else { Get-ChildItem (Join-Path $PSScriptRoot 'lhm') -File | Unblock-File }  # .dll de um zip da internet: sem isto o Add-Type recusa-os
$g = New-ScheduledTaskTrigger -Once -At ((Get-Date).AddMinutes(2)) -RepetitionInterval (New-TimeSpan -Minutes 5)
Registar-Tarefa -Nome 'Sensores' -Script (Join-Path $PSScriptRoot 'sensores.ps1') -Gatilho $g -LimiteMin 4 `
    -Descricao 'Le as temperaturas e a saude dos discos e avisa quando passam dos limites.'
