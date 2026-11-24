# Limpeza COMPLETA de pastas temporarias, a pedido: apaga tudo o que nao esta em uso, sem limite de dias.
#   limpar_temp_completo.ps1 [-Pastas <lista>] [-Excluir <nomes de pasta do 1.o nivel>] [-Ensaio]
# Por omissao limpa a pasta TEMP do utilizador. Nunca segue ligacoes; o que estiver aberto por um programa fica.
# Seguranca: recusa qualquer pasta cujo caminho nao tenha "\temp\" ou "\tmp\".
param([string[]]$Pastas, [string[]]$Excluir = @('claude'), [switch]$Ensaio)
try { (Get-Process -Id $PID).PriorityClass = 'Idle' } catch { }
if (-not $Pastas) { $Pastas = @([Environment]::GetEnvironmentVariable('TEMP', 'User')) }
foreach ($raiz in $Pastas) {
    if (-not $raiz -or -not (Test-Path -LiteralPath $raiz)) { "nao existe: $raiz"; continue }
    if ($raiz.Length -lt 8 -or $raiz -notmatch '(?i)\\te?mp(\\|$)') { "RECUSADO (nao parece uma pasta temporaria): $raiz"; continue }
    $t0 = Get-Date; $n = 0; $b = 0L; $ficam = 0
    $pilha = New-Object System.Collections.Generic.Stack[string]; $dirs = New-Object System.Collections.Generic.List[string]
    try { foreach ($x in [IO.Directory]::EnumerateFileSystemEntries($raiz)) { if ($Excluir -contains (Split-Path $x -Leaf)) { continue }; $pilha.Push($x) } } catch { }
    while ($pilha.Count) {
        $x = $pilha.Pop()
        try {
            $a = [IO.File]::GetAttributes($x)
            if ($a -band [IO.FileAttributes]::ReparsePoint) { if (-not $Ensaio) { if ($a -band [IO.FileAttributes]::Directory) { [IO.Directory]::Delete($x, $false) } else { [IO.File]::Delete($x) } }; continue }
            if ($a -band [IO.FileAttributes]::Directory) { $dirs.Add($x); foreach ($y in [IO.Directory]::EnumerateFileSystemEntries($x)) { $pilha.Push($y) }; continue }
            $tam = (New-Object IO.FileInfo $x).Length
            if (-not $Ensaio) { if ($a -band [IO.FileAttributes]::ReadOnly) { [IO.File]::SetAttributes($x, 'Normal') }; [IO.File]::Delete($x) }
            $n++; $b += $tam
        } catch { $ficam++ }
    }
    if (-not $Ensaio) { $dirs.Sort(); for ($i = $dirs.Count - 1; $i -ge 0; $i--) { try { [IO.Directory]::Delete($dirs[$i], $false) } catch { } } }
    $resto = 0; try { $resto = @([IO.Directory]::EnumerateFileSystemEntries($raiz)).Count } catch { }
    "{0}{1}: {2} ficheiros apagados, {3:N0} MB, {4} em uso ficaram, {5} entradas no 1.o nivel agora ({6:N0} s)" -f $(if ($Ensaio) { '[ENSAIO] ' }), $raiz, $n, ($b / 1MB), $ficam, $resto, ((Get-Date) - $t0).TotalSeconds
}
