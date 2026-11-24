# Acorda outro PC da rede de casa por Wake-on-LAN e espera que ele responda.
#   powershell -ExecutionPolicy Bypass -File acordar.ps1 -Mac AA:BB:CC:DD:EE:FF -Ip 192.168.1.50
# Requisitos no PC a acordar: Wake-on-LAN ligado na BIOS e na placa de rede (Gestor de Dispositivos >
# placa de rede > Gestao de energia > "Permitir que este dispositivo acorde o computador" + "Wake on Magic Packet").
# So funciona a partir de um aparelho ligado a mesma rede (o pacote e de difusao).
param([Parameter(Mandatory)][string]$Mac, [Parameter(Mandatory)][string]$Ip, [int]$EsperaSeg = 120)
$bytes = $Mac -split '[:-]' | ForEach-Object { [byte]("0x$_") }
if ($bytes.Count -ne 6) { 'MAC invalido.'; exit 1 }
$pacote = [byte[]](,0xFF * 6) + ($bytes * 16)
$prefixo = ($Ip -split '\.')[0..2] -join '.'
$local = (Get-NetIPAddress -AddressFamily IPv4 | Where-Object { $_.IPAddress -like "$prefixo.*" } | Select-Object -First 1).IPAddress
if (-not $local) { "Este PC nao esta na rede $prefixo.x."; exit 1 }
foreach ($destino in "$prefixo.255", '255.255.255.255') {
    foreach ($porta in 9, 7) {
        $u = New-Object System.Net.Sockets.UdpClient([System.Net.IPEndPoint]::new([System.Net.IPAddress]::Parse($local), 0))
        $u.EnableBroadcast = $true
        1..3 | ForEach-Object { [void]$u.Send($pacote, $pacote.Length, $destino, $porta) }
        $u.Close()
    }
}
"Sinal enviado. A esperar que o PC responda (ate $EsperaSeg s)..."
foreach ($i in 1..([math]::Ceiling($EsperaSeg / 5))) {
    Start-Sleep -Seconds 5
    if (Test-Connection $Ip -Count 1 -Quiet -ErrorAction SilentlyContinue) { "PC ligado ($($i * 5) s)."; exit 0 }
}
"Sem resposta em $EsperaSeg s."
exit 1
