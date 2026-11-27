"""Alertas completos: um catálogo e um formato para o Discord e para texto simples (Healthchecks, e-mail).

Cada alerta leva equipamento, serviço, hora, problema, evidência, impacto, histórico, causa provável,
solução sugerida e estado; níveis CRITICAL, HIGH, MEDIUM e LOW. O catalogo.json (ao lado deste ficheiro) dá,
por padrão de chave, o nível, o serviço, o impacto, a causa e a solução; quem avisa dá a evidência, o estado e o histórico.
Não avisar duas vezes o mesmo (novo / resolvido / já avisado) fica com quem avisa; aqui só se formata e se conta o histórico.
O equivalente em PowerShell é o alerta.ps1. Só usa a biblioteca padrão (Python 3.8 ou mais recente).

  from alerta import montar, discord
  a = montar("disco:C", "disco C: com 4 % livre", "Este PC", nivel_emissor="WARNING", historico=1)
  print(discord(a))

Autoteste: python alerta.py --teste
"""
from __future__ import annotations

import json
import sys
from datetime import datetime, timedelta, timezone
from fnmatch import fnmatchcase
from pathlib import Path

CATALOGO = Path(__file__).with_name("catalogo.json")
NIVEIS = ("CRITICAL", "HIGH", "MEDIUM", "LOW")
DO_EMISSOR = {"CRITICAL": "CRITICAL", "WARNING": "MEDIUM", "INFO": "LOW", **{n: n for n in NIVEIS}}
ICONE = {"CRITICAL": "🔴", "HIGH": "🟠", "MEDIUM": "🟡", "LOW": "🔵"}
LIMITE_DISCORD = 1900  # o Discord aceita 2000 carateres por mensagem
MAX_MENSAGENS = 4  # alertas a mais vão em várias mensagens; acima disto ficam contados na última
DIAS_HISTORICO = 7
EVIDENCIA_MAX = 350  # no Discord; o texto simples leva a evidência inteira
_GENERICO = {"servico": "Geral", "titulo": "Problema detetado", "impacto": "Pode afetar o serviço indicado.",
             "causa": "Sem catálogo de alertas.", "solucao": "Ler a evidência e o registo de quem avisou."}
_lidos: dict = {}


def catalogo(caminho=CATALOGO) -> dict:
    """O catálogo, lido uma vez por processo; estragado ou em falta, fica só o genérico (o alerta sai na mesma)."""
    chave = str(caminho)
    if chave not in _lidos:
        try:
            dados = json.loads(Path(caminho).read_text(encoding="utf-8-sig"))
            if not isinstance(dados, dict) or not isinstance(dados.get("tipos"), list):
                raise ValueError("sem lista de tipos")
        except (OSError, ValueError):
            dados = {"generico": _GENERICO, "tipos": []}
        _lidos[chave] = dados
    return _lidos[chave]


def tipo(chave: str, cat: dict | None = None) -> dict:
    """Junta os tipos que casam com a chave, do menos para o mais específico; `casou` diz se algum casou."""
    cat = cat or catalogo()
    k = (chave or "").lower()
    casam = [(len(t["chave"].replace("*", "")), i, t) for i, t in enumerate(cat.get("tipos") or [])
             if isinstance(t, dict) and isinstance(t.get("chave"), str) and fnmatchcase(k, t["chave"].lower())]
    junto = {**_GENERICO, **(cat.get("generico") or {})}
    for _, _, t in sorted(casam, key=lambda x: x[:2]):
        junto.update({c: v for c, v in t.items() if v not in (None, "")})
    junto["casou"] = bool(casam)
    return junto


def nivel(t: dict, do_emissor: str | None) -> str:
    n = t.get("nivel")
    if isinstance(n, dict):
        n = n.get(do_emissor or "")
    if n in NIVEIS:
        return n
    return DO_EMISSOR.get(do_emissor or "", "MEDIUM")


