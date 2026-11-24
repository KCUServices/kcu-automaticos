# Estado das maquinas da casa (de 10 em 10 min, escondido).
# Le a lista em maquinas.json (copia maquinas.exemplo.json e edita). Para cada maquina:
#   - esta ligada?  "host" (responde ao ping?) e/ou "porta" (a porta TCP do host aceita ligacao?)
#   - atualizacoes pendentes (so de 6 em 6 h, ou ja com -Completo), conforme "atualizacoes":
#       "windows"  este PC (Windows Update, so leitura: nao instala nada)
#       "apt"      Debian/Ubuntu/Proxmox por SSH   ("ssh": "utilizador@host")
#       "macos"    Mac por SSH (softwareupdate -l)
#       "comando"  um comando teu por SSH que escreve UMA linha por atualizacao pendente ("comando": "...")
# Escreve estado.json e estado.html ao lado deste script. Avisa no Discord quando uma maquina cai ou volta
# e quando aparecem atualizacoes criticas novas.
# Uso: estado_maquinas.ps1 [-Completo] [-HorasAtualizacoes 6] [-Ensaio]
#   -Ensaio  faz as verificacoes e mostra o resultado, mas nao escreve ficheiros nem avisa no Discord.
# O SSH tem de entrar sem password (chave em ~\.ssh). Testa antes a mao: ssh utilizador@host echo ok
param([switch]$Completo, [int]$HorasAtualizacoes = 6, [switch]$Ensaio)
$ErrorActionPreference = 'Continue'
$dir = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path $dir '..\comum\discord.ps1')
$log = Join-Path $dir 'estado_maquinas.log'
$cfg = Join-Path $dir 'maquinas.json'
$saidaJson = Join-Path $dir 'estado.json'
$saidaHtml = Join-Path $dir 'estado.html'
function Log($m) { $l = "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') $(if ($Ensaio) { '[ensaio] ' })$m"; if ($Ensaio) { Write-Host $l } else { $l | Out-File $log -Append -Encoding utf8 } }

if (-not (Test-Path $cfg)) {
    if ($Ensaio) { $cfg = Join-Path $dir 'maquinas.exemplo.json'; Log 'sem maquinas.json: a usar o exemplo' }
    else { Log 'falta maquinas.json (copia maquinas.exemplo.json)'; exit 1 }
}
$maquinas = @((Get-Content $cfg -Raw | ConvertFrom-Json))   # parenteses: no PS 5.1 o array vem num so objeto
$ssh = @('-o', 'BatchMode=yes', '-o', 'ConnectTimeout=10')

# Estado anterior: para saber o que mudou e para guardar as atualizacoes entre verificacoes completas
$antes = @{}
if (Test-Path $saidaJson) { try { foreach ($m in (Get-Content $saidaJson -Raw | ConvertFrom-Json).maquinas) { $antes[$m.nome] = $m } } catch { } }

