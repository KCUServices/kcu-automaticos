"""Os 7 estados: cada serviço e cada máquina recebe UM, pelas regras abaixo.

Juntam-se os "achados" (estado, motivo) de todas as fontes e ganha o pior, por esta ordem
(o motivo mostrado é o do pior achado):

  OFFLINE     máquina: não responde (ping ou porta do estado-maquinas).
  FAILED      serviço: em baixo sem recuperação automática (não está no vigia-servicos, ou o vigia parou),
              ou o vigia esgotou as tentativas em 24 h; máquina: um disco com SMART falhado.
  DEGRADED    máquina viva mas com uma parte em falha: hardware em alerta (sensores).
  RECOVERING  serviço em baixo com o vigia a tratar dele: tentativa recente (até RECUPERA_MIN), ou à espera
              de confirmar a falha / da próxima tentativa.
  STALE       dados mais velhos do que o limite da fonte (LIMITE_MIN, em minutos).
  WARNING     serviço a responder mas instável (2 ou mais tentativas de recuperação em 24 h); máquina com
              atualizações críticas por instalar ou temperatura perto do limite.
  HEALTHY     nenhum dos anteriores.

Funções puras: só leem os dados que recebem (não abrem ficheiros nem a rede). Autoteste: python estados.py --teste
"""
import re
import sys
from datetime import datetime, timedelta, timezone

ORDEM = ("OFFLINE", "FAILED", "DEGRADED", "RECOVERING", "STALE", "WARNING", "HEALTHY")
ETIQUETAS = {"HEALTHY": "Saudável", "WARNING": "Aviso", "DEGRADED": "Degradado", "FAILED": "Falhou",
             "OFFLINE": "Desligado", "STALE": "Desatualizado", "RECOVERING": "A recuperar"}
LIMITE_MIN = {
    "maquinas": 30,           # o estado-maquinas corre de 10 em 10 min
    "atualizacoes": 14 * 60,  # procura de 6 em 6 h (com folga para o PC desligado à noite)
    "sensores": 15,           # os sensores correm de 5 em 5 min
    "vigia": 20,              # o vigia-servicos corre de 5 em 5 min
}
TENTATIVAS_MAX = 3   # igual a $MaxTentativas do vigia_servicos.ps1
RECUPERA_MIN = 75    # espera mais longa do vigia (60 min) + uma volta (5) + margem


def pior(achados, bem):
    """[(estado, motivo), ...] -> {"estado", "etiqueta", "motivo"}; sem achados = HEALTHY com o motivo `bem`."""
    if not achados:
        return {"estado": "HEALTHY", "etiqueta": ETIQUETAS["HEALTHY"], "motivo": bem}
    e = min((a[0] for a in achados), key=ORDEM.index)
    return {"estado": e, "etiqueta": ETIQUETAS[e], "motivo": "; ".join(m for x, m in achados if x == e)[:300]}


