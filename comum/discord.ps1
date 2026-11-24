# Envia um aviso para um canal do Discord (webhook). Usado pelos outros scripts.
# O endereco do webhook NUNCA fica no codigo: vai na variavel de ambiente do utilizador KCU_DISCORD_WEBHOOK.
#   [Environment]::SetEnvironmentVariable('KCU_DISCORD_WEBHOOK', 'https://discord.com/api/webhooks/...', 'User')
# Sem a variavel, os avisos sao simplesmente ignorados.
function Enviar-Discord([string]$Texto, [string]$Nome = 'KCU Automaticos') {
    $url = [Environment]::GetEnvironmentVariable('KCU_DISCORD_WEBHOOK', 'User')
    if (-not $url) { return $false }
    $corpo = @{ content = $Texto; username = $Nome; allowed_mentions = @{ parse = @() } } | ConvertTo-Json -Compress
    try {
        Invoke-RestMethod $url -Method Post -ContentType 'application/json; charset=utf-8' -Body ([Text.Encoding]::UTF8.GetBytes($corpo)) -TimeoutSec 20 | Out-Null
        return $true
    } catch { return $false }
}
