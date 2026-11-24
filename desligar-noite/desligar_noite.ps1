# Desligar noturno: o PC desliga-se de madrugada e a BIOS liga-o de manha (ver README: "ligar pela BIOS").
# Corre numa tarefa agendada (por omissao a 01:00). Antes de desligar confirma que nada esta a meio; se estiver,
# volta a ver de 15 em 15 min e desiste a hora limite (por omissao 03:00), avisando no Discord.
# NAO desliga se:
#   - alguem mexeu no rato/teclado nos ultimos 20 min;
#   - a placa grafica (NVIDIA) ou o processador estao ocupados (jogo, render, IA);
#   - o Claude Code esta a trabalhar;
#   - um dos processos da lista $Proteger esta aberto (edita a lista abaixo);
#   - existe o ficheiro "nao_desligar.txt" ao lado deste script (vale so para essa noite).
# Uso: desligar_noite.ps1 [-HoraLimite 3] [-Ensaio]   (-Ensaio: so diz o que faria; nao espera nem desliga)
# Ficheiro so com ASCII: o PowerShell 5.1 le os .ps1 sem BOM como ANSI.
param([int]$HoraLimite = 3, [switch]$Ensaio)
$ErrorActionPreference = 'Continue'

# >>> Programas que impedem o desligar enquanto estiverem abertos (nome do processo, sem .exe). Edita a gosto.
$Proteger = @('obs64', 'Resolve', 'HandBrake')

$aqui = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path $aqui '..\comum\discord.ps1')
$log = Join-Path $aqui 'desligar_noite.log'
$naoDesligar = Join-Path $aqui 'nao_desligar.txt'
$limite = (Get-Date).Date.AddHours($HoraLimite)
if ((Get-Date) -ge $limite) { $limite = $limite.AddDays(1) }

function Log($m) { $l = "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') $(if ($Ensaio) { '[ensaio] ' })$m"; $l; if (-not $Ensaio) { $l | Out-File $log -Append -Encoding utf8 } }

Add-Type -Namespace KCU -Name Inativo -MemberDefinition @'
[StructLayout(LayoutKind.Sequential)] public struct LASTINPUTINFO { public uint cbSize; public uint dwTime; }
[DllImport("user32.dll")] static extern bool GetLastInputInfo(ref LASTINPUTINFO p);
public static uint Minutos() { var i = new LASTINPUTINFO(); i.cbSize = (uint)System.Runtime.InteropServices.Marshal.SizeOf(i); GetLastInputInfo(ref i); return (uint)((System.Environment.TickCount - (int)i.dwTime) / 60000); }
'@ -ErrorAction SilentlyContinue

function Ocupado {
    $motivos = @()
    if (Test-Path $naoDesligar) { $motivos += 'existe nao_desligar.txt' }
    $inativo = [KCU.Inativo]::Minutos()
    if ($inativo -lt 20) { $motivos += "rato/teclado usados ha $inativo min" }
    $smi = Get-Command nvidia-smi -ErrorAction SilentlyContinue
    if ($smi) {
        $g = 1..3 | ForEach-Object { [int]((& $smi.Source --query-gpu=utilization.gpu --format=csv,noheader,nounits) | Select-Object -First 1); Start-Sleep 2 }
        $media = [int](($g | Measure-Object -Average).Average)
        if ($media -ge 30) { $motivos += "placa grafica a $media%" }
    }
    $cpu = [int]((Get-Counter '\Processor(_Total)\% Processor Time' -SampleInterval 2 -MaxSamples 3 -ErrorAction SilentlyContinue).CounterSamples.CookedValue | Measure-Object -Average).Average
    if ($cpu -ge 40) { $motivos += "processador a $cpu%" }
    foreach ($p in $Proteger) { if (Get-Process $p -ErrorAction SilentlyContinue) { $motivos += "$p esta aberto" } }
    # Claude Code: mais de 3 s de processador em 20 s nos processos claude = uma sessao a trabalhar
    $antes = (Get-Process claude -ErrorAction SilentlyContinue | Measure-Object CPU -Sum).Sum
    Start-Sleep 20
    $depois = (Get-Process claude -ErrorAction SilentlyContinue | Measure-Object CPU -Sum).Sum
    if ($antes -ne $null -and $depois -ne $null -and ($depois - $antes) -gt 3) { $motivos += 'o Claude Code esta a trabalhar' }
    return $motivos
}

Log "inicio (limite $($limite.ToString('dd/MM HH:mm')))"
while ($true) {
    $m = @(Ocupado)
    if ($m.Count -eq 0) { break }
    if ($Ensaio) { Log ("ocupado: " + ($m -join '; ') + " (a serio voltava a ver daqui a 15 min)"); return }
    if ((Get-Date).AddMinutes(15) -gt $limite) {
        Log ("desisto por hoje: " + ($m -join '; '))
        Enviar-Discord ("O $env:COMPUTERNAME nao se desligou esta noite porque estava ocupado (" + ($m -join '; ') + ").") 'Desligar noturno' | Out-Null
        if (Test-Path $naoDesligar) { Remove-Item $naoDesligar -ErrorAction SilentlyContinue; Log 'nao_desligar.txt apagado (valia so para esta noite)' }
        return
    }
    Log ("ocupado: " + ($m -join '; ') + "; volto a ver daqui a 15 min")
    Start-Sleep 900
}

if ($Ensaio) { Log 'livre: a serio desligava agora'; return }
Log 'livre: a desligar'
shutdown.exe /s /t 60 /c "Desligar noturno. Para cancelar: shutdown /a"
if ((Test-Path $log) -and (Get-Item $log).Length -gt 100KB) { Get-Content $log -Tail 300 | Set-Content $log -Encoding utf8 }