def montar(chave: str, evidencia: str, equipamento: str, *, quando: datetime | None = None, nivel_emissor: str | None = None,
           historico: int = 0, estado: str = "novo", servico: str | None = None, resolvido: bool = False,
           cat: dict | None = None) -> dict:
    """O alerta com os 10 campos. A chave nunca vai para o texto (pode ter nomes de máquinas ou endereços)."""
    t = tipo(chave, cat)
    return {"chave": chave, "nivel": nivel(t, nivel_emissor), "equipamento": t.get("equipamento") or equipamento,
            "servico": servico or t["servico"], "hora": quando or datetime.now(timezone.utc), "problema": t["titulo"],
            "evidencia": " ".join(str(evidencia or "").split()) or "(sem evidência)", "impacto": t["impacto"],
            "historico": historico, "causa": t["causa"], "solucao": t["solucao"], "estado": estado,
            "resolvido": resolvido}


def _hora(d: datetime) -> str:
    return d.astimezone().strftime("%d/%m %H:%M")  # hora local do PC


def _historico(n: int) -> str:
    # 0 = aberto há mais de 7 dias ou antes de haver histórico: não dizer «sem registo» ao lado de «aberto desde»
    return f"{n}.ª vez nos últimos {DIAS_HISTORICO} dias" if n > 0 else f"sem aberturas registadas nos últimos {DIAS_HISTORICO} dias"


def _cortar(texto: str, limite: int) -> str:
    return texto if len(texto) <= limite else texto[:limite - 1].rstrip() + "…"


def discord(a: dict) -> str:
    """Bloco compacto: a 1.ª linha começa por «- » (um alerta por item da lista), as outras por dois espaços."""
    if a.get("resolvido"):
        return "\n".join((f"- ✅ **RESOLVIDO · {a['equipamento']}** · {a['servico']} · {_hora(a['hora'])}",
                          f"  Problema: {a['problema']}", f"  Evidência: {_cortar(a['evidencia'], EVIDENCIA_MAX)}",
                          f"  Histórico: {_historico(a['historico'])}", f"  Estado: {a['estado']}"))
    return "\n".join((f"- {ICONE[a['nivel']]} **{a['nivel']} · {a['equipamento']}** · {a['servico']} · {_hora(a['hora'])}",
                      f"  Problema: {a['problema']}", f"  Evidência: {_cortar(a['evidencia'], EVIDENCIA_MAX)}",
                      f"  Impacto: {a['impacto']}", f"  Causa provável: {a['causa']}", f"  Solução: {a['solucao']}",
                      f"  Histórico: {_historico(a['historico'])}", f"  Estado: {a['estado']}"))


def texto(a: dict) -> str:
    """Texto simples (Healthchecks e e-mail), com a evidência inteira."""
    cabeca = "RESOLVIDO" if a.get("resolvido") else a["nivel"]
    return "\n".join((f"{cabeca} · {a['equipamento']} · {a['servico']} · {_hora(a['hora'])}",
                      f"Problema: {a['problema']}", f"Evidência: {a['evidencia']}", f"Impacto: {a['impacto']}",
                      f"Causa provável: {a['causa']}", f"Solução: {a['solucao']}",
                      f"Histórico: {_historico(a['historico'])}", f"Estado: {a['estado']}"))


def partir(cabecalho: str, blocos: list, limite: int = LIMITE_DISCORD, maximo: int = MAX_MENSAGENS) -> list:
    """Cabeçalho e blocos em mensagens de até `limite` carateres, sem partir um alerta ao meio; o que não cabe vai na
    mensagem seguinte, e só acima de `maximo` mensagens é que fica contado na última."""
    nota = "\n(+{} alerta(s) sem espaço: ver o registo)"
    seguinte = cabecalho + " (continuação)"
    caber = limite - len(nota) - 4  # cada mensagem guarda espaço para a nota
    msgs = [cabecalho]
    for i, b in enumerate(blocos):
        b = _cortar(b, caber - len(seguinte) - 1)
        if len(msgs[-1]) + 1 + len(b) > caber:
            if len(msgs) >= maximo:
                msgs[-1] += nota.format(len(blocos) - i)
                break
            msgs.append(seguinte)
        msgs[-1] += "\n" + b
    return msgs