def idade_min(iso, agora=None):
    """Minutos desde uma data ISO (sem fuso = hora local); None se não for data."""
    try:
        # o PowerShell escreve 7 casas nos segundos; o Python antes do 3.11 so aceita 6
        d = datetime.fromisoformat(re.sub(r"(\.\d{6})\d+", r"\1", str(iso)).replace("Z", "+00:00"))
    except ValueError:
        return None
    if not d.tzinfo:
        d = d.astimezone()
    return max(0, int(((agora or datetime.now(timezone.utc)) - d).total_seconds() // 60))


def ha(m):
    if m is None:
        return "a hora desconhecida"
    return "há %d min" % m if m < 120 else "há %d h" % (m // 60) if m < 2880 else "há %d dias" % (m // 1440)


def estado_servico(ok, vigia=None, vigia_min=None, agora=None):
    """ok: a verificação da página respondeu?  vigia: o registo deste serviço no vigia_servicos.estado.json
    ({falhas, tentativas, avisado}) ou None se o vigia não trata dele; vigia_min: idade desse ficheiro em minutos."""
    tent = [m for m in (idade_min(x, agora) for x in (vigia or {}).get("tentativas") or []) if m is not None and m < 24 * 60]
    if ok:
        if len(tent) >= 2:
            return pior([("WARNING", "instável: %d tentativas de recuperação nas últimas 24 h" % len(tent))], "")
        return pior([], "a responder" + (" · recuperado %s" % ha(min(tent)) if tent else ""))
    if vigia is None:
        return pior([("FAILED", "não responde (sem recuperação automática)")], "")
    if vigia_min is None or vigia_min > LIMITE_MIN["vigia"]:
        return pior([("FAILED", "não responde e o vigia não está a correr (última volta %s)" % ha(vigia_min))], "")
    # a última tentativa ainda pode resultar: só se dá por esgotado depois de ela ter tido tempo
    if vigia.get("avisado") or (len(tent) >= TENTATIVAS_MAX and min(tent) > RECUPERA_MIN):
        return pior([("FAILED", "esgotou as %d tentativas em 24 h: precisa de ti" % TENTATIVAS_MAX)], "")
    if tent and min(tent) <= RECUPERA_MIN:
        return pior([("RECOVERING", "tentativa %d/%d %s" % (len(tent), TENTATIVAS_MAX, ha(min(tent))))], "")
    return pior([("RECOVERING", "em baixo; o vigia confirma e volta a arrancá-lo")], "")


def estado_maquina(m, dados_min, hw=None, agora=None):
    """m: uma máquina do estado.json do estado-maquinas ({nome, ligada, atualizacoes}); dados_min: idade desse
    estado.json em minutos; hw: o sensores.json desta máquina (ou None)."""
    ach = []
    if dados_min is None or dados_min > LIMITE_MIN["maquinas"]:
        ach.append(("STALE", "estado das máquinas lido " + ha(dados_min)))
    if not m.get("ligada"):
        ach.append(("OFFLINE", "não responde" + (" (visto %s)" % ha(idade_min(m["visto"], agora)) if m.get("visto") else "")))
    u = m.get("atualizacoes") or {}
    if u.get("quando"):
        iu = idade_min(u["quando"], agora)
        if iu is None or iu > LIMITE_MIN["atualizacoes"]:
            ach.append(("STALE", "atualizações verificadas " + ha(iu)))
    if u.get("criticas"):
        ach.append(("WARNING", "%s %s por instalar" % (u["criticas"], "atualização crítica" if u["criticas"] == 1 else "atualizações críticas")))
    if hw:
        ih = idade_min(hw.get("quando"), agora)
        r = hw.get("resumo") or {}
        if ih is None or ih > LIMITE_MIN["sensores"]:
            ach.append(("STALE", "sensores lidos " + ha(ih)))
        elif r.get("falhou"):
            ach.append(("FAILED", next((a for a in r.get("alertas") or [] if "SMART" in a), "disco com SMART falhado")))
        else:
            erros = set(hw.get("erros") or [])  # falta o LibreHardwareMonitor ou o smartctl: não é o hardware em alerta
            reais = [a for a in r.get("alertas") or [] if a not in erros]
            if reais:
                ach.append(("DEGRADED", "hardware em alerta: " + reais[0]))
            elif erros:
                ach.append(("WARNING", "sensores por ler: " + sorted(erros)[0]))
            elif r.get("avisos"):
                ach.append(("WARNING", r["avisos"][0]))
    return pior(ach, "ligada, sem alertas")


def contagem(itens):
    return {e: sum(1 for x in itens if x.get("estado") == e) for e in ORDEM}


def _teste():
    agora = datetime(2026, 1, 15, 12, 0, tzinfo=timezone.utc)
    iso = lambda m: (agora - timedelta(minutes=m)).isoformat()
    E = lambda *a, **k: estado_servico(*a, agora=agora, **k)["estado"]
    # serviços
    assert E(True) == "HEALTHY"
    assert E(True, {"tentativas": [iso(30), iso(90)]}, 1) == "WARNING"            # instável
    assert E(True, {"tentativas": [iso(60 * 25), iso(60 * 26)]}, 1) == "HEALTHY"   # tentativas fora das 24 h
    assert E(False) == "FAILED"                                                    # sem vigia
    assert E(False, {"falhas": 1, "tentativas": []}, None) == "FAILED"            # vigia nunca correu
    assert E(False, {"falhas": 1, "tentativas": []}, 60) == "FAILED"              # vigia parado
    assert E(False, {"falhas": 1, "tentativas": []}, 3) == "RECOVERING"           # a confirmar
    assert E(False, {"falhas": 2, "tentativas": [iso(10)]}, 3) == "RECOVERING"    # tentativa 1/3
    assert E(False, {"falhas": 9, "tentativas": [iso(200), iso(150), iso(10)]}, 3) == "RECOVERING"  # 3.a ainda a tempo
    assert E(False, {"falhas": 9, "tentativas": [iso(300), iso(200), iso(90)]}, 3) == "FAILED"     # esgotado
    assert E(False, {"falhas": 9, "tentativas": [], "avisado": True}, 3) == "FAILED"
    assert "2/3" in estado_servico(False, {"tentativas": [iso(50), iso(5)]}, 3, agora)["motivo"]
    # máquinas
    M = lambda m, d=5, hw=None: estado_maquina(m, d, hw, agora)["estado"]
    hw = lambda **r: {"quando": iso(2), "resumo": r}
    assert M({"ligada": True}) == "HEALTHY"
    assert M({"ligada": False}) == "OFFLINE"
    assert M({"ligada": False}, 90) == "OFFLINE"                                     # desligada ganha a desatualizada
    assert M({"ligada": True}, 90) == "STALE" and M({"ligada": True}, None) == "STALE"
    assert M({"ligada": True, "atualizacoes": {"quando": iso(60), "criticas": 2}}) == "WARNING"
    assert M({"ligada": True, "atualizacoes": {"quando": iso(60 * 20), "criticas": 0}}) == "STALE"
    assert M({"ligada": True}, hw=hw(ok=False, falhou=True, alertas=["Disco X: SMART FALHOU"])) == "FAILED"
    assert M({"ligada": True}, hw=hw(ok=False, alertas=["CPU muito quente: 95 C"])) == "DEGRADED"
    assert M({"ligada": True}, hw=hw(ok=True, avisos=["CPU a 85 C"])) == "WARNING"
    assert M({"ligada": True}, hw={"quando": iso(60), "resumo": {"ok": True}}) == "STALE"
    assert M({"ligada": False}, hw=hw(ok=False, falhou=True, alertas=["x"])) == "OFFLINE"
    erro = {"quando": iso(2), "erros": ["sensores: falta x"], "resumo": {"ok": False, "alertas": ["sensores: falta x"]}}
    assert M({"ligada": True}, hw=erro) == "WARNING"                                   # erro de leitura não degrada
    erro["resumo"]["alertas"].append("CPU muito quente: 95 C")
    assert M({"ligada": True}, hw=erro) == "DEGRADED"
    # pior e contagem
    p = pior([("WARNING", "a"), ("FAILED", "b"), ("FAILED", "c")], "")
    assert p == {"estado": "FAILED", "etiqueta": "Falhou", "motivo": "b; c"}
    assert pior([], "tudo bem")["estado"] == "HEALTHY"
    c = contagem([{"estado": "HEALTHY"}, {"estado": "HEALTHY"}, {"estado": "STALE"}])
    assert set(c) == set(ORDEM) and c["HEALTHY"] == 2 and c["STALE"] == 1 and c["OFFLINE"] == 0
    assert set(ETIQUETAS) == set(ORDEM) and len(ORDEM) == 7
    assert idade_min("não é data") is None and ha(None) == "a hora desconhecida" and ha(3000) == "há 2 dias"
    assert idade_min("2026-01-15T11:50:00.1234567Z", agora) == 9                   # data do PowerShell
    print("autoteste ok: 7 estados")


if __name__ == "__main__":
    if sys.stdout is not None:
        sys.stdout.reconfigure(encoding="utf-8", errors="replace")
    _teste() if "--teste" in sys.argv else print(__doc__)