function Ping-Host([string]$h) {
    try { return ((New-Object Net.NetworkInformation.Ping).Send($h, 2000).Status -eq 'Success') } catch { return $false }
}
function Porta-Aberta([string]$h, [int]$p) {
    $c = New-Object Net.Sockets.TcpClient
    try { $t = $c.ConnectAsync($h, $p); return ($t.Wait(3000) -and $c.Connected) } catch { return $false } finally { $c.Close() }
}
function Resultado($lista, $criticas, $erro) {
    [ordered]@{ quando = (Get-Date).ToString('o'); pendentes = @($lista).Count; criticas = @($criticas).Count
        lista = @($lista | Select-Object -First 30); erro = $erro }
}
function Atualizacoes($m) {
    switch ($m.atualizacoes) {
        'windows' {
            try {
                $r = (New-Object -ComObject Microsoft.Update.Session).CreateUpdateSearcher().Search("IsInstalled=0 and IsHidden=0 and Type='Software'")
                $u = @($r.Updates)
                return Resultado ($u | ForEach-Object { $_.Title }) ($u | Where-Object { $_.MsrcSeverity -in 'Critical', 'Important' }) $null
            } catch { return Resultado @() @() "Windows Update: $($_.Exception.Message)" }
        }
        'apt' {
            # apt-get update so funciona como root; sem root, usa a lista que o sistema ja tem
            # (sem aspas duplas: o PowerShell 5.1 estraga-as ao passar argumentos ao ssh.exe)
            $out = & ssh @ssh $m.ssh 'if [ $(id -u) -eq 0 ]; then apt-get update -qq >/dev/null 2>&1; fi; apt list --upgradable 2>/dev/null | grep -v ^Listing; echo FIM-OK' 2>$null
            if (-not ($out -contains 'FIM-OK')) { return Resultado @() @() 'sem ligacao SSH' }
            $pk = @($out | Where-Object { $_ -match '/' })
            return Resultado ($pk | ForEach-Object { ($_ -split '/')[0] }) ($pk | Where-Object { $_ -match '-security' }) $null
        }
        'macos' {
            $out = & ssh @ssh $m.ssh 'softwareupdate -l 2>&1; echo FIM-OK' 2>$null
            if (-not ($out -contains 'FIM-OK')) { return Resultado @() @() 'sem ligacao SSH' }
            $it = @($out | Where-Object { $_ -match '^\s*\* Label:' } | ForEach-Object { ($_ -replace '^\s*\* Label:\s*', '').Trim() })
            return Resultado $it ($it | Where-Object { $_ -match 'Security|Seguran' }) $null
        }
        'comando' {
            $out = & ssh @ssh $m.ssh "$($m.comando); echo FIM-OK" 2>$null
            if (-not ($out -contains 'FIM-OK')) { return Resultado @() @() 'sem ligacao SSH' }
            $it = @($out | Where-Object { $_ -and $_ -ne 'FIM-OK' } | ForEach-Object { "$_".Trim() })
            return Resultado $it @() $null
        }
        default { return $null }
    }
}

$agora = Get-Date
$avisos = @()
$resultado = foreach ($m in $maquinas) {
    $a = $antes[$m.nome]
    $ping = if ($m.host) { Ping-Host $m.host } else { $null }
    $alvo = if ($m.host) { [string]$m.host } else { '127.0.0.1' }
    $porta = if ($m.porta) { Porta-Aberta -h $alvo -p ([int]$m.porta) } else { $null }
    # Ligada: se tem porta, conta a porta (ha redes que bloqueiam o ping); senao o ping; sem nada = este PC
    $ligada = if ($null -ne $porta) { $porta } elseif ($null -ne $ping) { $ping } else { $true }

    # Atualizacoes: reaproveita as da ultima vez, a nao ser que ja tenham passado as horas ou venha -Completo
    $upd = if ($a) { $a.atualizacoes } else { $null }
    $ultima = if ($upd -and $upd.quando) { [datetime]$upd.quando } else { [datetime]::MinValue }
    if ($m.atualizacoes -and $ligada -and ($Completo -or ($agora - $ultima).TotalHours -ge $HorasAtualizacoes)) {
        if ($Ensaio -and -not $Completo) { Log "$($m.nome): procurava atualizacoes ($($m.atualizacoes)) - usa -Completo para ver" }
        else {
            Log "$($m.nome): a procurar atualizacoes ($($m.atualizacoes))..."
            $novo = Atualizacoes $m
            if ($novo) {
                $critAntes = if ($upd) { [int]$upd.criticas } else { 0 }
                if ($novo.criticas -gt $critAntes) { $avisos += "$($m.nome): $($novo.criticas) atualizacoes criticas/de seguranca por instalar" }
                $upd = $novo
            }
        }
    }

    $visto = if ($ligada) { $agora.ToString('o') } elseif ($a) { $a.visto } else { $null }
    if ($a -and $null -ne $a.ligada -and [bool]$a.ligada -ne [bool]$ligada) {
        $avisos += if ($ligada) { "$($m.nome) voltou" } else { "$($m.nome) deixou de responder" }
    }
    $txtUpd = if ($upd) { if ($upd.erro) { " | atualizacoes: $($upd.erro)" } else { " | $($upd.pendentes) atualizacoes ($($upd.criticas) criticas)" } } else { '' }
    Log ("{0}: {1}{2}" -f $m.nome, $(if ($ligada) { 'ligada' } else { 'DESLIGADA' }), $txtUpd)
    [ordered]@{ nome = $m.nome; ligada = $ligada; ping = $ping; porta = $porta; visto = $visto; atualizacoes = $upd }
}
$estado = [ordered]@{ gerado = $agora.ToString('o'); maquinas = @($resultado) }

