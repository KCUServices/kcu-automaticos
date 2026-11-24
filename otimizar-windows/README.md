# Otimizar o Windows

Um script que corres **uma vez** (não é uma tarefa agendada) e que só mexe em definições documentadas do Windows 10/11. Tudo o que muda fica guardado em `otimizar_windows.antes.json`, e `-Desfazer` repõe os valores de antes.

**Nunca toca em:** Defender, firewall, UAC, Windows Update (as atualizações continuam a instalar-se), drivers, plano de energia, ficheiros do sistema.

## Como usar

Abre o **PowerShell como administrador, na tua conta** (as definições `HKCU` são da conta que corre o script):

```powershell
cd C:\kcu-automaticos\otimizar-windows
powershell -ExecutionPolicy Bypass -File otimizar_windows.ps1 -Ensaio              # mostra o que mudaria, sem mudar nada
powershell -ExecutionPolicy Bypass -File otimizar_windows.ps1                      # pergunta grupo a grupo (1 a 5)
powershell -ExecutionPolicy Bypass -File otimizar_windows.ps1 -Tudo                # grupos 1 a 5 sem perguntar
powershell -ExecutionPolicy Bypass -File otimizar_windows.ps1 -Jogos -LimitarWSL   # junta grupos opcionais
powershell -ExecutionPolicy Bypass -File otimizar_windows.ps1 -Desfazer            # volta tudo atrás
```

O `-Ensaio` mostra cada definição com o valor atual e o novo (`0 -> 1`) e diz quais já estão como deve ser. Depois de aplicar ou desfazer, **reinicia o PC**.

## Grupos base (1 a 5)

| # | O que faz | Como | Desfazer à mão |
|---|---|---|---|
| 1 | **Telemetria no mínimo.** Envia só os dados de diagnóstico obrigatórios. | Política `HKLM\SOFTWARE\Policies\Microsoft\Windows\DataCollection` → `AllowTelemetry = 1`. Serviço `DiagTrack` (Experiências de Utilizador Ligado e Telemetria) desativado. Tarefas `Consolidator` e `UsbCeip` (Programa de Melhoria da Experiência do Cliente) e `Microsoft-Windows-DiskDiagnosticDataCollector` desativadas. | Apaga o valor `AllowTelemetry`; em `services.msc` põe o `DiagTrack` em Automático; no Agendador de Tarefas reativa as três tarefas. |
| 2 | **Sem publicidade nem sugestões.** Tira widgets, botão do Copilot, recomendações no Iniciar, anúncios no Explorador, destaques da pesquisa, ID de publicidade, "experiências personalizadas", pedidos de feedback, o ecrã "vamos terminar de configurar", apps instaladas sem pedir, dicas e sugestões nas Definições e curiosidades no ecrã de bloqueio. | Valores em `HKCU\...\Explorer\Advanced` (`TaskbarDa`, `ShowCopilotButton`, `Start_IrisRecommendations`, `ShowSyncProviderNotifications`), `SearchSettings\IsDynamicSearchBoxEnabled`, `AdvertisingInfo\Enabled`, `Privacy\TailoredExperiencesWithDiagnosticDataEnabled`, `Siuf\Rules\NumberOfSIUFInPeriod`, `UserProfileEngagement\ScoobeSystemSettingEnabled` e `ContentDeliveryManager` (`SilentInstalledAppsEnabled`, `SystemPaneSuggestionsEnabled`, `SoftLandingEnabled`, `SubscribedContent-*Enabled`, `RotatingLockScreenOverlayEnabled`), todos a `0`. | Quase tudo se liga outra vez em **Definições → Personalização** (Barra de tarefas, Iniciar, Ecrã de bloqueio) e **Privacidade e segurança → Geral**. Ou `-Desfazer`. |
| 3 | **Atualizações só da Microsoft.** O Windows deixa de enviar e receber pedaços de atualizações de outros PCs. Poupa upload. | Política `HKLM\SOFTWARE\Policies\Microsoft\Windows\DeliveryOptimization` → `DODownloadMode = 0`. | Apaga o valor `DODownloadMode`. |
| 4 | **Edge não fica a correr** depois de fechado nem pré-carrega no arranque. O Edge passa a dizer "gerido pela tua organização": é normal, é uma política. | Políticas `HKLM\SOFTWARE\Policies\Microsoft\Edge` → `StartupBoostEnabled = 0` e `BackgroundModeEnabled = 0`. | Apaga os dois valores (ou a chave `Edge`, se estiver vazia). |
| 5 | **Limpeza automática semanal** (Sensor de Armazenamento): ficheiros temporários e reciclagem com mais de 30 dias. A pasta Transferências **nunca** é tocada. | `HKCU\...\StorageSense\Parameters\StoragePolicy`: `01=1` (ligado), `2048=7` (semanal), `04=1` (temporários), `08=1` e `256=30` (reciclagem, 30 dias), `32=0` (Transferências não). | **Definições → Sistema → Armazenamento → Sensor de Armazenamento** → desligar. |