def _instante(x):
    try:
        d = datetime.fromisoformat(str(x).replace("Z", "+00:00"))
    except ValueError:
        return None
    return d if d.tzinfo else d.replace(tzinfo=timezone.utc)


def contar(hist: dict, chave: str, agora: datetime) -> int:
    """Quantas vezes a chave abriu nos últimos 7 dias, pelo histórico {chave: [instantes ISO]}."""
    limite = agora - timedelta(days=DIAS_HISTORICO)
    return sum(1 for x in (hist or {}).get(chave) or [] if _instante(x) and _instante(x) >= limite)


def podar(hist: dict, agora: datetime) -> dict:
    """Deita fora do histórico o que tem mais de 7 dias (e o que não é data)."""
    limite = agora - timedelta(days=DIAS_HISTORICO)
    for k in list(hist):
        hist[k] = [x for x in hist[k] if _instante(x) and _instante(x) >= limite] if isinstance(hist[k], list) else []
        if not hist[k]:
            del hist[k]
    return hist


def registar(hist: dict, chave: str, ocorreu: datetime, agora: datetime | None = None) -> int:
    """Acrescenta a ocorrência (a mesma hora não conta duas vezes: reenviar um aviso falhado não soma),
    deita fora o que tem mais de 7 dias e devolve a contagem desta chave."""
    agora = agora or ocorreu
    podar(hist, agora)
    lista = hist.setdefault(chave, [])
    if ocorreu.isoformat() not in lista:
        lista.append(ocorreu.isoformat())
    return contar(hist, chave, agora)


# chaves de exemplo: as do vigia-servicos e do sensores.ps1, e outras que os teus scripts podem usar; o autoteste exige um tipo próprio para cada uma
CHAVES_CONHECIDAS = (
    "disco:C", "memoria", "tarefa:Limpar RAM", "dados:estado.json", "atualizacoes:Servidor Linux",
    "maquina:NAS", "maquina:NAS:voltou",
    "servico:comfyui:tentativa", "servico:comfyui:esgotado", "servico:comfyui:voltou",
    "queda:luz", "queda:parado", "queda:internet",
    # sensores.ps1
    "hw-cpu-quente", "hw-gpu-quente", "hw-gpu-hotspot", "hw-disco-smart:Disco1", "hw-disco-realocados:Disco1",
    "hw-disco-pendentes:Disco1", "hw-disco-incorrigiveis:Disco1", "hw-disco-nvme_erros_media:Disco1",
    "hw-disco-gasto:Disco1", "hw-disco-quente:Disco1", "hw-erro-sensores", "hw-erro-discos")