# ---- pagina HTML simples (abre-a no browser; atualiza-se sozinha de 5 em 5 min)
function Esc($t) { [Net.WebUtility]::HtmlEncode([string]$t) }
$linhas = foreach ($r in $estado.maquinas) {
    $u = $r.atualizacoes
    $tu = if (-not $u) { '&mdash;' } elseif ($u.erro) { "<span class=mal>$(Esc $u.erro)</span>" }
          elseif ($u.pendentes -eq 0) { '<span class=ok>em dia</span>' }
          else { "<details><summary>$($u.pendentes) pendentes" + $(if ($u.criticas) { " <span class=mal>($($u.criticas) cr&iacute;ticas)</span>" }) + '</summary><ul>' + (($u.lista | ForEach-Object { "<li>$(Esc $_)</li>" }) -join '') + '</ul></details>' }
    $quando = if ($u -and $u.quando) { ([datetime]$u.quando).ToString('dd/MM HH:mm') } else { '' }
    $visto = if ($r.visto) { ([datetime]$r.visto).ToString('dd/MM HH:mm') } else { 'nunca' }
    "<tr><td><span class='luz $(if ($r.ligada) { 'l-ok' } else { 'l-mal' })'></span>$(Esc $r.nome)</td><td>$(if ($r.ligada) { 'ligada' } else { "desligada<br><small>visto: $visto</small>" })</td><td>$tu<br><small>$quando</small></td></tr>"
}
$html = @"
<!doctype html><html lang="pt"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<meta http-equiv="refresh" content="300"><title>Estado das m&aacute;quinas</title><style>
:root{--fundo:#f6f7f9;--cartao:#fff;--texto:#1d2330;--cinza:#6b7280;--ok:#15803d;--mal:#b91c1c;--linha:#e5e7eb}
@media (prefers-color-scheme:dark){:root{--fundo:#12151b;--cartao:#1b1f27;--texto:#e7e9ee;--cinza:#9aa1ad;--ok:#4ade80;--mal:#f87171;--linha:#2a2f3a}}
body{margin:0;padding:24px 16px;background:var(--fundo);color:var(--texto);font:15px/1.5 system-ui,sans-serif}
main{max-width:860px;margin:0 auto}h1{font-size:22px;margin:0 0 4px}p{color:var(--cinza);margin:0 0 16px}
table{width:100%;border-collapse:collapse;background:var(--cartao);border-radius:10px;overflow:hidden}
td,th{padding:10px 12px;border-bottom:1px solid var(--linha);text-align:left;vertical-align:top}th{color:var(--cinza);font-weight:600;font-size:13px}
.luz{display:inline-block;width:10px;height:10px;border-radius:50%;margin-right:8px}.l-ok{background:var(--ok)}.l-mal{background:var(--mal)}
.ok{color:var(--ok)}.mal{color:var(--mal)}small{color:var(--cinza)}ul{margin:6px 0;padding-left:18px}summary{cursor:pointer}
</style></head><body><main><h1>Estado das m&aacute;quinas</h1><p>Atualizado a $($agora.ToString('dd/MM/yyyy HH:mm'))</p>
<table><tr><th>M&aacute;quina</th><th>Estado</th><th>Atualiza&ccedil;&otilde;es</th></tr>
$($linhas -join "`n")
</table></main></body></html>
"@

if ($Ensaio) {
    Log "faria estado.json e estado.html com $(@($estado.maquinas).Count) maquinas"
    foreach ($t in $avisos) { Log "avisaria no Discord: $t" }
    return
}
$utf8 = New-Object Text.UTF8Encoding $false
[IO.File]::WriteAllText($saidaJson, ($estado | ConvertTo-Json -Depth 5), $utf8)
[IO.File]::WriteAllText($saidaHtml, $html, $utf8)
if ($avisos.Count) { Enviar-Discord ($avisos -join "`n") "Estado ($env:COMPUTERNAME)" | Out-Null; $avisos | ForEach-Object { Log "aviso: $_" } }
if ((Test-Path $log) -and (Get-Item $log).Length -gt 100KB) { Get-Content $log -Tail 300 | Set-Content $log -Encoding utf8 }