## Grupos opcionais (só com o interruptor)

| Interruptor | O que faz | Desfazer à mão |
|---|---|---|
| `-ServicosExtra` | Desativa serviços que quase ninguém usa: `MapsBroker` (mapas offline), `RetailDemo` (modo de demonstração de loja), `Fax`, `WMPNetworkSvc` (partilha de rede do Windows Media Player) e as tarefas `MapsToastTask`/`MapsUpdateTask`. O ganho é pequeno: arrancam pouco. | `services.msc` → põe cada um em Manual; Agendador → reativa as tarefas. |
| `-Jogos` | **Modo de Jogo** automático (`GameBar\AutoGameModeEnabled = 1`); **agendamento de GPU por hardware** (`GraphicsDrivers\HwSchMode = 2`, só vale depois de reiniciar e se a placa e o driver o suportarem); **otimização de jogos em janela** (`SwapEffectUpgradeEnable=1` em `DirectXUserGlobalSettings`, sem apagar outras opções como o HDR automático); **sem gravação em segundo plano da Game Bar** (`GameDVR_Enabled = 0`, `AppCaptureEnabled = 0`). | **Definições → Jogos → Modo de Jogo**; **Sistema → Ecrã → Gráficos → Alterar predefinições** (agendamento de GPU e jogos em janela); **Jogos → Capturas**. |
| `-LimitarWSL [-WslGB 8]` | Cria `%USERPROFILE%\.wslconfig` com `memory=8GB`, para o WSL/Docker não comer a RAM toda. Se o ficheiro já existir, **não lhe mexe**. | Apaga o `.wslconfig` e corre `wsl --shutdown`. |
| `-SemIndexacao` | Desativa o serviço `WSearch` (indexação). Poupa o disco, mas a pesquisa no Explorador, no Iniciar e no Outlook fica mais lenta. | `services.msc` → `Windows Search` em Automático (Arranque Atrasado). |
| `-RemoverApps` | Desinstala, **para a tua conta**, apps de origem: Clipchamp, Notícias, Meteorologia, Bing Search, Solitaire, Hub de Comentários, Dev Home, Office Hub, Cortana, Pessoas, Mapas, Portal de Realidade Mista, Visualizador 3D, Skype. Mostra a lista e pede **sempre** confirmação, mesmo com `-Tudo`. | **Não se desfaz com `-Desfazer`.** Reinstala pela Microsoft Store. |

## O que tirámos da versão que usamos em casa, e porquê

- **Serviço `dmwappushservice` e serviço `InventorySvc`, tarefas `Microsoft Compatibility Appraiser`, `MareBackup` e `StartupAppTask`:** fazem parte da inscrição em MDM e das verificações de compatibilidade que o Windows Update usa antes de oferecer uma nova versão do Windows. Desligá-los pode bloquear atualizações ou a gestão do PC pela empresa.
- **Serviços `PhoneSvc`, `WalletService`, `SEMgrSvc`, `TrkWks`:** já só arrancam quando são precisos e desligá-los pode estragar a Ligação ao Telemóvel, os pagamentos por NFC ou os atalhos que seguem ficheiros movidos. O ganho é quase nenhum.
- **Controlo parental (`WpcMonSvc`, tarefas `FamilySafety*`):** desligá-lo num PC usado por crianças desliga a proteção sem ninguém dar por isso.
- **Desinstalar Teams, Outlook, To Do, Power Automate, Ligação ao Telemóvel e Obter Ajuda:** há quem precise deles (e o Obter Ajuda é usado pelas resoluções de problemas do Windows 11).
- **`VRROptimizeEnable` nos jogos:** depende do monitor; o script já não substitui as tuas opções de DirectX, só acrescenta a dos jogos em janela.
- Tudo o que era só da nossa máquina (pastas e atalhos nossos).

## Cuidados

- Se o Windows recusar uma definição (há versões que protegem algumas, como `TaskbarDa`), o script escreve um aviso e continua.
- O `-Desfazer` repõe o valor **de antes da primeira vez** que correste o script. Se mudaste algo à mão depois, confirma com `-Desfazer -Ensaio`.
- Depois de desfazer, o ficheiro `otimizar_windows.antes.json` fica guardado com a data no nome, por segurança.