def _teste() -> None:
    cat = catalogo()
    assert cat["tipos"], "o catálogo não carregou"
    chaves = [t["chave"].lower() for t in cat["tipos"]]
    assert len(chaves) == len(set(chaves)), "há tipos repetidos no catálogo"
    for t in cat["tipos"]:
        assert set(t) <= {"chave", "equipamento", "servico", "titulo", "nivel", "impacto", "causa", "solucao"}, t["chave"]
        n = t.get("nivel")
        assert n is None or n in NIVEIS or (isinstance(n, dict) and set(n.values()) <= set(NIVEIS)), t["chave"]
    for c in CHAVES_CONHECIDAS:
        t = tipo(c)
        assert t["casou"] and t["titulo"] != _GENERICO["titulo"], f"sem tipo próprio: {c}"
        assert all(t[k] for k in ("servico", "impacto", "causa", "solucao")), c
    # o mais específico ganha; o emissor manda no nível quando o tipo dá um mapa
    assert tipo("servico:x:esgotado")["titulo"] == "Serviço em baixo: tentativas esgotadas"
    assert tipo("servico:x:esgotado")["impacto"] == tipo("servico:x")["impacto"]  # herdado do servico:*
    assert nivel(tipo("disco:C"), "INFO") == "LOW" and nivel(tipo("disco:C"), "CRITICAL") == "CRITICAL"
    assert nivel(tipo("hw-disco-smart:x"), None) == "CRITICAL"
    g = tipo("coisa-que-nao-existe")
    assert not g["casou"] and g["solucao"] and nivel(g, None) == "MEDIUM" and nivel(g, "CRITICAL") == "CRITICAL"
    # catálogo em falta não rebenta
    assert tipo("disco:C", catalogo(CATALOGO.with_name("nao-existe.json")))["titulo"] == _GENERICO["titulo"]
    # formato: os 10 campos estão lá e a chave não aparece
    agora = datetime(2026, 1, 15, 12, 0, tzinfo=timezone.utc)
    a = montar("hw-disco-quente:modelo-secreto", "Disco de exemplo quente: 58 C", "Este PC",
               quando=agora, historico=2, estado="novo")
    d = discord(a)
    for campo in ("MEDIUM · Este PC", "Problema: Disco quente", "Evidência: Disco de exemplo quente: 58 C",
                  "Impacto: ", "Causa provável: ", "Solução: ", "Histórico: 2.ª vez nos últimos 7 dias", "Estado: novo"):
        assert campo in d, campo
    assert "modelo-secreto" not in d and d.startswith("- ") and d.count("\n- ") == 0
    assert "Histórico: sem aberturas registadas nos últimos 7 dias" in discord(montar("disco:C", "x", "PC", quando=agora))
    assert "\nEvidência: " in texto(a) and "**" not in texto(a)
    r = discord(montar("disco:C", "disco C: com 20 %", "Este PC", quando=agora, resolvido=True, estado="resolvido"))
    assert "RESOLVIDO" in r and "Causa provável" not in r
    assert len(discord(montar("x", "y" * 5000, "PC", quando=agora))) < 1500
    # partir: nenhuma mensagem passa do limite, nenhum alerta se perde até ao máximo de mensagens
    assert partir("C", [d, d]) == ["C\n" + d + "\n" + d]
    m = partir("Sensores", [d] * 6)
    assert len(m) > 1 and all(len(x) <= LIMITE_DISCORD for x in m) and sum(x.count("\n- ") for x in m) == 6
    assert m[1].startswith("Sensores (continuação)") and "sem espaço" not in "".join(m)
    m = partir("C", [d] * 40)
    assert len(m) == MAX_MENSAGENS and "alerta(s) sem espaço" in m[-1] and all(len(x) <= LIMITE_DISCORD for x in m)
    assert sum(x.count("\n- ") for x in m) + int(m[-1].rsplit("(+", 1)[1].split()[0]) == 40
    assert len(partir("C", ["- " + "z" * 3000])[0]) <= LIMITE_DISCORD
    # histórico: 7 dias, sem contar duas vezes o mesmo instante
    h = {"velha": [(agora - timedelta(days=9)).isoformat()], "estragada": ["isto não é data"]}
    assert registar(h, "k", agora - timedelta(days=2), agora) == 1
    assert registar(h, "k", agora, agora) == 2 and registar(h, "k", agora, agora) == 2
    assert "velha" not in h and "estragada" not in h and contar(h, "k", agora + timedelta(days=6)) == 1
    assert contar({}, "k", agora) == 0 and contar(None, "k", agora) == 0
    print(f"autoteste ok: {len(cat['tipos'])} tipos, {len(CHAVES_CONHECIDAS)} chaves conhecidas com tipo próprio")


if __name__ == "__main__":
    if sys.stdout is not None:
        sys.stdout.reconfigure(encoding="utf-8", errors="replace")
    _teste() if "--teste" in sys.argv else print(__doc__)
