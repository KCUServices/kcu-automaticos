# Limpeza inteligente da RAM (de 30 em 30 min, escondida, precisa de administrador).
# Regra (a mesma do ISLC): quando a memoria LIVRE fica abaixo de 1 GB e a lista em espera (cache de ficheiros que o
# Windows guarda "pelo sim pelo nao") passa de 1 GB, esvazia a lista em espera. Seguro: NAO corta a memoria dos
# programas (isso so os torna mais lentos).
# Uso: limpar_ram.ps1 [-LivreMinMB 1024] [-EsperaMinMB 1024] [-Ensaio]
param([int]$LivreMinMB = 1024, [int]$EsperaMinMB = 1024, [switch]$Ensaio)
$dir = Split-Path -Parent $MyInvocation.MyCommand.Path
$log = Join-Path $dir 'limpar_ram.log'
function Log($m) { "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') $m" | Out-File $log -Append -Encoding utf8 }
function Medir {
    $p = Get-CimInstance Win32_PerfFormattedData_PerfOS_Memory
    [pscustomobject]@{
        livre    = [math]::Round([double]$p.FreeAndZeroPageListBytes / 1MB)
        espera   = [math]::Round(([double]$p.StandbyCacheNormalPriorityBytes + [double]$p.StandbyCacheReserveBytes + [double]$p.StandbyCacheCoreBytes) / 1MB)
        disponivel = [int]$p.AvailableMBytes
    }
}
$m = Medir
$precisa = $m.livre -lt $LivreMinMB -and $m.espera -gt $EsperaMinMB
if ($Ensaio) {
    "ENSAIO: livre $($m.livre) MB, em espera $($m.espera) MB, disponivel $($m.disponivel) MB -> " + $(if ($precisa) { 'esvaziaria a lista em espera' } else { 'nada a fazer' })
    return
}
if (-not $precisa) { return }

Add-Type -Language CSharp -TypeDefinition @'
using System; using System.Runtime.InteropServices;
public static class KcuRam {
  [StructLayout(LayoutKind.Sequential)] struct LUID { public uint Low; public int High; }
  [StructLayout(LayoutKind.Sequential)] struct TP { public int Count; public LUID Luid; public int Attr; }
  [DllImport("advapi32.dll", SetLastError=true)] static extern bool OpenProcessToken(IntPtr h, int acc, out IntPtr t);
  [DllImport("advapi32.dll", SetLastError=true)] static extern bool LookupPrivilegeValue(string s, string n, out LUID l);
  [DllImport("advapi32.dll", SetLastError=true)] static extern bool AdjustTokenPrivileges(IntPtr t, bool d, ref TP n, int l, IntPtr p, IntPtr r);
  [DllImport("kernel32.dll")] static extern IntPtr GetCurrentProcess();
  [DllImport("ntdll.dll")] static extern int NtSetSystemInformation(int cls, ref int info, int len);
  public static int PurgeStandby() {
    IntPtr tok; if (!OpenProcessToken(GetCurrentProcess(), 0x28, out tok)) return -1;
    LUID l; if (!LookupPrivilegeValue(null, "SeProfileSingleProcessPrivilege", out l)) return -2;
    TP tp = new TP { Count = 1, Luid = l, Attr = 2 };
    if (!AdjustTokenPrivileges(tok, false, ref tp, 0, IntPtr.Zero, IntPtr.Zero) || Marshal.GetLastWin32Error() != 0) return -3;
    int cmd = 4; // MemoryPurgeStandbyList
    return NtSetSystemInformation(80, ref cmd, 4); // SystemMemoryListInformation
  }
}
'@
$r = [KcuRam]::PurgeStandby()
Start-Sleep 2
$d = Medir
if ($r -eq 0) { Log "livre $($m.livre) MB -> $($d.livre) MB (lista em espera $($m.espera) -> $($d.espera) MB)" }
else { Log "livre $($m.livre) MB: nao consegui esvaziar (codigo $r; a tarefa precisa de privilegios de administrador)" }
if ((Get-Item $log -ErrorAction SilentlyContinue).Length -gt 100KB) { Get-Content $log -Tail 300 | Set-Content $log -Encoding utf8 }
