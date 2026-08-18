# import datetime
# import decimal
# import json
# import re

# from flask import Blueprint, jsonify, request

# from database.server import create_connection_tinturaria

# wms_separacao_planejada_bp = Blueprint("wms_separacao_planejada", __name__)


# def _to_int(value, default=0):
#     try:
#         if value in (None, ""):
#             return default
#         return int(value)
#     except Exception:
#         return default


# def _to_float(value, default=0.0):
#     try:
#         if value in (None, ""):
#             return default
#         return float(str(value).replace(",", "."))
#     except Exception:
#         return default


# def _norm(value):
#     return (value or "").strip().upper()


# def _coerce(value):
#     if isinstance(value, decimal.Decimal):
#         return float(value)
#     if isinstance(value, (datetime.datetime, datetime.date)):
#         return value.isoformat()
#     return value


# def _row_dict(cursor, row):
#     if not row:
#         return None
#     columns = [col[0] for col in cursor.description]
#     return {columns[i]: _coerce(row[i]) for i in range(len(columns))}


# def _fetch_all_dict(cursor):
#     columns = [col[0] for col in cursor.description]
#     return [{columns[i]: _coerce(row[i]) for i in range(len(columns))} for row in cursor.fetchall()]


# def _json_safe(obj):
#     if isinstance(obj, (datetime.datetime, datetime.date)):
#         return obj.isoformat()
#     if isinstance(obj, decimal.Decimal):
#         return float(obj)
#     if isinstance(obj, list):
#         return [_json_safe(x) for x in obj]
#     if isinstance(obj, dict):
#         return {k: _json_safe(v) for k, v in obj.items()}
#     return obj


# def _extrair_artigo_mae(descricao):
#     texto = (descricao or "").strip()
#     if not texto:
#         return ""
#     match = re.search(r"(.+?\bmm)", texto, flags=re.IGNORECASE)
#     if match:
#         return texto[: match.end()].strip()
#     return texto


# def _buscar_padrao_caixa(cursor, objeto):
#     artigo_mae = _extrair_artigo_mae(objeto)
#     if not artigo_mae:
#         return {}, ""

#     cursor.execute(
#         """
#         SELECT TOP 1
#             artigo,
#             caixa_p = ISNULL(caixa_p, 0),
#             caixa_g = ISNULL(caixa_g, 0),
#             enfestado = ISNULL(enfestado, 0),
#             enfraldado = ISNULL(enfraldado, 0)
#         FROM dbo.Stik_PadraoCaixa WITH (NOLOCK)
#         WHERE UPPER(LTRIM(RTRIM(artigo))) = UPPER(LTRIM(RTRIM(?)))
#     """,
#         (artigo_mae,),
#     )
#     padrao = _row_dict(cursor, cursor.fetchone())
#     return padrao or {}, artigo_mae


# def _buscar_candidatos_embalagem(cursor, cd_obj, detalhe):
#     cursor.execute(
#         """
#         WITH AlocacaoBase AS (
#             SELECT
#                 Endereco = UPPER(LTRIM(RTRIM(Endereco))),
#                 CodSKU,
#                 Detalhe = ISNULL(Detalhe, 0),
#                 QtBase = SUM(ISNULL(QtAlocada, 0))
#             FROM dbo.Stik_WMS_Alocacao WITH (NOLOCK)
#             WHERE CodSKU = ?
#               AND ISNULL(Detalhe, 0) = ISNULL(?, 0)
#             GROUP BY UPPER(LTRIM(RTRIM(Endereco))), CodSKU, ISNULL(Detalhe, 0)
#         ),
#         Movimentos AS (
#             SELECT
#                 Endereco = UPPER(LTRIM(RTRIM(Endereco))),
#                 CodSKU,
#                 Detalhe = ISNULL(Detalhe, 0),
#                 QtMov = SUM(
#                     CASE
#                         WHEN ISNULL(TpMov, 0) IN (1, 3) THEN ISNULL(QtMovida, 0)
#                         ELSE -ISNULL(QtMovida, 0)
#                     END
#                 )
#             FROM dbo.Stik_WMS_Movimento WITH (NOLOCK)
#             WHERE CodSKU = ?
#               AND ISNULL(Detalhe, 0) = ISNULL(?, 0)
#             GROUP BY UPPER(LTRIM(RTRIM(Endereco))), CodSKU, ISNULL(Detalhe, 0)
#         ),
#         Chaves AS (
#             SELECT Endereco, CodSKU, Detalhe FROM AlocacaoBase
#             UNION
#             SELECT Endereco, CodSKU, Detalhe FROM Movimentos
#         ),
#         Saldos AS (
#             SELECT
#                 C.Endereco,
#                 C.CodSKU,
#                 C.Detalhe,
#                 QtSaldoFinal =
#                     ISNULL(A.QtBase, 0) + ISNULL(M.QtMov, 0)
#             FROM Chaves C
#             LEFT JOIN AlocacaoBase A
#                 ON A.Endereco = C.Endereco
#                AND A.CodSKU = C.CodSKU
#                AND A.Detalhe = C.Detalhe
#             LEFT JOIN Movimentos M
#                 ON M.Endereco = C.Endereco
#                AND M.CodSKU = C.CodSKU
#                AND M.Detalhe = C.Detalhe
#         ),
#         CaixaResumo AS (
#             -- Fonte oficial das caixas fechadas: Stik_WMS_Caixa (caixa
#             -- física individual), não mais o contador agregado antigo.
#             SELECT
#                 Endereco = UPPER(LTRIM(RTRIM(Endereco))),
#                 CdObj,
#                 Detalhe = ISNULL(Detalhe, 0),
#                 QtCaixaP = SUM(CASE WHEN TipoCaixa = 'P' THEN 1 ELSE 0 END),
#                 QtCaixaG = SUM(CASE WHEN TipoCaixa = 'G' THEN 1 ELSE 0 END),
#                 QtEnfestado = SUM(CASE WHEN TipoCaixa = 'ENF' THEN 1 ELSE 0 END),
#                 QtEnfraldado = SUM(CASE WHEN TipoCaixa = 'ENFR' THEN 1 ELSE 0 END)
#             FROM dbo.Stik_WMS_Caixa WITH (NOLOCK)
#             WHERE Status = 'DISPONIVEL'
#               AND CdObj = ?
#               AND ISNULL(Detalhe, 0) = ISNULL(?, 0)
#             GROUP BY UPPER(LTRIM(RTRIM(Endereco))), CdObj, ISNULL(Detalhe, 0)
#         )
#         SELECT
#             S.Endereco,
#             S.CodSKU,
#             S.Detalhe,
#             QtSaldoFinal = S.QtSaldoFinal,
#             QtCaixaP = ISNULL(E.QtCaixaP, 0),
#             QtCaixaG = ISNULL(E.QtCaixaG, 0),
#             QtEnfestado = ISNULL(E.QtEnfestado, 0),
#             QtEnfraldado = ISNULL(E.QtEnfraldado, 0)
#         FROM Saldos S
#         LEFT JOIN CaixaResumo E
#             ON E.Endereco = S.Endereco
#            AND E.CdObj = S.CodSKU
#            AND E.Detalhe = S.Detalhe
#         WHERE S.QtSaldoFinal > 0
#         ORDER BY
#             CASE
#                 WHEN ISNULL(E.QtCaixaP, 0) > 0 OR
#                      ISNULL(E.QtCaixaG, 0) > 0 OR
#                      ISNULL(E.QtEnfestado, 0) > 0 OR
#                      ISNULL(E.QtEnfraldado, 0) > 0
#                 THEN 0 ELSE 1
#             END,
#             S.QtSaldoFinal DESC,
#             S.Endereco
#     """,
#         (cd_obj, detalhe, cd_obj, detalhe, cd_obj, detalhe),
#     )
#     return _fetch_all_dict(cursor)


# def _parse_endereco(endereco):
#     texto = _norm(endereco)
#     partes = [p for p in texto.split("-") if p]
#     rua = ""
#     nivel = ""
#     rack = 0
#     posicao = 0

#     for idx, parte in enumerate(partes):
#         if re.match(r"^L\d+$", parte):
#             rua = parte
#         elif re.match(r"^R\d+$", parte):
#             rack = _to_int(parte[1:])
#             if idx + 1 < len(partes):
#                 proximo = partes[idx + 1]
#                 if not re.match(r"^P\d+$", proximo):
#                     nivel = proximo
#         elif re.match(r"^P\d+$", parte):
#             posicao = _to_int(parte[1:])

#     return {
#         "rua": rua,
#         "nivel": nivel,
#         "rack": rack,
#         "posicao": posicao,
#         "rua_nivel": f"{rua}|{nivel}" if rua and nivel else "",
#     }


# def _tem_embalagem(candidato):
#     return (
#         _to_int(candidato.get("QtCaixaP")) > 0 or
#         _to_int(candidato.get("QtCaixaG")) > 0 or
#         _to_int(candidato.get("QtEnfestado")) > 0 or
#         _to_int(candidato.get("QtEnfraldado")) > 0
#     )


# def _calcular_perfil_proximidade(preparados):
#     ruas = {}
#     niveis = {}
#     racks = {}

#     for idx, preparado in enumerate(preparados):
#         ruas_item = set()
#         niveis_item = set()
#         racks_item = set()
#         for candidato in preparado.get("candidatos", []):
#             endereco_info = _parse_endereco(candidato.get("Endereco"))
#             candidato["_EnderecoInfo"] = endereco_info
#             if endereco_info["rua"]:
#                 ruas_item.add(endereco_info["rua"])
#             if endereco_info["rua_nivel"]:
#                 niveis_item.add(endereco_info["rua_nivel"])
#             if endereco_info["rua"] and endereco_info["rack"] > 0:
#                 racks_item.add((endereco_info["rua"], endereco_info["rack"]))

#         for key in ruas_item:
#             ruas.setdefault(key, set()).add(idx)
#         for key in niveis_item:
#             niveis.setdefault(key, set()).add(idx)
#         for key in racks_item:
#             racks.setdefault(key, set()).add(idx)

#     return {
#         "ruas": {key: len(value) for key, value in ruas.items()},
#         "niveis": {key: len(value) for key, value in niveis.items()},
#         "racks": {key: len(value) for key, value in racks.items()},
#     }


# def _aplicar_proximidade_candidatos(preparados):
#     perfil = _calcular_perfil_proximidade(preparados)

#     for preparado in preparados:
#         for candidato in preparado.get("candidatos", []):
#             endereco_info = candidato.get("_EnderecoInfo") or _parse_endereco(candidato.get("Endereco"))
#             rua = endereco_info["rua"]
#             rua_nivel = endereco_info["rua_nivel"]
#             rack_key = (rua, endereco_info["rack"]) if rua and endereco_info["rack"] > 0 else None
#             score = (
#                 perfil["ruas"].get(rua, 0) * 300 +
#                 perfil["niveis"].get(rua_nivel, 0) * 180 +
#                 (perfil["racks"].get(rack_key, 0) * 80 if rack_key else 0)
#             )
#             candidato["_ProximidadeScore"] = score
#             candidato["_TemEmbalagem"] = 1 if _tem_embalagem(candidato) else 0

#         preparado["candidatos"].sort(
#             key=lambda c: (
#                 -_to_int(c.get("_ProximidadeScore")),
#                 -_to_int(c.get("_TemEmbalagem")),
#                 -_to_float(c.get("QtSaldoFinal")),
#                 _to_int((c.get("_EnderecoInfo") or {}).get("rack")),
#                 _to_int((c.get("_EnderecoInfo") or {}).get("posicao")),
#                 _norm(c.get("Endereco")),
#             )
#         )


# def _caixas_disponiveis(candidato, campo_qt, mts_caixa):
#     if mts_caixa <= 0:
#         return 0
#     # Confia na contagem real de caixas (Stik_WMS_Caixa). Não estima mais
#     # "caixas possíveis" a partir do saldo em metros quando a contagem é
#     # zero — isso fazia o planejamento escolher endereços que não têm
#     # nenhuma caixa fechada daquele tipo, só porque tinham saldo suficiente.
#     saldo = _to_float(candidato.get("QtSaldoFinal"))
#     por_saldo = int(saldo // mts_caixa)
#     por_embalagem = _to_int(candidato.get(campo_qt))
#     return min(por_embalagem, por_saldo)


# def _copiar_candidatos(candidatos):
#     return [dict(candidato) for candidato in candidatos]


# def _consumir_saldo_candidato(candidato, metros):
#     saldo = _to_float(candidato.get("QtSaldoFinal"))
#     candidato["QtSaldoFinal"] = max(0, saldo - _to_float(metros))


# def _montar_linhas_caixa_individuais(endereco, tipo, qt_caixas, mts_caixa):
#     linhas = []
#     for _ in range(_to_int(qt_caixas)):
#         linhas.append(
#             {
#                 "endereco": endereco,
#                 "tipo_caixa": tipo,
#                 "qt_caixas": 1,
#                 "mts_por_caixa": mts_caixa,
#                 "mts_planejados": mts_caixa,
#             }
#         )
#     return linhas


# def _montar_fracionado_restante(restante_metros, candidatos):
#     if restante_metros <= 0:
#         return [], 0
#     candidatos_com_saldo = [
#         candidato for candidato in candidatos
#         if _to_float(candidato.get("QtSaldoFinal")) > 0
#     ]
#     for candidato in candidatos_com_saldo:
#         if _to_float(candidato.get("QtSaldoFinal")) >= restante_metros:
#             return [
#                 {
#                     "endereco": candidato.get("Endereco"),
#                     "tipo_caixa": "FRACIONADO",
#                     "qt_caixas": 0,
#                     "mts_por_caixa": 0,
#                     "mts_planejados": restante_metros,
#                 }
#             ], 0
#     return _montar_execucoes_por_saldo(restante_metros, candidatos_com_saldo)


# def _montar_execucoes_por_caixa(qt_romaneio, candidatos, padrao):
#     tipos = [
#         ("P", _to_float(padrao.get("caixa_p")), "QtCaixaP"),
#         ("G", _to_float(padrao.get("caixa_g")), "QtCaixaG"),
#         ("ENFESTADO", _to_float(padrao.get("enfestado")), "QtEnfestado"),
#         ("ENFRALDADO", _to_float(padrao.get("enfraldado")), "QtEnfraldado"),
#     ]

#     # Primeiro tenta atender tudo com um único palete e caixa fechada correta.
#     for tipo, mts_caixa, campo_qt in tipos:
#         if mts_caixa <= 0 or abs(qt_romaneio % mts_caixa) > 0.0001:
#             continue
#         caixas_necessarias = int(qt_romaneio // mts_caixa)
#         if caixas_necessarias <= 0:
#             continue
#         for candidato in candidatos:
#             if _caixas_disponiveis(candidato, campo_qt, mts_caixa) >= caixas_necessarias:
#                 return _montar_linhas_caixa_individuais(
#                     candidato.get("Endereco"),
#                     tipo,
#                     caixas_necessarias,
#                     mts_caixa,
#                 )

#     # Depois permite dividir a mesma caixa fechada entre paletes.
#     for tipo, mts_caixa, campo_qt in tipos:
#         if mts_caixa <= 0 or abs(qt_romaneio % mts_caixa) > 0.0001:
#             continue
#         restante_caixas = int(qt_romaneio // mts_caixa)
#         plano = []
#         for candidato in candidatos:
#             usar = min(
#                 _caixas_disponiveis(candidato, campo_qt, mts_caixa),
#                 restante_caixas
#             )
#             if usar <= 0:
#                 continue
#             plano.extend(
#                 _montar_linhas_caixa_individuais(
#                     candidato.get("Endereco"),
#                     tipo,
#                     usar,
#                     mts_caixa,
#                 )
#             )
#             restante_caixas -= usar
#             if restante_caixas == 0:
#                 return plano

#     # Se não fechar tudo em caixa, usa o máximo possível de caixa fechada
#     # e deixa somente a sobra como fracionado.
#     melhores = []
#     for tipo, mts_caixa, campo_qt in tipos:
#         if mts_caixa <= 0:
#             continue
#         candidatos_teste = _copiar_candidatos(candidatos)
#         restante_metros = _to_float(qt_romaneio)
#         plano = []

#         for candidato in candidatos_teste:
#             if restante_metros < mts_caixa:
#                 break
#             caixas_disponiveis = _caixas_disponiveis(candidato, campo_qt, mts_caixa)
#             caixas_necessarias = int(restante_metros // mts_caixa)
#             usar = min(caixas_disponiveis, caixas_necessarias)
#             if usar <= 0:
#                 continue
#             mts_total = usar * mts_caixa
#             plano.extend(
#                 _montar_linhas_caixa_individuais(
#                     candidato.get("Endereco"),
#                     tipo,
#                     usar,
#                     mts_caixa,
#                 )
#             )
#             restante_metros -= mts_total
#             _consumir_saldo_candidato(candidato, mts_total)

#         if not plano:
#             continue

#         fracionados, restante_sem_saldo = _montar_fracionado_restante(
#             restante_metros,
#             candidatos_teste
#         )
#         plano_completo = plano + fracionados
#         metros_caixa = sum(_to_float(ex.get("mts_planejados")) for ex in plano)
#         metros_fracionado = sum(_to_float(ex.get("mts_planejados")) for ex in fracionados)
#         melhores.append({
#             "plano": plano_completo,
#             "restante_sem_saldo": restante_sem_saldo,
#             "metros_caixa": metros_caixa,
#             "metros_fracionado": metros_fracionado,
#             "linhas": len(plano_completo),
#             "mts_caixa": mts_caixa,
#         })

#     if melhores:
#         melhores.sort(
#             key=lambda opcao: (
#                 _to_float(opcao["restante_sem_saldo"]),
#                 _to_float(opcao["metros_fracionado"]),
#                 -_to_float(opcao["metros_caixa"]),
#                 _to_int(opcao["linhas"]),
#                 -_to_float(opcao["mts_caixa"]),
#             )
#         )
#         melhor = melhores[0]
#         plano = melhor["plano"]
#         restante_sem_saldo = _to_float(melhor["restante_sem_saldo"])
#         if restante_sem_saldo > 0.0001:
#             plano = plano + [
#                 {
#                     "endereco": "SEM ESTOQUE",
#                     "tipo_caixa": "SEM_ESTOQUE",
#                     "qt_caixas": 0,
#                     "mts_por_caixa": 0,
#                     "mts_planejados": restante_sem_saldo,
#                 }
#             ]
#         return plano

#     return []


# def _montar_execucoes_por_saldo(qt_romaneio, candidatos):
#     restante = _to_float(qt_romaneio)
#     plano = []
#     for candidato in candidatos:
#         if restante <= 0:
#             break
#         saldo = _to_float(candidato.get("QtSaldoFinal"))
#         if saldo <= 0:
#             continue
#         usar = min(saldo, restante)
#         if usar <= 0:
#             continue
#         plano.append(
#             {
#                 "endereco": candidato.get("Endereco"),
#                 "tipo_caixa": "FRACIONADO",
#                 "qt_caixas": 0,
#                 "mts_por_caixa": 0,
#                 "mts_planejados": usar,
#             }
#         )
#         restante -= usar
#     return plano, restante


# def _inserir_execucao_planejada(cursor, id_plano_item, execucao):
#     cursor.execute(
#         """
#         INSERT INTO dbo.Stik_WMS_SeparacaoPlanejada_Execucao
#             (IdPlanoItem, Endereco, TipoCaixa, QtCaixasPlanejada, MtsPorCaixa, MtsPlanejados)
#         VALUES (?, ?, ?, ?, ?, ?)
#     """,
#         (
#             id_plano_item,
#             execucao["endereco"],
#             execucao["tipo_caixa"],
#             execucao["qt_caixas"],
#             execucao["mts_por_caixa"],
#             execucao["mts_planejados"],
#         ),
#     )


# def _dividir_execucoes_caixa_agregadas(cursor, id_plano):
#     cursor.execute(
#         """
#         SELECT
#             E.IdExecucao,
#             E.IdPlanoItem,
#             E.Endereco,
#             E.TipoCaixa,
#             E.QtCaixasPlanejada,
#             E.MtsPorCaixa
#         FROM dbo.Stik_WMS_SeparacaoPlanejada_Execucao E WITH (UPDLOCK, HOLDLOCK)
#         INNER JOIN dbo.Stik_WMS_SeparacaoPlanejada_Item I WITH (UPDLOCK, HOLDLOCK)
#             ON I.IdPlanoItem = E.IdPlanoItem
#         WHERE I.IdPlano = ?
#           AND ISNULL(E.QtCaixasPlanejada, 0) > 1
#           AND ISNULL(E.MtsPorCaixa, 0) > 0
#           AND UPPER(LTRIM(RTRIM(ISNULL(E.TipoCaixa, '')))) NOT IN ('FRACIONADO', 'SEM_ESTOQUE')
#           AND ISNULL(E.PaleteValidado, 0) = 0
#           AND ISNULL(E.ItemValidado, 0) = 0
#           AND ISNULL(E.Confirmado, 0) = 0
#           AND ISNULL(E.Cortado, 0) = 0
#         ORDER BY E.IdExecucao
#         """,
#         (id_plano,),
#     )
#     execucoes = _fetch_all_dict(cursor)
#     if not execucoes:
#         return 0

#     total_novas_linhas = 0
#     for execucao in execucoes:
#         qt_caixas = _to_int(execucao.get("QtCaixasPlanejada"))
#         if qt_caixas <= 1:
#             continue

#         cursor.execute(
#             "DELETE FROM dbo.Stik_WMS_SeparacaoPlanejada_Execucao WHERE IdExecucao = ?",
#             (execucao["IdExecucao"],),
#         )
#         for linha in _montar_linhas_caixa_individuais(
#             execucao.get("Endereco"),
#             execucao.get("TipoCaixa"),
#             qt_caixas,
#             _to_float(execucao.get("MtsPorCaixa")),
#         ):
#             _inserir_execucao_planejada(cursor, execucao["IdPlanoItem"], linha)
#             total_novas_linhas += 1

#     return total_novas_linhas


# def _gerar_execucoes_para_item(cursor, id_plano_item, cd_obj, detalhe, objeto, qt_romaneio):
#     """Consulta padrão de caixa + candidatos e insere as execuções de um
#     IdPlanoItem já existente. Usada tanto ao popular um plano novo quanto
#     ao recalcular um único item preservando os demais já iniciados."""
#     padrao, _artigo_mae = _buscar_padrao_caixa(cursor, objeto)
#     candidatos = _buscar_candidatos_embalagem(cursor, cd_obj, detalhe)

#     if not candidatos:
#         _inserir_execucao_planejada(
#             cursor,
#             id_plano_item,
#             {
#                 "endereco": "SEM ESTOQUE",
#                 "tipo_caixa": "SEM_ESTOQUE",
#                 "qt_caixas": 0,
#                 "mts_por_caixa": 0,
#                 "mts_planejados": qt_romaneio,
#             },
#         )
#         return

#     execucoes = _montar_execucoes_por_caixa(qt_romaneio, candidatos, padrao)
#     if execucoes:
#         for ex in execucoes:
#             _inserir_execucao_planejada(cursor, id_plano_item, ex)
#         return

#     execucoes_saldo, restante_sem_saldo = _montar_execucoes_por_saldo(qt_romaneio, candidatos)
#     for ex in execucoes_saldo:
#         _inserir_execucao_planejada(cursor, id_plano_item, ex)

#     if restante_sem_saldo > 0.0001:
#         _inserir_execucao_planejada(
#             cursor,
#             id_plano_item,
#             {
#                 "endereco": "SEM ESTOQUE",
#                 "tipo_caixa": "SEM_ESTOQUE",
#                 "qt_caixas": 0,
#                 "mts_por_caixa": 0,
#                 "mts_planejados": restante_sem_saldo,
#             },
#         )


# def _popular_plano(cursor, id_plano, nr_romaneio):
#     cursor.execute(
#         """
#         SELECT Fat.NrRomaneio, Fat.CdVpo, Vpd.CdVpd, Vpo.CdObj,
#                Detalhe = Lot.CdLot, NmLot = Lot.NmLot, Objeto = Obj.NmObj,
#                Setor = ISNULL(Obj.CdObjLin, 0),
#                QtRomaneio = ISNULL(Fat.QtFatAtend, Fat.QtFat)
#         FROM dbo.Stik_Pedido_QtdFat Fat WITH (NOLOCK)
#         INNER JOIN dbo.TbVpo Vpo WITH (NOLOCK) ON Vpo.CdVpo = Fat.CdVpo
#         INNER JOIN dbo.TbVpd Vpd WITH (NOLOCK) ON Vpd.CdVpd = Vpo.CdVpd
#         INNER JOIN dbo.TbObj Obj WITH (NOLOCK) ON Obj.CdObj = Vpo.CdObj
#         OUTER APPLY (
#             SELECT TOP 1 L.CdLot, L.NmLot
#             FROM dbo.TbLot L WITH (NOLOCK)
#             WHERE L.CdLot = Fat.CdLot
#         ) Lot
#         WHERE Fat.NrRomaneio = ?
#           AND ISNULL(Fat.TpSitFat, 0) <> 4
#     """,
#         (nr_romaneio,),
#     )
#     itens = _fetch_all_dict(cursor)
#     if not itens:
#         raise ValueError("Itens do romaneio não encontrados.")

#     preparados = []
#     for item in itens:
#         qt_romaneio = _to_float(item.get("QtRomaneio"))
#         if qt_romaneio <= 0:
#             continue
#         padrao, artigo_mae = _buscar_padrao_caixa(cursor, item.get("Objeto"))
#         candidatos = _buscar_candidatos_embalagem(cursor, item.get("CdObj"), item.get("Detalhe"))
#         preparados.append({
#             "item": item,
#             "qt_romaneio": qt_romaneio,
#             "padrao": padrao,
#             "artigo_mae": artigo_mae,
#             "candidatos": candidatos,
#         })

#     _aplicar_proximidade_candidatos(preparados)

#     for preparado in preparados:
#         item = preparado["item"]
#         qt_romaneio = preparado["qt_romaneio"]
#         padrao = preparado["padrao"]
#         candidatos = preparado["candidatos"]

#         cursor.execute(
#             """
#             INSERT INTO dbo.Stik_WMS_SeparacaoPlanejada_Item
#                 (IdPlano, CdVpo, CdVpd, CdObj, Detalhe, NmLot, Objeto, QtRomaneio)
#             OUTPUT INSERTED.IdPlanoItem
#             VALUES (?, ?, ?, ?, ?, ?, ?, ?)
#         """,
#             (
#                 id_plano,
#                 item.get("CdVpo"),
#                 item.get("CdVpd"),
#                 item.get("CdObj"),
#                 item.get("Detalhe"),
#                 item.get("NmLot"),
#                 item.get("Objeto"),
#                 qt_romaneio,
#             ),
#         )
#         id_plano_item = cursor.fetchone()[0]

#         if not candidatos:
#             _inserir_execucao_planejada(
#                 cursor,
#                 id_plano_item,
#                 {
#                     "endereco": "SEM ESTOQUE",
#                     "tipo_caixa": "SEM_ESTOQUE",
#                     "qt_caixas": 0,
#                     "mts_por_caixa": 0,
#                     "mts_planejados": qt_romaneio,
#                 },
#             )
#             continue

#         execucoes = _montar_execucoes_por_caixa(qt_romaneio, candidatos, padrao)
#         if execucoes:
#             for ex in execucoes:
#                 _inserir_execucao_planejada(cursor, id_plano_item, ex)
#             continue

#         execucoes_saldo, restante_sem_saldo = _montar_execucoes_por_saldo(qt_romaneio, candidatos)
#         for ex in execucoes_saldo:
#             _inserir_execucao_planejada(cursor, id_plano_item, ex)

#         if restante_sem_saldo > 0.0001:
#             _inserir_execucao_planejada(
#                 cursor,
#                 id_plano_item,
#                 {
#                     "endereco": "SEM ESTOQUE",
#                     "tipo_caixa": "SEM_ESTOQUE",
#                     "qt_caixas": 0,
#                     "mts_por_caixa": 0,
#                     "mts_planejados": restante_sem_saldo,
#                 },
#             )


# def _log_event(cursor, evento, payload, cd_usr=None, nm_usr=None, coletor_id=None,
#                id_plano=None, id_plano_item=None, id_execucao=None):
#     cursor.execute(
#         """
#         INSERT INTO dbo.Stik_WMS_SeparacaoPlanejada_Evento
#             (IdPlano, IdPlanoItem, IdExecucao, Evento, Payload, CdUsr, NmUsr, ColetorId)
#         VALUES (?, ?, ?, ?, ?, ?, ?, ?)
#     """,
#         (
#             id_plano,
#             id_plano_item,
#             id_execucao,
#             evento,
#             json.dumps(_json_safe(payload), ensure_ascii=False),
#             cd_usr,
#             nm_usr,
#             coletor_id,
#         ),
#     )


# def _buscar_plano(cursor, nr_romaneio):
#     cursor.execute(
#         """
#         SELECT IdPlano, NrRomaneio, Status, Versao, CdUsrCriacao, ColetorId,
#                DtCriacao, DtAtualizacao
#         FROM dbo.Stik_WMS_SeparacaoPlanejada WITH (NOLOCK)
#         WHERE NrRomaneio = ?
#     """,
#         (nr_romaneio,),
#     )
#     plano = _row_dict(cursor, cursor.fetchone())
#     if not plano:
#         return None

#     cursor.execute(
#         """
#         SELECT I.IdPlanoItem, I.IdPlano, I.CdVpo, I.CdVpd, I.CdObj, I.Detalhe, I.NmLot,
#                I.Objeto, Setor = ISNULL(Obj.CdObjLin, 0), I.QtRomaneio,
#                I.Status, I.Versao, I.DtCriacao, I.DtAtualizacao
#         FROM dbo.Stik_WMS_SeparacaoPlanejada_Item I WITH (NOLOCK)
#         INNER JOIN dbo.TbObj Obj WITH (NOLOCK) ON Obj.CdObj = I.CdObj
#         WHERE I.IdPlano = ?
#         ORDER BY I.IdPlanoItem
#     """,
#         (plano["IdPlano"],),
#     )
#     itens = _fetch_all_dict(cursor)

#     for item in itens:
#         cursor.execute(
#             """
#             SELECT IdExecucao, IdPlanoItem, Endereco, EnderecoLido, TipoCaixa,
#                    QtCaixasPlanejada, MtsPorCaixa, MtsPlanejados,
#                    QtCaixasConfirmada, MtsConfirmados, QtCaixasCortada,
#                    MtsCortados, PaleteValidado, ItemValidado, Confirmado,
#                    Cortado, MotivoCorte, CdUsr, NmUsr, ColetorId,
#                    BloqueadoAte, Versao, DtCriacao, DtAtualizacao
#             FROM dbo.Stik_WMS_SeparacaoPlanejada_Execucao WITH (NOLOCK)
#             WHERE IdPlanoItem = ?
#             ORDER BY IdExecucao
#         """,
#             (item["IdPlanoItem"],),
#         )
#         item["execucoes"] = _fetch_all_dict(cursor)

#     plano["itens"] = itens
#     return _json_safe(plano)


# def _buscar_execucao(cursor, id_execucao):
#     cursor.execute(
#         """
#         SELECT E.*, I.IdPlano, I.CdVpo, I.CdVpd, I.CdObj, I.Detalhe,
#                I.NmLot, I.Objeto, Setor = ISNULL(Obj.CdObjLin, 0), I.QtRomaneio
#         FROM dbo.Stik_WMS_SeparacaoPlanejada_Execucao E WITH (NOLOCK)
#         INNER JOIN dbo.Stik_WMS_SeparacaoPlanejada_Item I WITH (NOLOCK)
#             ON I.IdPlanoItem = E.IdPlanoItem
#         INNER JOIN dbo.TbObj Obj WITH (NOLOCK) ON Obj.CdObj = I.CdObj
#         WHERE E.IdExecucao = ?
#     """,
#         (id_execucao,),
#     )
#     return _json_safe(_row_dict(cursor, cursor.fetchone()))


# def _erro_conflito(execucao):
#     return jsonify({"error": "Registro atualizado por outro coletor.", "estado_atual": execucao}), 409


# def _validar_versao(execucao, versao):
#     return _to_int(execucao.get("Versao")) == _to_int(versao)


# # Mapeia as siglas compactas do QR da etiqueta (campo "C") para os nomes
# # usados em TipoCaixa da execução (ex.: etiqueta grava "ENF", plano grava
# # "ENFESTADO").
# _TIPO_CAIXA_QR_ABREVIADO = {
#     "ENF": "ENFESTADO",
#     "ENFR": "ENFRALDADO",
#     "P": "P",
#     "G": "G",
#     "D": "D",
# }


# def _validar_qr_execucao(execucao, qr):
#     cd_obj_lido = _to_int(qr.get("CdObj") or qr.get("cdObj") or qr.get("cd_obj"))
#     if cd_obj_lido != _to_int(execucao.get("CdObj")):
#         return False, "CdObj lido não corresponde ao planejado."

#     # "Detalhe" é a chave do QR compacto atual da etiqueta; DetalheId/DetalheID
#     # são mantidas por compatibilidade com formatos antigos.
#     detalhe_lido = (
#         qr.get("Detalhe")
#         or qr.get("DetalheId")
#         or qr.get("DetalheID")
#         or qr.get("detalheId")
#     )
#     if detalhe_lido not in (None, "") and _to_int(detalhe_lido) != _to_int(execucao.get("Detalhe")):
#         return False, "Detalhe lido não corresponde ao planejado."

#     tipo_esperado = _norm(execucao.get("TipoCaixa"))

#     # Execuções "FRACIONADO"/"SEM_ESTOQUE" representam sobra de saldo em
#     # metros, não uma caixa fechada de um tipo específico (P/G/ENF/ENFR) —
#     # foram montadas por _montar_fracionado_restante/_montar_execucoes_por_saldo
#     # sem QtCaixasPlanejada nem MtsPorCaixa. Qualquer caixa física do mesmo
#     # CdObj/Detalhe serve para abater esse saldo, então tipo e metragem da
#     # caixa lida não são comparados ao planejado nesses casos.
#     if tipo_esperado in ("FRACIONADO", "SEM_ESTOQUE"):
#         return True, None

#     # "C" é a chave do QR compacto atual; TipoCaixa/tipoCaixa por compatibilidade.
#     tipo_lido_bruto = _norm(qr.get("C") or qr.get("TipoCaixa") or qr.get("tipoCaixa"))
#     tipo_lido = _TIPO_CAIXA_QR_ABREVIADO.get(tipo_lido_bruto, tipo_lido_bruto)
#     if tipo_lido and tipo_esperado and tipo_lido != tipo_esperado:
#         return False, "Tipo de caixa lido não corresponde ao planejado."

#     mts_lido = qr.get("MetrosCaixa") or qr.get("metrosCaixa")
#     if mts_lido not in (None, ""):
#         if abs(_to_float(mts_lido) - _to_float(execucao.get("MtsPorCaixa"))) > 0.0001:
#             return False, "Metragem da caixa lida não corresponde ao planejado."

#     return True, None


# @wms_separacao_planejada_bp.route("/consulta/wms/separacao-planejada", methods=["GET"])
# def separacao_planejada_buscar():
#     connection = None
#     try:
#         nr_romaneio = _to_int(request.args.get("nr_romaneio"))
#         if nr_romaneio <= 0:
#             return jsonify({"error": "Parâmetro obrigatório: nr_romaneio"}), 400

#         connection = create_connection_tinturaria()
#         if connection is None:
#             return jsonify({"status": "SQL_ERROR", "details": "Falha ao conectar ao banco."}), 500

#         cursor = connection.cursor()
#         cursor.execute("SET NOCOUNT ON; SET XACT_ABORT ON;")
#         plano = _buscar_plano(cursor, nr_romaneio)
#         if not plano:
#             return jsonify({"error": "Plano não encontrado."}), 404
#         linhas_divididas = _dividir_execucoes_caixa_agregadas(cursor, plano["IdPlano"])
#         if linhas_divididas:
#             connection.commit()
#             plano = _buscar_plano(cursor, nr_romaneio)

#         return jsonify({"success": True, "plano": plano}), 200
#     except Exception as e:
#         return jsonify({"error": str(e)}), 500
#     finally:
#         if connection:
#             connection.close()


# @wms_separacao_planejada_bp.route("/consulta/wms/separacao-planejada/gerar", methods=["POST"])
# def separacao_planejada_gerar():
#     connection = None
#     try:
#         data = request.get_json() or {}
#         nr_romaneio = _to_int(data.get("nr_romaneio"))
#         cd_usr = _to_int(data.get("cd_usr") or data.get("usuario_id"), None)
#         nm_usr = (data.get("nm_usr") or data.get("usuario_nome") or "").strip()
#         coletor_id = (data.get("coletor_id") or "").strip()

#         if nr_romaneio <= 0:
#             return jsonify({"error": "Campo obrigatório: nr_romaneio"}), 400

#         connection = create_connection_tinturaria()
#         if connection is None:
#             return jsonify({"status": "SQL_ERROR", "details": "Falha ao conectar ao banco."}), 500

#         cursor = connection.cursor()
#         cursor.execute("SET NOCOUNT ON; SET XACT_ABORT ON;")

#         existente = _buscar_plano(cursor, nr_romaneio)
#         if existente:
#             linhas_divididas = _dividir_execucoes_caixa_agregadas(cursor, existente["IdPlano"])
#             if linhas_divididas:
#                 _log_event(
#                     cursor,
#                     "DIVIDIR_EXECUCOES_CAIXA",
#                     {**data, "linhas_divididas": linhas_divididas},
#                     cd_usr,
#                     nm_usr,
#                     coletor_id,
#                     id_plano=existente["IdPlano"],
#                 )
#                 connection.commit()
#                 existente = _buscar_plano(cursor, nr_romaneio)
#             return jsonify({"success": True, "message": "Plano já existente.", "plano": existente}), 200

#         cursor.execute(
#             """
#             INSERT INTO dbo.Stik_WMS_SeparacaoPlanejada
#                 (NrRomaneio, Status, CdUsrCriacao, ColetorId)
#             OUTPUT INSERTED.IdPlano
#             VALUES (?, 'planejado', ?, ?)
#         """,
#             (nr_romaneio, cd_usr, coletor_id),
#         )
#         id_plano = cursor.fetchone()[0]

#         try:
#             _popular_plano(cursor, id_plano, nr_romaneio)
#         except ValueError as e:
#             connection.rollback()
#             return jsonify({"error": str(e)}), 404

#         _log_event(cursor, "GERAR_PLANO", data, cd_usr, nm_usr, coletor_id, id_plano=id_plano)
#         connection.commit()

#         plano = _buscar_plano(cursor, nr_romaneio)
#         return jsonify({"success": True, "message": "Plano gerado com sucesso.", "plano": plano}), 201
#     except Exception as e:
#         if connection:
#             try:
#                 connection.rollback()
#             except Exception:
#                 pass
#         return jsonify({"error": str(e)}), 500
#     finally:
#         if connection:
#             connection.close()


# @wms_separacao_planejada_bp.route("/consulta/wms/separacao-planejada/obter-ou-gerar", methods=["POST"])
# def separacao_planejada_obter_ou_gerar():
#     return separacao_planejada_gerar()


# @wms_separacao_planejada_bp.route("/consulta/wms/separacao-planejada/recalcular", methods=["PATCH"])
# def separacao_planejada_recalcular():
#     connection = None
#     try:
#         data = request.get_json() or {}
#         nr_romaneio = _to_int(data.get("nr_romaneio"))
#         cd_usr = _to_int(data.get("cd_usr") or data.get("usuario_id"), None)
#         nm_usr = (data.get("nm_usr") or data.get("usuario_nome") or "").strip()
#         coletor_id = (data.get("coletor_id") or "").strip()

#         if nr_romaneio <= 0:
#             return jsonify({"error": "Campo obrigatório: nr_romaneio"}), 400

#         connection = create_connection_tinturaria()
#         cursor = connection.cursor()
#         cursor.execute("SET NOCOUNT ON; SET XACT_ABORT ON;")

#         cursor.execute(
#             """
#             SELECT IdPlano, Status
#             FROM dbo.Stik_WMS_SeparacaoPlanejada WITH (UPDLOCK, HOLDLOCK)
#             WHERE NrRomaneio = ?
#         """,
#             (nr_romaneio,),
#         )
#         plano = _row_dict(cursor, cursor.fetchone())
#         if not plano:
#             return jsonify({"error": "Plano não encontrado."}), 404
#         if plano.get("Status") in ("finalizado", "enviado_conferencia"):
#             return jsonify({"error": "Plano finalizado não pode ser recalculado."}), 400

#         cursor.execute(
#             """
#             SELECT Qtd = COUNT(1)
#             FROM dbo.Stik_WMS_SeparacaoPlanejada_Execucao E WITH (NOLOCK)
#             INNER JOIN dbo.Stik_WMS_SeparacaoPlanejada_Item I WITH (NOLOCK)
#                 ON I.IdPlanoItem = E.IdPlanoItem
#             WHERE I.IdPlano = ?
#               AND (
#                     ISNULL(E.PaleteValidado, 0) = 1 OR
#                     ISNULL(E.ItemValidado, 0) = 1 OR
#                     ISNULL(E.Confirmado, 0) = 1 OR
#                     ISNULL(E.Cortado, 0) = 1
#               )
#         """,
#             (plano["IdPlano"],),
#         )
#         execucoes_iniciadas = _to_int(cursor.fetchone()[0])
#         if execucoes_iniciadas > 0:
#             return jsonify({
#                 "error": "Plano já iniciado não pode ser recalculado sem preservar a execução."
#             }), 400

#         cursor.execute(
#             """
#             DELETE E
#             FROM dbo.Stik_WMS_SeparacaoPlanejada_Execucao E
#             INNER JOIN dbo.Stik_WMS_SeparacaoPlanejada_Item I
#                 ON I.IdPlanoItem = E.IdPlanoItem
#             WHERE I.IdPlano = ?
#         """,
#             (plano["IdPlano"],),
#         )
#         cursor.execute(
#             """
#             DELETE FROM dbo.Stik_WMS_SeparacaoPlanejada_Item
#             WHERE IdPlano = ?
#         """,
#             (plano["IdPlano"],),
#         )
#         try:
#             _popular_plano(cursor, plano["IdPlano"], nr_romaneio)
#         except ValueError as e:
#             connection.rollback()
#             return jsonify({"error": str(e)}), 404

#         cursor.execute(
#             """
#             UPDATE dbo.Stik_WMS_SeparacaoPlanejada
#             SET Versao = Versao + 1, DtAtualizacao = GETDATE()
#             WHERE IdPlano = ?
#         """,
#             (plano["IdPlano"],),
#         )

#         _log_event(cursor, "RECALCULAR_PLANO", data, cd_usr, nm_usr, coletor_id, id_plano=plano["IdPlano"])
#         connection.commit()
#         return jsonify({"success": True, "message": "Plano recalculado.", "plano": _buscar_plano(cursor, nr_romaneio)}), 200
#     except Exception as e:
#         if connection:
#             try:
#                 connection.rollback()
#             except Exception:
#                 pass
#         return jsonify({"error": str(e)}), 500
#     finally:
#         if connection:
#             connection.close()


# @wms_separacao_planejada_bp.route("/consulta/wms/separacao-planejada/item/recalcular", methods=["PATCH"])
# def separacao_planejada_item_recalcular():
#     """Recalcula as execuções de UM item do plano (por nr_romaneio + cd_obj +
#     detalhe), preservando os demais itens do mesmo plano já iniciados —
#     diferente de /recalcular, que apaga o plano inteiro."""
#     connection = None
#     try:
#         data = request.get_json() or {}
#         nr_romaneio = _to_int(data.get("nr_romaneio"))
#         cd_obj = _to_int(data.get("cd_obj") or data.get("CdObj"))
#         detalhe = _to_int(data.get("detalhe") or data.get("Detalhe"))
#         cd_usr = _to_int(data.get("cd_usr") or data.get("usuario_id"), None)
#         nm_usr = (data.get("nm_usr") or data.get("usuario_nome") or "").strip()
#         coletor_id = (data.get("coletor_id") or "").strip()

#         if nr_romaneio <= 0 or cd_obj <= 0:
#             return jsonify({"error": "Campos obrigatórios: nr_romaneio, cd_obj"}), 400

#         connection = create_connection_tinturaria()
#         cursor = connection.cursor()
#         cursor.execute("SET NOCOUNT ON; SET XACT_ABORT ON;")

#         cursor.execute(
#             """
#             SELECT I.IdPlanoItem, I.IdPlano, I.CdObj, I.Detalhe, I.Objeto, I.QtRomaneio, P.Status
#             FROM dbo.Stik_WMS_SeparacaoPlanejada_Item I WITH (UPDLOCK, HOLDLOCK)
#             INNER JOIN dbo.Stik_WMS_SeparacaoPlanejada P WITH (UPDLOCK, HOLDLOCK) ON P.IdPlano = I.IdPlano
#             WHERE P.NrRomaneio = ? AND I.CdObj = ? AND ISNULL(I.Detalhe, 0) = ISNULL(?, 0)
#             """,
#             (nr_romaneio, cd_obj, detalhe),
#         )
#         item = _row_dict(cursor, cursor.fetchone())
#         if not item:
#             return jsonify({"error": "Item do plano não encontrado."}), 404
#         if item.get("Status") in ("finalizado", "enviado_conferencia"):
#             return jsonify({"error": "Plano finalizado não pode ser recalculado."}), 400

#         id_plano_item = item["IdPlanoItem"]

#         cursor.execute(
#             """
#             SELECT Qtd = COUNT(1)
#             FROM dbo.Stik_WMS_SeparacaoPlanejada_Execucao WITH (NOLOCK)
#             WHERE IdPlanoItem = ?
#               AND (
#                     ISNULL(PaleteValidado, 0) = 1 OR
#                     ISNULL(ItemValidado, 0) = 1 OR
#                     ISNULL(Confirmado, 0) = 1 OR
#                     ISNULL(Cortado, 0) = 1
#               )
#             """,
#             (id_plano_item,),
#         )
#         execucoes_iniciadas = _to_int(cursor.fetchone()[0])
#         if execucoes_iniciadas > 0:
#             return jsonify({
#                 "error": "Item já iniciado não pode ser recalculado sem preservar a execução."
#             }), 400

#         cursor.execute(
#             "DELETE FROM dbo.Stik_WMS_SeparacaoPlanejada_Execucao WHERE IdPlanoItem = ?",
#             (id_plano_item,),
#         )

#         _gerar_execucoes_para_item(
#             cursor,
#             id_plano_item,
#             item.get("CdObj"),
#             item.get("Detalhe"),
#             item.get("Objeto"),
#             _to_float(item.get("QtRomaneio")),
#         )

#         cursor.execute(
#             "UPDATE dbo.Stik_WMS_SeparacaoPlanejada SET Versao = Versao + 1, DtAtualizacao = GETDATE() WHERE IdPlano = ?",
#             (item["IdPlano"],),
#         )

#         _log_event(
#             cursor, "RECALCULAR_ITEM", data, cd_usr, nm_usr, coletor_id,
#             id_plano=item["IdPlano"], id_plano_item=id_plano_item,
#         )
#         connection.commit()
#         return jsonify({
#             "success": True,
#             "message": "Item recalculado.",
#             "plano": _buscar_plano(cursor, nr_romaneio),
#         }), 200
#     except Exception as e:
#         if connection:
#             try:
#                 connection.rollback()
#             except Exception:
#                 pass
#         return jsonify({"error": str(e)}), 500
#     finally:
#         if connection:
#             connection.close()


# @wms_separacao_planejada_bp.route("/consulta/wms/separacao-planejada/execucao/assumir", methods=["PATCH"])
# def separacao_planejada_assumir():
#     connection = None
#     try:
#         data = request.get_json() or {}
#         id_execucao = _to_int(data.get("id_execucao"))
#         versao = _to_int(data.get("versao"), None)
#         cd_usr = _to_int(data.get("cd_usr") or data.get("usuario_id"), None)
#         nm_usr = (data.get("nm_usr") or data.get("usuario_nome") or "").strip()
#         coletor_id = (data.get("coletor_id") or "").strip()

#         if id_execucao <= 0 or versao is None:
#             return jsonify({"error": "Campos obrigatórios: id_execucao, versao"}), 400

#         connection = create_connection_tinturaria()
#         cursor = connection.cursor()
#         cursor.execute("SET NOCOUNT ON; SET XACT_ABORT ON;")

#         execucao = _buscar_execucao(cursor, id_execucao)
#         if not execucao:
#             return jsonify({"error": "Execução não encontrada."}), 404
#         if not _validar_versao(execucao, versao):
#             return _erro_conflito(execucao)

#         bloqueado_ate = execucao.get("BloqueadoAte")
#         coletor_atual = (execucao.get("ColetorId") or "").strip()
#         if bloqueado_ate and coletor_atual and coletor_atual != coletor_id:
#             bloqueado_ate_dt = datetime.datetime.fromisoformat(bloqueado_ate) if isinstance(bloqueado_ate, str) else bloqueado_ate
#             if bloqueado_ate_dt > datetime.datetime.now():
#                 return jsonify({"error": "Execução em uso por outro coletor.", "estado_atual": execucao}), 423

#         novo_bloqueio = datetime.datetime.now() + datetime.timedelta(minutes=5)
#         cursor.execute(
#             """
#             UPDATE dbo.Stik_WMS_SeparacaoPlanejada_Execucao
#             SET CdUsr = ?, NmUsr = ?, ColetorId = ?, BloqueadoAte = ?,
#                 Versao = Versao + 1, DtAtualizacao = GETDATE()
#             WHERE IdExecucao = ?
#         """,
#             (cd_usr, nm_usr, coletor_id, novo_bloqueio, id_execucao),
#         )

#         _log_event(cursor, "ASSUMIR_EXECUCAO", data, cd_usr, nm_usr, coletor_id, id_execucao=id_execucao)
#         connection.commit()
#         return jsonify({"success": True, "message": "Execução assumida.", "execucao": _buscar_execucao(cursor, id_execucao)}), 200
#     except Exception as e:
#         if connection:
#             try:
#                 connection.rollback()
#             except Exception:
#                 pass
#         return jsonify({"error": str(e)}), 500
#     finally:
#         if connection:
#             connection.close()


# @wms_separacao_planejada_bp.route("/consulta/wms/separacao-planejada/execucao/validar-palete", methods=["PATCH"])
# def separacao_planejada_validar_palete():
#     connection = None
#     try:
#         data = request.get_json() or {}
#         id_execucao = _to_int(data.get("id_execucao"))
#         endereco_lido = _norm(data.get("endereco_lido"))
#         versao = _to_int(data.get("versao"), None)
#         cd_usr = _to_int(data.get("cd_usr") or data.get("usuario_id"), None)
#         nm_usr = (data.get("nm_usr") or data.get("usuario_nome") or "").strip()
#         coletor_id = (data.get("coletor_id") or "").strip()

#         if id_execucao <= 0 or not endereco_lido or versao is None:
#             return jsonify({"error": "Campos obrigatórios: id_execucao, endereco_lido, versao"}), 400

#         connection = create_connection_tinturaria()
#         cursor = connection.cursor()
#         cursor.execute("SET NOCOUNT ON; SET XACT_ABORT ON;")
#         execucao = _buscar_execucao(cursor, id_execucao)
#         if not execucao:
#             return jsonify({"error": "Execução não encontrada."}), 404
#         if not _validar_versao(execucao, versao):
#             return _erro_conflito(execucao)

#         esperado = _norm(execucao.get("Endereco"))
#         if endereco_lido != esperado:
#             return jsonify({"error": "Palete lido não corresponde ao planejado.", "esperado": esperado, "lido": endereco_lido}), 400

#         cursor.execute(
#             """
#             UPDATE dbo.Stik_WMS_SeparacaoPlanejada_Execucao
#             SET EnderecoLido = ?, PaleteValidado = 1, CdUsr = ?, NmUsr = ?,
#                 ColetorId = ?, Versao = Versao + 1, DtAtualizacao = GETDATE()
#             WHERE IdExecucao = ?
#         """,
#             (endereco_lido, cd_usr, nm_usr, coletor_id, id_execucao),
#         )
#         _log_event(cursor, "VALIDAR_PALETE", data, cd_usr, nm_usr, coletor_id, id_execucao=id_execucao)
#         connection.commit()
#         return jsonify({"success": True, "message": "Palete validado.", "execucao": _buscar_execucao(cursor, id_execucao)}), 200
#     except Exception as e:
#         if connection:
#             try:
#                 connection.rollback()
#             except Exception:
#                 pass
#         return jsonify({"error": str(e)}), 500
#     finally:
#         if connection:
#             connection.close()


# @wms_separacao_planejada_bp.route("/consulta/wms/separacao-planejada/execucao/validar-item", methods=["PATCH"])
# def separacao_planejada_validar_item():
#     connection = None
#     try:
#         data = request.get_json() or {}
#         id_execucao = _to_int(data.get("id_execucao"))
#         qr = data.get("qr") or {}
#         versao = _to_int(data.get("versao"), None)
#         cd_usr = _to_int(data.get("cd_usr") or data.get("usuario_id"), None)
#         nm_usr = (data.get("nm_usr") or data.get("usuario_nome") or "").strip()
#         coletor_id = (data.get("coletor_id") or "").strip()

#         if id_execucao <= 0 or not isinstance(qr, dict) or versao is None:
#             return jsonify({"error": "Campos obrigatórios: id_execucao, qr, versao"}), 400

#         connection = create_connection_tinturaria()
#         cursor = connection.cursor()
#         cursor.execute("SET NOCOUNT ON; SET XACT_ABORT ON;")
#         execucao = _buscar_execucao(cursor, id_execucao)
#         if not execucao:
#             return jsonify({"error": "Execução não encontrada."}), 404
#         if not _validar_versao(execucao, versao):
#             return _erro_conflito(execucao)

#         ok, erro = _validar_qr_execucao(execucao, qr)
#         if not ok:
#             return jsonify({"error": erro, "esperado": {"CdObj": execucao.get("CdObj"), "Detalhe": execucao.get("Detalhe"), "TipoCaixa": execucao.get("TipoCaixa"), "MtsPorCaixa": execucao.get("MtsPorCaixa")}, "lido": qr}), 400

#         # CX = código único da caixa física lida (campo "CX" do QR da etiqueta).
#         # LI = lote de impressão (campo "LI" do QR), agrupa N caixas impressas
#         # juntas. Quando o QR traz LI, ele SUBSTITUI o CX como chave de
#         # identificação da leitura (bloqueio de duplicidade e consumo da
#         # caixa passam a girar em torno do lote, não da unidade); sem LI,
#         # o comportamento é exatamente o de sempre, por CX.
#         li_lido = (qr.get("LI") or qr.get("li") or "").strip() or None
#         cx_lido = (qr.get("CX") or qr.get("cx") or "").strip() or None
#         usar_li = li_lido is not None
#         chave = li_lido if usar_li else cx_lido

#         if chave:
#             # Cada chave (CX ou, quando presente, LI) só pode ser lida uma
#             # vez, mesmo que outra execução seja do mesmo CdObj+Detalhe.
#             # Bloqueia se já estiver em uso (validada, ainda pendente) em
#             # outra execução...
#             campo_chave = "LiLido" if usar_li else "CxLido"
#             cursor.execute(
#                 f"""
#                 SELECT TOP 1 IdExecucao
#                 FROM dbo.Stik_WMS_SeparacaoPlanejada_Execucao WITH (NOLOCK)
#                 WHERE {campo_chave} = ?
#                   AND IdExecucao <> ?
#                   AND ISNULL(ItemValidado, 0) = 1
#                   AND ISNULL(Confirmado, 0) = 0
#                 """,
#                 (chave, id_execucao),
#             )
#             outra_execucao = cursor.fetchone()
#             if outra_execucao:
#                 rotulo = f"lote (LI {chave})" if usar_li else f"caixa (CX {chave})"
#                 return jsonify({
#                     "error": f"Essa {rotulo} já foi lida em outra execução (ID {outra_execucao[0]}).",
#                 }), 409

#             # ...ou já tiver sido consumida (confirmada) em qualquer separação.
#             campo_caixa = "LI" if usar_li else "CX"
#             cursor.execute(
#                 f"SELECT TOP 1 Status FROM dbo.Stik_WMS_Caixa WITH (NOLOCK) WHERE {campo_caixa} = ?",
#                 (chave,),
#             )
#             caixa_row = cursor.fetchone()
#             if caixa_row and (caixa_row[0] or "").strip().upper() == "CONSUMIDA":
#                 rotulo = f"lote (LI {chave})" if usar_li else f"caixa (CX {chave})"
#                 return jsonify({
#                     "error": f"Essa {rotulo} já foi consumida em outra separação.",
#                 }), 409

#         cursor.execute(
#             """
#             UPDATE dbo.Stik_WMS_SeparacaoPlanejada_Execucao
#             SET ItemValidado = 1, CxLido = ?, LiLido = ?, CdUsr = ?, NmUsr = ?, ColetorId = ?,
#                 Versao = Versao + 1, DtAtualizacao = GETDATE()
#             WHERE IdExecucao = ?
#         """,
#             (None if usar_li else cx_lido, li_lido if usar_li else None, cd_usr, nm_usr, coletor_id, id_execucao),
#         )
#         _log_event(cursor, "VALIDAR_ITEM", data, cd_usr, nm_usr, coletor_id, id_execucao=id_execucao)
#         connection.commit()
#         return jsonify({"success": True, "message": "Item validado.", "execucao": _buscar_execucao(cursor, id_execucao)}), 200
#     except Exception as e:
#         if connection:
#             try:
#                 connection.rollback()
#             except Exception:
#                 pass
#         return jsonify({"error": str(e)}), 500
#     finally:
#         if connection:
#             connection.close()


# @wms_separacao_planejada_bp.route("/consulta/wms/separacao-planejada/execucao/confirmar", methods=["PATCH"])
# def separacao_planejada_confirmar():
#     connection = None
#     try:
#         data = request.get_json() or {}
#         id_execucao = _to_int(data.get("id_execucao"))
#         versao = _to_int(data.get("versao"), None)
#         qt_caixas = _to_int(data.get("quantidade_caixas_confirmada") or data.get("qt_caixas_confirmada"))
#         mts_confirmados = _to_float(data.get("metros_confirmados") or data.get("mts_confirmados"))
#         cd_usr = _to_int(data.get("cd_usr") or data.get("usuario_id"), None)
#         nm_usr = (data.get("nm_usr") or data.get("usuario_nome") or "").strip()
#         coletor_id = (data.get("coletor_id") or "").strip()

#         if id_execucao <= 0 or versao is None:
#             return jsonify({"error": "Campos obrigatórios: id_execucao, versao"}), 400

#         connection = create_connection_tinturaria()
#         cursor = connection.cursor()
#         cursor.execute("SET NOCOUNT ON; SET XACT_ABORT ON;")
#         execucao = _buscar_execucao(cursor, id_execucao)
#         if not execucao:
#             return jsonify({"error": "Execução não encontrada."}), 404
#         if not _validar_versao(execucao, versao):
#             return _erro_conflito(execucao)
#         if execucao.get("Confirmado"):
#             return jsonify({"error": "Execução já confirmada.", "estado_atual": execucao}), 409
#         if not execucao.get("PaleteValidado"):
#             return jsonify({"error": "Valide o palete antes de confirmar."}), 400
#         if not execucao.get("ItemValidado"):
#             return jsonify({"error": "Valide o item antes de confirmar."}), 400

#         if mts_confirmados <= 0:
#             mts_confirmados = _to_float(execucao.get("MtsPlanejados"))
#         if mts_confirmados > _to_float(execucao.get("MtsPlanejados")) + 0.0001:
#             return jsonify({"error": "Metros confirmados não podem superar o planejado."}), 400

#         endereco = _norm(execucao.get("EnderecoLido") or execucao.get("Endereco"))
#         cod_sku = _to_int(execucao.get("CdObj"))
#         detalhe = _to_int(execucao.get("Detalhe"))
#         tipo = _norm(execucao.get("TipoCaixa"))

#         cursor.execute(
#             """
#             INSERT INTO dbo.Stik_WMS_Movimento
#                 (Endereco, CodSKU, Detalhe, TpMov, QtMovida, CdUsr, Origem, Observacao, DataMovimento)
#             VALUES (?, ?, ?, 2, ?, ?, 'SEPARACAO_PLANEJADA', 'Saída separação planejada', GETDATE())
#         """,
#             (endereco, cod_sku, detalhe, mts_confirmados, cd_usr),
#         )

#         qt_p = qt_g = qt_enf = qt_enfr = 0
#         if tipo == "P":
#             qt_p = qt_caixas
#         elif tipo == "G":
#             qt_g = qt_caixas
#         elif tipo == "ENFESTADO":
#             qt_enf = qt_caixas
#         elif tipo == "ENFRALDADO":
#             qt_enfr = qt_caixas

#         if qt_p or qt_g or qt_enf or qt_enfr:
#             cursor.execute(
#                 """
#                 UPDATE dbo.Stik_WMS_Alocacao_Embalagem
#                 SET QtCaixaP = CASE WHEN QtCaixaP - ? < 0 THEN 0 ELSE QtCaixaP - ? END,
#                     QtCaixaG = CASE WHEN QtCaixaG - ? < 0 THEN 0 ELSE QtCaixaG - ? END,
#                     QtEnfestado = CASE WHEN QtEnfestado - ? < 0 THEN 0 ELSE QtEnfestado - ? END,
#                     QtEnfraldado = CASE WHEN QtEnfraldado - ? < 0 THEN 0 ELSE QtEnfraldado - ? END,
#                     DtAtualizacao = GETDATE()
#                 WHERE UPPER(LTRIM(RTRIM(Endereco))) = ?
#                   AND CodSKU = ?
#                   AND ISNULL(Detalhe, 0) = ISNULL(?, 0)
#             """,
#                 (qt_p, qt_p, qt_g, qt_g, qt_enf, qt_enf, qt_enfr, qt_enfr, endereco, cod_sku, detalhe),
#             )
#             cursor.execute(
#                 """
#                 INSERT INTO dbo.Stik_WMS_Movimento_Embalagem
#                     (EnderecoOrigem, EnderecoDestino, CodSKU, Detalhe, TpMov,
#                      QtCaixaP, QtCaixaG, QtEnfestado, QtEnfraldado,
#                      QtMovidaMetro, CdUsr, Origem, Observacao, DataMovimento)
#                 VALUES (?, NULL, ?, ?, 2, ?, ?, ?, ?, ?, ?, 'SEPARACAO_PLANEJADA', 'Saída embalagem separação planejada', GETDATE())
#             """,
#                 (endereco, cod_sku, detalhe, qt_p, qt_g, qt_enf, qt_enfr, mts_confirmados, cd_usr),
#             )

#         # Marca a caixa física (CX ou, quando a leitura foi por lote, LI)
#         # como consumida, mantendo Stik_WMS_Caixa refletindo o que ainda está
#         # disponível no armazém. Melhor esforço: se a chave não estiver
#         # cadastrada (ex.: alocação anterior a essa funcionalidade), não
#         # bloqueia a confirmação.
#         cx_lido = (execucao.get("CxLido") or "").strip()
#         li_lido = (execucao.get("LiLido") or "").strip()
#         if li_lido and tipo in ("P", "G"):
#             cursor.execute(
#                 """
#                 UPDATE dbo.Stik_WMS_Caixa
#                 SET Status = 'CONSUMIDA', IdExecucao = ?, DataConsumo = GETDATE()
#                 WHERE LI = ? AND Status = 'DISPONIVEL'
#                 """,
#                 (id_execucao, li_lido),
#             )
#         elif cx_lido and tipo in ("P", "G"):
#             cursor.execute(
#                 """
#                 UPDATE dbo.Stik_WMS_Caixa
#                 SET Status = 'CONSUMIDA', IdExecucao = ?, DataConsumo = GETDATE()
#                 WHERE CX = ? AND Status = 'DISPONIVEL'
#                 """,
#                 (id_execucao, cx_lido),
#             )

#         cursor.execute(
#             """
#             UPDATE dbo.Stik_WMS_SeparacaoPlanejada_Execucao
#             SET QtCaixasConfirmada = ?, MtsConfirmados = ?, Confirmado = 1,
#                 CdUsr = ?, NmUsr = ?, ColetorId = ?, Versao = Versao + 1,
#                 DtAtualizacao = GETDATE()
#             WHERE IdExecucao = ?
#         """,
#             (qt_caixas, mts_confirmados, cd_usr, nm_usr, coletor_id, id_execucao),
#         )

#         _log_event(cursor, "CONFIRMAR_EXECUCAO", data, cd_usr, nm_usr, coletor_id, id_execucao=id_execucao)
#         connection.commit()
#         return jsonify({"success": True, "message": "Separação confirmada.", "execucao": _buscar_execucao(cursor, id_execucao)}), 200
#     except Exception as e:
#         if connection:
#             try:
#                 connection.rollback()
#             except Exception:
#                 pass
#         return jsonify({"error": str(e)}), 500
#     finally:
#         if connection:
#             connection.close()


# @wms_separacao_planejada_bp.route("/consulta/wms/separacao-planejada/execucao/reiniciar", methods=["PATCH"])
# def separacao_planejada_reiniciar_execucao():
#     connection = None
#     try:
#         data = request.get_json() or {}
#         id_execucao = _to_int(data.get("id_execucao"))
#         versao = _to_int(data.get("versao"), None)
#         cd_usr = _to_int(data.get("cd_usr") or data.get("usuario_id"), None)
#         nm_usr = (data.get("nm_usr") or data.get("usuario_nome") or "").strip()
#         coletor_id = (data.get("coletor_id") or "").strip()

#         if id_execucao <= 0 or versao is None:
#             return jsonify({"error": "Campos obrigatórios: id_execucao, versao"}), 400

#         connection = create_connection_tinturaria()
#         cursor = connection.cursor()
#         cursor.execute("SET NOCOUNT ON; SET XACT_ABORT ON;")

#         execucao = _buscar_execucao(cursor, id_execucao)
#         if not execucao:
#             return jsonify({"error": "Execução não encontrada."}), 404
#         if not _validar_versao(execucao, versao):
#             return _erro_conflito(execucao)

#         endereco = _norm(execucao.get("EnderecoLido") or execucao.get("Endereco"))
#         cod_sku = _to_int(execucao.get("CdObj"))
#         detalhe = _to_int(execucao.get("Detalhe"))
#         mts_confirmados = _to_float(execucao.get("MtsConfirmados"))
#         qt_caixas = _to_int(execucao.get("QtCaixasConfirmada"))
#         tipo = _norm(execucao.get("TipoCaixa"))

#         if execucao.get("Confirmado") and mts_confirmados > 0:
#             cursor.execute(
#                 """
#                 INSERT INTO dbo.Stik_WMS_Movimento
#                     (Endereco, CodSKU, Detalhe, TpMov, QtMovida, CdUsr, Origem, Observacao, DataMovimento)
#                 VALUES (?, ?, ?, 1, ?, ?, 'SEPARACAO_PLANEJADA_ESTORNO', 'Estorno separação planejada', GETDATE())
#             """,
#                 (endereco, cod_sku, detalhe, mts_confirmados, cd_usr),
#             )

#             qt_p = qt_g = qt_enf = qt_enfr = 0
#             if tipo == "P":
#                 qt_p = qt_caixas
#             elif tipo == "G":
#                 qt_g = qt_caixas
#             elif tipo == "ENFESTADO":
#                 qt_enf = qt_caixas
#             elif tipo == "ENFRALDADO":
#                 qt_enfr = qt_caixas

#             if qt_p or qt_g or qt_enf or qt_enfr:
#                 cursor.execute(
#                     """
#                     UPDATE dbo.Stik_WMS_Alocacao_Embalagem
#                     SET QtCaixaP = ISNULL(QtCaixaP, 0) + ?,
#                         QtCaixaG = ISNULL(QtCaixaG, 0) + ?,
#                         QtEnfestado = ISNULL(QtEnfestado, 0) + ?,
#                         QtEnfraldado = ISNULL(QtEnfraldado, 0) + ?,
#                         DtAtualizacao = GETDATE()
#                     WHERE UPPER(LTRIM(RTRIM(Endereco))) = ?
#                       AND CodSKU = ?
#                       AND ISNULL(Detalhe, 0) = ISNULL(?, 0)
#                 """,
#                     (qt_p, qt_g, qt_enf, qt_enfr, endereco, cod_sku, detalhe),
#                 )
#                 if cursor.rowcount == 0:
#                     cursor.execute(
#                         """
#                         INSERT INTO dbo.Stik_WMS_Alocacao_Embalagem
#                             (Endereco, CodSKU, Detalhe, QtCaixaP, QtCaixaG, QtEnfestado, QtEnfraldado, DtAtualizacao)
#                         VALUES (?, ?, ?, ?, ?, ?, ?, GETDATE())
#                     """,
#                         (endereco, cod_sku, detalhe, qt_p, qt_g, qt_enf, qt_enfr),
#                     )

#                 cursor.execute(
#                     """
#                     INSERT INTO dbo.Stik_WMS_Movimento_Embalagem
#                         (EnderecoOrigem, EnderecoDestino, CodSKU, Detalhe, TpMov,
#                          QtCaixaP, QtCaixaG, QtEnfestado, QtEnfraldado,
#                          QtMovidaMetro, CdUsr, Origem, Observacao, DataMovimento)
#                     VALUES (NULL, ?, ?, ?, 1, ?, ?, ?, ?, ?, ?, 'SEPARACAO_PLANEJADA_ESTORNO', 'Estorno embalagem separação planejada', GETDATE())
#                 """,
#                     (endereco, cod_sku, detalhe, qt_p, qt_g, qt_enf, qt_enfr, mts_confirmados, cd_usr),
#                 )

#             # Devolve a caixa física (ou o lote, se a leitura foi por LI)
#             # consumida na confirmação de volta para disponível, já que a
#             # separação está sendo desfeita.
#             cx_lido = (execucao.get("CxLido") or "").strip()
#             li_lido = (execucao.get("LiLido") or "").strip()
#             if li_lido:
#                 cursor.execute(
#                     """
#                     UPDATE dbo.Stik_WMS_Caixa
#                     SET Status = 'DISPONIVEL', IdExecucao = NULL, DataConsumo = NULL
#                     WHERE LI = ? AND IdExecucao = ?
#                     """,
#                     (li_lido, id_execucao),
#                 )
#             elif cx_lido:
#                 cursor.execute(
#                     """
#                     UPDATE dbo.Stik_WMS_Caixa
#                     SET Status = 'DISPONIVEL', IdExecucao = NULL, DataConsumo = NULL
#                     WHERE CX = ? AND IdExecucao = ?
#                     """,
#                     (cx_lido, id_execucao),
#                 )

#         cursor.execute(
#             """
#             UPDATE dbo.Stik_WMS_SeparacaoPlanejada_Execucao
#             SET EnderecoLido = NULL,
#                 CxLido = NULL,
#                 LiLido = NULL,
#                 PaleteValidado = 0,
#                 ItemValidado = 0,
#                 Confirmado = 0,
#                 Cortado = 0,
#                 QtCaixasConfirmada = 0,
#                 MtsConfirmados = 0,
#                 QtCaixasCortada = 0,
#                 MtsCortados = 0,
#                 MotivoCorte = NULL,
#                 CdUsr = ?,
#                 NmUsr = ?,
#                 ColetorId = ?,
#                 BloqueadoAte = NULL,
#                 Versao = Versao + 1,
#                 DtAtualizacao = GETDATE()
#             WHERE IdExecucao = ?
#         """,
#             (cd_usr, nm_usr, coletor_id, id_execucao),
#         )

#         _log_event(cursor, "REINICIAR_EXECUCAO", data, cd_usr, nm_usr, coletor_id, id_execucao=id_execucao)
#         connection.commit()
#         return jsonify({"success": True, "message": "Execução reiniciada.", "execucao": _buscar_execucao(cursor, id_execucao)}), 200
#     except Exception as e:
#         if connection:
#             try:
#                 connection.rollback()
#             except Exception:
#                 pass
#         return jsonify({"error": str(e)}), 500
#     finally:
#         if connection:
#             connection.close()


# @wms_separacao_planejada_bp.route("/consulta/wms/separacao-planejada/execucao/cortar", methods=["PATCH"])
# def separacao_planejada_cortar():
#     connection = None
#     try:
#         data = request.get_json() or {}
#         id_execucao = _to_int(data.get("id_execucao"))
#         versao = _to_int(data.get("versao"), None)
#         mts_cortados = _to_float(data.get("metros_cortados") or data.get("mts_cortados"))
#         qt_caixas = _to_int(data.get("quantidade_caixas_cortada") or data.get("qt_caixas_cortada"))
#         motivo = (data.get("motivo") or "").strip()
#         cd_usr = _to_int(data.get("cd_usr") or data.get("usuario_id"), None)
#         nm_usr = (data.get("nm_usr") or data.get("usuario_nome") or "").strip()
#         coletor_id = (data.get("coletor_id") or "").strip()

#         if id_execucao <= 0 or versao is None:
#             return jsonify({"error": "Campos obrigatórios: id_execucao, versao"}), 400
#         if not motivo:
#             return jsonify({"error": "Campo obrigatório: motivo"}), 400

#         connection = create_connection_tinturaria()
#         cursor = connection.cursor()
#         cursor.execute("SET NOCOUNT ON; SET XACT_ABORT ON;")
#         execucao = _buscar_execucao(cursor, id_execucao)
#         if not execucao:
#             return jsonify({"error": "Execução não encontrada."}), 404
#         if not _validar_versao(execucao, versao):
#             return _erro_conflito(execucao)
#         if execucao.get("Confirmado"):
#             return jsonify({"error": "Execução confirmada não pode ser cortada."}), 409

#         if mts_cortados <= 0:
#             mts_cortados = _to_float(execucao.get("MtsPlanejados"))
#         if mts_cortados > _to_float(execucao.get("MtsPlanejados")) + 0.0001:
#             return jsonify({"error": "Metros cortados não podem superar o planejado."}), 400

#         cursor.execute(
#             """
#             UPDATE dbo.Stik_WMS_SeparacaoPlanejada_Execucao
#             SET QtCaixasCortada = ?, MtsCortados = ?, Cortado = 1,
#                 MotivoCorte = ?, CdUsr = ?, NmUsr = ?, ColetorId = ?,
#                 Versao = Versao + 1, DtAtualizacao = GETDATE()
#             WHERE IdExecucao = ?
#         """,
#             (qt_caixas, mts_cortados, motivo, cd_usr, nm_usr, coletor_id, id_execucao),
#         )
#         _log_event(cursor, "CORTAR_EXECUCAO", data, cd_usr, nm_usr, coletor_id, id_execucao=id_execucao)
#         connection.commit()
#         return jsonify({"success": True, "message": "Corte registrado.", "execucao": _buscar_execucao(cursor, id_execucao)}), 200
#     except Exception as e:
#         if connection:
#             try:
#                 connection.rollback()
#             except Exception:
#                 pass
#         return jsonify({"error": str(e)}), 500
#     finally:
#         if connection:
#             connection.close()


# @wms_separacao_planejada_bp.route("/consulta/wms/separacao-planejada/enviar-conferencia", methods=["POST"])
# def separacao_planejada_enviar_conferencia():
#     connection = None
#     try:
#         data = request.get_json() or {}
#         nr_romaneio = _to_int(data.get("nr_romaneio"))
#         cd_usr = _to_int(data.get("cd_usr") or data.get("usuario_id"), None)
#         nm_usr = (data.get("nm_usr") or data.get("usuario_nome") or "").strip()
#         coletor_id = (data.get("coletor_id") or "").strip()

#         if nr_romaneio <= 0:
#             return jsonify({"error": "Campo obrigatório: nr_romaneio"}), 400

#         connection = create_connection_tinturaria()
#         cursor = connection.cursor()
#         cursor.execute("SET NOCOUNT ON; SET XACT_ABORT ON;")
#         cursor.execute(
#             """
#             SELECT IdPlano, Status
#             FROM dbo.Stik_WMS_SeparacaoPlanejada WITH (UPDLOCK, HOLDLOCK)
#             WHERE NrRomaneio = ?
#         """,
#             (nr_romaneio,),
#         )
#         plano = _row_dict(cursor, cursor.fetchone())
#         if not plano:
#             return jsonify({"error": "Plano não encontrado."}), 404

#         cursor.execute(
#             """
#             SELECT E.IdExecucao, I.CdObj, I.Detalhe, I.NmLot, E.Endereco
#             FROM dbo.Stik_WMS_SeparacaoPlanejada_Execucao E WITH (NOLOCK)
#             INNER JOIN dbo.Stik_WMS_SeparacaoPlanejada_Item I WITH (NOLOCK)
#                 ON I.IdPlanoItem = E.IdPlanoItem
#             WHERE I.IdPlano = ?
#               AND ISNULL(E.Confirmado, 0) = 0
#               AND ISNULL(E.Cortado, 0) = 0
#         """,
#             (plano["IdPlano"],),
#         )
#         pendentes = _fetch_all_dict(cursor)
#         if pendentes:
#             return jsonify({"error": "Existem execuções pendentes.", "pendentes": _json_safe(pendentes)}), 400

#         cursor.execute(
#             """
#             SELECT I.CdVpo, I.CdObj, I.Detalhe, NmLot = MAX(ISNULL(I.NmLot, '')),
#                    QtRomaneio = MAX(I.QtRomaneio),
#                    QtSeparada = SUM(ISNULL(E.MtsConfirmados, 0))
#             FROM dbo.Stik_WMS_SeparacaoPlanejada_Item I WITH (NOLOCK)
#             INNER JOIN dbo.Stik_WMS_SeparacaoPlanejada_Execucao E WITH (NOLOCK)
#                 ON E.IdPlanoItem = I.IdPlanoItem
#             WHERE I.IdPlano = ?
#             GROUP BY I.CdVpo, I.CdObj, I.Detalhe
#         """,
#             (plano["IdPlano"],),
#         )
#         itens_consolidados = _fetch_all_dict(cursor)

#         cd_usr_str = str(cd_usr) if cd_usr is not None else ""
#         for item in itens_consolidados:
#             cursor.execute(
#                 """
#                 INSERT INTO dbo.Stik_WMS_Romaneio_Conferencia
#                     (NrRomaneio, CdVpo, CdObj, Detalhe, SituacaoConferencia, CdUsrConf, DtConf)
#                 SELECT ?, ?, ?, ?, 'Separado', ?, GETDATE()
#                 WHERE NOT EXISTS (
#                     SELECT 1 FROM dbo.Stik_WMS_Romaneio_Conferencia WITH (NOLOCK)
#                     WHERE NrRomaneio = ? AND CdVpo = ?
#                 )
#                 """,
#                 (
#                     nr_romaneio,
#                     item["CdVpo"],
#                     item["CdObj"],
#                     item.get("NmLot") or "",
#                     cd_usr_str,
#                     nr_romaneio,
#                     item["CdVpo"],
#                 ),
#             )

#         cursor.execute(
#             """
#             UPDATE dbo.Stik_WMS_SeparacaoPlanejada
#             SET Status = 'enviado_conferencia', Versao = Versao + 1,
#                 DtAtualizacao = GETDATE()
#             WHERE IdPlano = ?
#         """,
#             (plano["IdPlano"],),
#         )
#         _log_event(cursor, "ENVIAR_CONFERENCIA", {**data, "itens_consolidados": _json_safe(itens_consolidados)}, cd_usr, nm_usr, coletor_id, id_plano=plano["IdPlano"])
#         connection.commit()
#         return jsonify({"success": True, "message": "Romaneio enviado para conferência.", "nr_romaneio": nr_romaneio, "status": "enviado_conferencia", "itens": _json_safe(itens_consolidados)}), 200
#     except Exception as e:
#         if connection:
#             try:
#                 connection.rollback()
#             except Exception:
#                 pass
#         return jsonify({"error": str(e)}), 500
#     finally:
#         if connection:
#             connection.close()


# @wms_separacao_planejada_bp.route("/consulta/wms/separacao-planejada/lista-conferencia", methods=["GET"])
# def separacao_planejada_lista_conferencia():
#     connection = None
#     try:
#         connection = create_connection_tinturaria()
#         if connection is None:
#             return jsonify({"error": "Falha ao conectar ao banco."}), 500

#         cursor = connection.cursor()
#         cursor.execute(
#             """
#             SELECT
#                 P.NrRomaneio,
#                 ID               = I.IdPlanoItem,
#                 I.CdVpo,
#                 I.CdVpd,
#                 CdObj            = I.CdObj,
#                 CdLot            = I.Detalhe,
#                 Cliente          = ISNULL(
#                     (SELECT TOP 1 C.NmCli
#                      FROM dbo.TbVpd V WITH (NOLOCK)
#                      INNER JOIN dbo.TbCli C WITH (NOLOCK) ON C.CdCli = V.CdCli
#                      WHERE V.CdVpd = I.CdVpd),
#                     ''
#                 ),
#                 Objeto           = I.Objeto,
#                 Detalhe          = I.NmLot,
#                 DataExpedicao    = NULL,
#                 DataConclusaoSep = P.DtAtualizacao,
#                 Separador        = ISNULL((
#                     SELECT TOP 1 NmUsr
#                     FROM dbo.Stik_WMS_SeparacaoPlanejada_Execucao WITH (NOLOCK)
#                     WHERE IdPlanoItem = I.IdPlanoItem
#                       AND NmUsr IS NOT NULL AND NmUsr <> ''
#                 ), ''),
#                 TotalItens       = (
#                     SELECT COUNT(*)
#                     FROM dbo.Stik_WMS_SeparacaoPlanejada_Item WITH (NOLOCK)
#                     WHERE IdPlano = P.IdPlano
#                 ),
#                 QtRomaneio       = I.QtRomaneio,
#                 QtSeparada       = ISNULL((
#                     SELECT SUM(MtsConfirmados)
#                     FROM dbo.Stik_WMS_SeparacaoPlanejada_Execucao WITH (NOLOCK)
#                     WHERE IdPlanoItem = I.IdPlanoItem
#                       AND ISNULL(Confirmado, 0) = 1
#                 ), 0),
#                 Fonte            = 'wms'
#             FROM dbo.Stik_WMS_SeparacaoPlanejada P WITH (NOLOCK)
#             INNER JOIN dbo.Stik_WMS_SeparacaoPlanejada_Item I WITH (NOLOCK)
#                 ON I.IdPlano = P.IdPlano
#             WHERE P.Status = 'enviado_conferencia'
#             ORDER BY P.NrRomaneio DESC, I.IdPlanoItem
#             """
#         )
#         items = _fetch_all_dict(cursor)
#         return jsonify(items), 200
#     except Exception as e:
#         return jsonify({"error": str(e)}), 500
#     finally:
#         if connection:
#             connection.close()


# @wms_separacao_planejada_bp.route("/consulta/wms/separacao-planejada/preparar-conferencia", methods=["POST"])
# def separacao_planejada_preparar_conferencia():
#     """Garante que os itens WMS existam em Stik_WMS_Romaneio_Conferencia
#     para que o endpoint ERP /separado_conferido os encontre."""
#     connection = None
#     try:
#         data = request.get_json() or {}
#         nr_romaneio = _to_int(data.get("nr_romaneio"))
#         cd_usr = _to_int(data.get("cd_usr") or data.get("usuario_id"), None)

#         if nr_romaneio <= 0:
#             return jsonify({"error": "Campo obrigatório: nr_romaneio"}), 400

#         connection = create_connection_tinturaria()
#         cursor = connection.cursor()
#         cursor.execute("SET NOCOUNT ON; SET XACT_ABORT ON;")

#         cursor.execute(
#             """
#             SELECT IdPlano FROM dbo.Stik_WMS_SeparacaoPlanejada WITH (NOLOCK)
#             WHERE NrRomaneio = ? AND Status = 'enviado_conferencia'
#             """,
#             (nr_romaneio,),
#         )
#         row = cursor.fetchone()
#         if not row:
#             return jsonify({"error": "Romaneio não encontrado ou não está em conferência."}), 404

#         id_plano = row[0]
#         cursor.execute(
#             """
#             SELECT I.CdVpo, I.CdObj, ISNULL(I.NmLot, '') AS NmLot
#             FROM dbo.Stik_WMS_SeparacaoPlanejada_Item I WITH (NOLOCK)
#             WHERE I.IdPlano = ?
#             """,
#             (id_plano,),
#         )
#         itens = _fetch_all_dict(cursor)

#         cd_usr_str = str(cd_usr) if cd_usr is not None else ""
#         inseridos = 0
#         for item in itens:
#             cursor.execute(
#                 """
#                 INSERT INTO dbo.Stik_WMS_Romaneio_Conferencia
#                     (NrRomaneio, CdVpo, CdObj, Detalhe, SituacaoConferencia, CdUsrConf, DtConf)
#                 SELECT ?, ?, ?, ?, 'Separado', ?, GETDATE()
#                 WHERE NOT EXISTS (
#                     SELECT 1 FROM dbo.Stik_WMS_Romaneio_Conferencia WITH (NOLOCK)
#                     WHERE NrRomaneio = ? AND CdVpo = ?
#                 )
#                 """,
#                 (
#                     nr_romaneio, item["CdVpo"], item["CdObj"], item["NmLot"],
#                     cd_usr_str,
#                     nr_romaneio, item["CdVpo"],
#                 ),
#             )
#             inseridos += cursor.rowcount

#         connection.commit()
#         return jsonify({"success": True, "nr_romaneio": nr_romaneio, "itens_inseridos": inseridos}), 200
#     except Exception as e:
#         if connection:
#             try:
#                 connection.rollback()
#             except Exception:
#                 pass
#         return jsonify({"error": str(e)}), 500
#     finally:
#         if connection:
#             connection.close()


# @wms_separacao_planejada_bp.route("/consulta/wms/separacao-planejada/conferir", methods=["POST"])
# def separacao_planejada_conferir():
#     connection = None
#     try:
#         data = request.get_json() or {}
#         nr_romaneio = _to_int(data.get("nr_romaneio"))
#         cd_usr = _to_int(data.get("cd_usr") or data.get("usuario_id"), None)
#         nm_usr = (data.get("nm_usr") or data.get("usuario_nome") or "").strip()
#         coletor_id = (data.get("coletor_id") or "").strip()

#         if nr_romaneio <= 0:
#             return jsonify({"error": "Campo obrigatório: nr_romaneio"}), 400

#         connection = create_connection_tinturaria()
#         cursor = connection.cursor()
#         cursor.execute("SET NOCOUNT ON; SET XACT_ABORT ON;")

#         cursor.execute(
#             """
#             SELECT IdPlano FROM dbo.Stik_WMS_SeparacaoPlanejada WITH (UPDLOCK, HOLDLOCK)
#             WHERE NrRomaneio = ? AND Status = 'enviado_conferencia'
#             """,
#             (nr_romaneio,),
#         )
#         row = cursor.fetchone()
#         if not row:
#             return jsonify({"error": "Romaneio não encontrado ou não está em conferência."}), 404

#         id_plano = row[0]
#         cursor.execute(
#             """
#             UPDATE dbo.Stik_WMS_SeparacaoPlanejada
#             SET Status = 'conferido', Versao = Versao + 1, DtAtualizacao = GETDATE()
#             WHERE IdPlano = ?
#             """,
#             (id_plano,),
#         )
#         tp_sit_fat = _to_int(data.get("tp_sit_fat"), 4) or 4
#         cd_usr_str = str(cd_usr) if cd_usr is not None else None
#         cursor.execute(
#             """
#             UPDATE dbo.Stik_Pedido_QtdFat
#             SET TpSitFat = ?,
#                 CdUsrConf = ISNULL(?, CdUsrConf),
#                 DtConf    = GETDATE()
#             WHERE NrRomaneio = ?
#             """,
#             (tp_sit_fat, cd_usr_str, nr_romaneio),
#         )
#         _log_event(cursor, "CONFERIR", data, cd_usr, nm_usr, coletor_id, id_plano=id_plano)
#         connection.commit()
#         return jsonify({"success": True, "nr_romaneio": nr_romaneio, "status": "conferido"}), 200
#     except Exception as e:
#         if connection:
#             try:
#                 connection.rollback()
#             except Exception:
#                 pass
#         return jsonify({"error": str(e)}), 500
#     finally:
#         if connection:
#             connection.close()

import datetime
import decimal
import json
import re

from flask import Blueprint, jsonify, request

from database.server import create_connection_tinturaria

wms_separacao_planejada_bp = Blueprint("wms_separacao_planejada", __name__)


def _to_int(value, default=0):
    try:
        if value in (None, ""):
            return default
        return int(value)
    except Exception:
        return default


def _to_float(value, default=0.0):
    try:
        if value in (None, ""):
            return default
        return float(str(value).replace(",", "."))
    except Exception:
        return default


def _norm(value):
    return (value or "").strip().upper()


def _coerce(value):
    if isinstance(value, decimal.Decimal):
        return float(value)
    if isinstance(value, (datetime.datetime, datetime.date)):
        return value.isoformat()
    return value


def _row_dict(cursor, row):
    if not row:
        return None
    columns = [col[0] for col in cursor.description]
    return {columns[i]: _coerce(row[i]) for i in range(len(columns))}


def _fetch_all_dict(cursor):
    columns = [col[0] for col in cursor.description]
    return [{columns[i]: _coerce(row[i]) for i in range(len(columns))} for row in cursor.fetchall()]


def _json_safe(obj):
    if isinstance(obj, (datetime.datetime, datetime.date)):
        return obj.isoformat()
    if isinstance(obj, decimal.Decimal):
        return float(obj)
    if isinstance(obj, list):
        return [_json_safe(x) for x in obj]
    if isinstance(obj, dict):
        return {k: _json_safe(v) for k, v in obj.items()}
    return obj


def _extrair_artigo_mae(descricao):
    texto = (descricao or "").strip()
    if not texto:
        return ""
    match = re.search(r"(.+?\bmm)", texto, flags=re.IGNORECASE)
    if match:
        return texto[: match.end()].strip()
    return texto


def _buscar_padrao_caixa(cursor, objeto):
    artigo_mae = _extrair_artigo_mae(objeto)
    if not artigo_mae:
        return {}, ""

    cursor.execute(
        """
        SELECT TOP 1
            artigo,
            caixa_p = ISNULL(caixa_p, 0),
            caixa_g = ISNULL(caixa_g, 0),
            enfestado = ISNULL(enfestado, 0),
            enfraldado = ISNULL(enfraldado, 0)
        FROM dbo.Stik_PadraoCaixa WITH (NOLOCK)
        WHERE UPPER(LTRIM(RTRIM(artigo))) = UPPER(LTRIM(RTRIM(?)))
    """,
        (artigo_mae,),
    )
    padrao = _row_dict(cursor, cursor.fetchone())
    return padrao or {}, artigo_mae


def _buscar_candidatos_embalagem(cursor, cd_obj, detalhe):
    cursor.execute(
        """
        WITH AlocacaoBase AS (
            SELECT
                Endereco = UPPER(LTRIM(RTRIM(Endereco))),
                CodSKU,
                Detalhe = ISNULL(Detalhe, 0),
                QtBase = SUM(ISNULL(QtAlocada, 0))
            FROM dbo.Stik_WMS_Alocacao WITH (NOLOCK)
            WHERE CodSKU = ?
              AND ISNULL(Detalhe, 0) = ISNULL(?, 0)
            GROUP BY UPPER(LTRIM(RTRIM(Endereco))), CodSKU, ISNULL(Detalhe, 0)
        ),
        Movimentos AS (
            SELECT
                Endereco = UPPER(LTRIM(RTRIM(Endereco))),
                CodSKU,
                Detalhe = ISNULL(Detalhe, 0),
                QtMov = SUM(
                    CASE
                        WHEN ISNULL(TpMov, 0) IN (1, 3) THEN ISNULL(QtMovida, 0)
                        ELSE -ISNULL(QtMovida, 0)
                    END
                )
            FROM dbo.Stik_WMS_Movimento WITH (NOLOCK)
            WHERE CodSKU = ?
              AND ISNULL(Detalhe, 0) = ISNULL(?, 0)
            GROUP BY UPPER(LTRIM(RTRIM(Endereco))), CodSKU, ISNULL(Detalhe, 0)
        ),
        Chaves AS (
            SELECT Endereco, CodSKU, Detalhe FROM AlocacaoBase
            UNION
            SELECT Endereco, CodSKU, Detalhe FROM Movimentos
        ),
        Saldos AS (
            SELECT
                C.Endereco,
                C.CodSKU,
                C.Detalhe,
                QtSaldoFinal =
                    ISNULL(A.QtBase, 0) + ISNULL(M.QtMov, 0)
            FROM Chaves C
            LEFT JOIN AlocacaoBase A
                ON A.Endereco = C.Endereco
               AND A.CodSKU = C.CodSKU
               AND A.Detalhe = C.Detalhe
            LEFT JOIN Movimentos M
                ON M.Endereco = C.Endereco
               AND M.CodSKU = C.CodSKU
               AND M.Detalhe = C.Detalhe
        ),
        CaixaResumo AS (
            -- Fonte oficial das caixas fechadas: Stik_WMS_Caixa (caixa
            -- física individual), não mais o contador agregado antigo.
            SELECT
                Endereco = UPPER(LTRIM(RTRIM(Endereco))),
                CdObj,
                Detalhe = ISNULL(Detalhe, 0),
                QtCaixaP = SUM(CASE WHEN TipoCaixa = 'P' THEN 1 ELSE 0 END),
                QtCaixaG = SUM(CASE WHEN TipoCaixa = 'G' THEN 1 ELSE 0 END),
                QtEnfestado = SUM(CASE WHEN TipoCaixa = 'ENF' THEN 1 ELSE 0 END),
                QtEnfraldado = SUM(CASE WHEN TipoCaixa = 'ENFR' THEN 1 ELSE 0 END)
            FROM dbo.Stik_WMS_Caixa WITH (NOLOCK)
            WHERE Status = 'DISPONIVEL'
              AND CdObj = ?
              AND ISNULL(Detalhe, 0) = ISNULL(?, 0)
            GROUP BY UPPER(LTRIM(RTRIM(Endereco))), CdObj, ISNULL(Detalhe, 0)
        )
        SELECT
            S.Endereco,
            S.CodSKU,
            S.Detalhe,
            QtSaldoFinal = S.QtSaldoFinal,
            QtCaixaP = ISNULL(E.QtCaixaP, 0),
            QtCaixaG = ISNULL(E.QtCaixaG, 0),
            QtEnfestado = ISNULL(E.QtEnfestado, 0),
            QtEnfraldado = ISNULL(E.QtEnfraldado, 0)
        FROM Saldos S
        LEFT JOIN CaixaResumo E
            ON E.Endereco = S.Endereco
           AND E.CdObj = S.CodSKU
           AND E.Detalhe = S.Detalhe
        WHERE S.QtSaldoFinal > 0
        ORDER BY
            CASE
                WHEN ISNULL(E.QtCaixaP, 0) > 0 OR
                     ISNULL(E.QtCaixaG, 0) > 0 OR
                     ISNULL(E.QtEnfestado, 0) > 0 OR
                     ISNULL(E.QtEnfraldado, 0) > 0
                THEN 0 ELSE 1
            END,
            S.QtSaldoFinal DESC,
            S.Endereco
    """,
        (cd_obj, detalhe, cd_obj, detalhe, cd_obj, detalhe),
    )
    return _fetch_all_dict(cursor)


def _parse_endereco(endereco):
    texto = _norm(endereco)
    partes = [p for p in texto.split("-") if p]
    rua = ""
    nivel = ""
    rack = 0
    posicao = 0

    for idx, parte in enumerate(partes):
        if re.match(r"^L\d+$", parte):
            rua = parte
        elif re.match(r"^R\d+$", parte):
            rack = _to_int(parte[1:])
            if idx + 1 < len(partes):
                proximo = partes[idx + 1]
                if not re.match(r"^P\d+$", proximo):
                    nivel = proximo
        elif re.match(r"^P\d+$", parte):
            posicao = _to_int(parte[1:])

    return {
        "rua": rua,
        "nivel": nivel,
        "rack": rack,
        "posicao": posicao,
        "rua_nivel": f"{rua}|{nivel}" if rua and nivel else "",
    }


def _tem_embalagem(candidato):
    return (
        _to_int(candidato.get("QtCaixaP")) > 0 or
        _to_int(candidato.get("QtCaixaG")) > 0 or
        _to_int(candidato.get("QtEnfestado")) > 0 or
        _to_int(candidato.get("QtEnfraldado")) > 0
    )


def _calcular_perfil_proximidade(preparados):
    ruas = {}
    niveis = {}
    racks = {}

    for idx, preparado in enumerate(preparados):
        ruas_item = set()
        niveis_item = set()
        racks_item = set()
        for candidato in preparado.get("candidatos", []):
            endereco_info = _parse_endereco(candidato.get("Endereco"))
            candidato["_EnderecoInfo"] = endereco_info
            if endereco_info["rua"]:
                ruas_item.add(endereco_info["rua"])
            if endereco_info["rua_nivel"]:
                niveis_item.add(endereco_info["rua_nivel"])
            if endereco_info["rua"] and endereco_info["rack"] > 0:
                racks_item.add((endereco_info["rua"], endereco_info["rack"]))

        for key in ruas_item:
            ruas.setdefault(key, set()).add(idx)
        for key in niveis_item:
            niveis.setdefault(key, set()).add(idx)
        for key in racks_item:
            racks.setdefault(key, set()).add(idx)

    return {
        "ruas": {key: len(value) for key, value in ruas.items()},
        "niveis": {key: len(value) for key, value in niveis.items()},
        "racks": {key: len(value) for key, value in racks.items()},
    }


def _aplicar_proximidade_candidatos(preparados):
    perfil = _calcular_perfil_proximidade(preparados)

    for preparado in preparados:
        for candidato in preparado.get("candidatos", []):
            endereco_info = candidato.get("_EnderecoInfo") or _parse_endereco(candidato.get("Endereco"))
            rua = endereco_info["rua"]
            rua_nivel = endereco_info["rua_nivel"]
            rack_key = (rua, endereco_info["rack"]) if rua and endereco_info["rack"] > 0 else None
            score = (
                perfil["ruas"].get(rua, 0) * 300 +
                perfil["niveis"].get(rua_nivel, 0) * 180 +
                (perfil["racks"].get(rack_key, 0) * 80 if rack_key else 0)
            )
            candidato["_ProximidadeScore"] = score
            candidato["_TemEmbalagem"] = 1 if _tem_embalagem(candidato) else 0

        preparado["candidatos"].sort(
            key=lambda c: (
                -_to_int(c.get("_ProximidadeScore")),
                -_to_int(c.get("_TemEmbalagem")),
                -_to_float(c.get("QtSaldoFinal")),
                _to_int((c.get("_EnderecoInfo") or {}).get("rack")),
                _to_int((c.get("_EnderecoInfo") or {}).get("posicao")),
                _norm(c.get("Endereco")),
            )
        )


def _caixas_disponiveis(candidato, campo_qt, mts_caixa):
    if mts_caixa <= 0:
        return 0
    # Confia na contagem real de caixas (Stik_WMS_Caixa). Não estima mais
    # "caixas possíveis" a partir do saldo em metros quando a contagem é
    # zero — isso fazia o planejamento escolher endereços que não têm
    # nenhuma caixa fechada daquele tipo, só porque tinham saldo suficiente.
    saldo = _to_float(candidato.get("QtSaldoFinal"))
    por_saldo = int(saldo // mts_caixa)
    por_embalagem = _to_int(candidato.get(campo_qt))
    return min(por_embalagem, por_saldo)


def _copiar_candidatos(candidatos):
    return [dict(candidato) for candidato in candidatos]


def _consumir_saldo_candidato(candidato, metros):
    saldo = _to_float(candidato.get("QtSaldoFinal"))
    candidato["QtSaldoFinal"] = max(0, saldo - _to_float(metros))


def _montar_linhas_caixa_individuais(endereco, tipo, qt_caixas, mts_caixa):
    linhas = []
    for _ in range(_to_int(qt_caixas)):
        linhas.append(
            {
                "endereco": endereco,
                "tipo_caixa": tipo,
                "qt_caixas": 1,
                "mts_por_caixa": mts_caixa,
                "mts_planejados": mts_caixa,
            }
        )
    return linhas


def _montar_fracionado_restante(restante_metros, candidatos):
    if restante_metros <= 0:
        return [], 0
    candidatos_com_saldo = [
        candidato for candidato in candidatos
        if _to_float(candidato.get("QtSaldoFinal")) > 0
    ]
    for candidato in candidatos_com_saldo:
        if _to_float(candidato.get("QtSaldoFinal")) >= restante_metros:
            return [
                {
                    "endereco": candidato.get("Endereco"),
                    "tipo_caixa": "FRACIONADO",
                    "qt_caixas": 0,
                    "mts_por_caixa": 0,
                    "mts_planejados": restante_metros,
                }
            ], 0
    return _montar_execucoes_por_saldo(restante_metros, candidatos_com_saldo)


def _montar_execucoes_por_caixa(qt_romaneio, candidatos, padrao):
    tipos = [
        ("P", _to_float(padrao.get("caixa_p")), "QtCaixaP"),
        ("G", _to_float(padrao.get("caixa_g")), "QtCaixaG"),
        ("ENFESTADO", _to_float(padrao.get("enfestado")), "QtEnfestado"),
        ("ENFRALDADO", _to_float(padrao.get("enfraldado")), "QtEnfraldado"),
    ]

    # Primeiro tenta atender tudo com um único palete e caixa fechada correta.
    for tipo, mts_caixa, campo_qt in tipos:
        if mts_caixa <= 0 or abs(qt_romaneio % mts_caixa) > 0.0001:
            continue
        caixas_necessarias = int(qt_romaneio // mts_caixa)
        if caixas_necessarias <= 0:
            continue
        for candidato in candidatos:
            if _caixas_disponiveis(candidato, campo_qt, mts_caixa) >= caixas_necessarias:
                return _montar_linhas_caixa_individuais(
                    candidato.get("Endereco"),
                    tipo,
                    caixas_necessarias,
                    mts_caixa,
                )

    # Depois permite dividir a mesma caixa fechada entre paletes.
    for tipo, mts_caixa, campo_qt in tipos:
        if mts_caixa <= 0 or abs(qt_romaneio % mts_caixa) > 0.0001:
            continue
        restante_caixas = int(qt_romaneio // mts_caixa)
        plano = []
        for candidato in candidatos:
            usar = min(
                _caixas_disponiveis(candidato, campo_qt, mts_caixa),
                restante_caixas
            )
            if usar <= 0:
                continue
            plano.extend(
                _montar_linhas_caixa_individuais(
                    candidato.get("Endereco"),
                    tipo,
                    usar,
                    mts_caixa,
                )
            )
            restante_caixas -= usar
            if restante_caixas == 0:
                return plano

    # Se não fechar tudo em caixa, usa o máximo possível de caixa fechada
    # e deixa somente a sobra como fracionado.
    melhores = []
    for tipo, mts_caixa, campo_qt in tipos:
        if mts_caixa <= 0:
            continue
        candidatos_teste = _copiar_candidatos(candidatos)
        restante_metros = _to_float(qt_romaneio)
        plano = []

        for candidato in candidatos_teste:
            if restante_metros < mts_caixa:
                break
            caixas_disponiveis = _caixas_disponiveis(candidato, campo_qt, mts_caixa)
            caixas_necessarias = int(restante_metros // mts_caixa)
            usar = min(caixas_disponiveis, caixas_necessarias)
            if usar <= 0:
                continue
            mts_total = usar * mts_caixa
            plano.extend(
                _montar_linhas_caixa_individuais(
                    candidato.get("Endereco"),
                    tipo,
                    usar,
                    mts_caixa,
                )
            )
            restante_metros -= mts_total
            _consumir_saldo_candidato(candidato, mts_total)

        if not plano:
            continue

        fracionados, restante_sem_saldo = _montar_fracionado_restante(
            restante_metros,
            candidatos_teste
        )
        plano_completo = plano + fracionados
        metros_caixa = sum(_to_float(ex.get("mts_planejados")) for ex in plano)
        metros_fracionado = sum(_to_float(ex.get("mts_planejados")) for ex in fracionados)
        melhores.append({
            "plano": plano_completo,
            "restante_sem_saldo": restante_sem_saldo,
            "metros_caixa": metros_caixa,
            "metros_fracionado": metros_fracionado,
            "linhas": len(plano_completo),
            "mts_caixa": mts_caixa,
        })

    if melhores:
        melhores.sort(
            key=lambda opcao: (
                _to_float(opcao["restante_sem_saldo"]),
                _to_float(opcao["metros_fracionado"]),
                -_to_float(opcao["metros_caixa"]),
                _to_int(opcao["linhas"]),
                -_to_float(opcao["mts_caixa"]),
            )
        )
        melhor = melhores[0]
        plano = melhor["plano"]
        restante_sem_saldo = _to_float(melhor["restante_sem_saldo"])
        if restante_sem_saldo > 0.0001:
            plano = plano + [
                {
                    "endereco": "SEM ESTOQUE",
                    "tipo_caixa": "SEM_ESTOQUE",
                    "qt_caixas": 0,
                    "mts_por_caixa": 0,
                    "mts_planejados": restante_sem_saldo,
                }
            ]
        return plano

    return []


def _montar_execucoes_por_saldo(qt_romaneio, candidatos):
    restante = _to_float(qt_romaneio)
    plano = []
    for candidato in candidatos:
        if restante <= 0:
            break
        saldo = _to_float(candidato.get("QtSaldoFinal"))
        if saldo <= 0:
            continue
        usar = min(saldo, restante)
        if usar <= 0:
            continue
        plano.append(
            {
                "endereco": candidato.get("Endereco"),
                "tipo_caixa": "FRACIONADO",
                "qt_caixas": 0,
                "mts_por_caixa": 0,
                "mts_planejados": usar,
            }
        )
        restante -= usar
    return plano, restante


def _inserir_execucao_planejada(cursor, id_plano_item, execucao):
    cursor.execute(
        """
        INSERT INTO dbo.Stik_WMS_SeparacaoPlanejada_Execucao
            (IdPlanoItem, Endereco, TipoCaixa, QtCaixasPlanejada, MtsPorCaixa, MtsPlanejados)
        VALUES (?, ?, ?, ?, ?, ?)
    """,
        (
            id_plano_item,
            execucao["endereco"],
            execucao["tipo_caixa"],
            execucao["qt_caixas"],
            execucao["mts_por_caixa"],
            execucao["mts_planejados"],
        ),
    )


def _dividir_execucoes_caixa_agregadas(cursor, id_plano):
    cursor.execute(
        """
        SELECT
            E.IdExecucao,
            E.IdPlanoItem,
            E.Endereco,
            E.TipoCaixa,
            E.QtCaixasPlanejada,
            E.MtsPorCaixa
        FROM dbo.Stik_WMS_SeparacaoPlanejada_Execucao E WITH (UPDLOCK, HOLDLOCK)
        INNER JOIN dbo.Stik_WMS_SeparacaoPlanejada_Item I WITH (UPDLOCK, HOLDLOCK)
            ON I.IdPlanoItem = E.IdPlanoItem
        WHERE I.IdPlano = ?
          AND ISNULL(E.QtCaixasPlanejada, 0) > 1
          AND ISNULL(E.MtsPorCaixa, 0) > 0
          AND UPPER(LTRIM(RTRIM(ISNULL(E.TipoCaixa, '')))) NOT IN ('FRACIONADO', 'SEM_ESTOQUE')
          AND ISNULL(E.PaleteValidado, 0) = 0
          AND ISNULL(E.ItemValidado, 0) = 0
          AND ISNULL(E.Confirmado, 0) = 0
          AND ISNULL(E.Cortado, 0) = 0
        ORDER BY E.IdExecucao
        """,
        (id_plano,),
    )
    execucoes = _fetch_all_dict(cursor)
    if not execucoes:
        return 0

    total_novas_linhas = 0
    for execucao in execucoes:
        qt_caixas = _to_int(execucao.get("QtCaixasPlanejada"))
        if qt_caixas <= 1:
            continue

        cursor.execute(
            "DELETE FROM dbo.Stik_WMS_SeparacaoPlanejada_Execucao WHERE IdExecucao = ?",
            (execucao["IdExecucao"],),
        )
        for linha in _montar_linhas_caixa_individuais(
            execucao.get("Endereco"),
            execucao.get("TipoCaixa"),
            qt_caixas,
            _to_float(execucao.get("MtsPorCaixa")),
        ):
            _inserir_execucao_planejada(cursor, execucao["IdPlanoItem"], linha)
            total_novas_linhas += 1

    return total_novas_linhas


def _gerar_execucoes_para_item(cursor, id_plano_item, cd_obj, detalhe, objeto, qt_romaneio):
    """Consulta padrão de caixa + candidatos e insere as execuções de um
    IdPlanoItem já existente. Usada tanto ao popular um plano novo quanto
    ao recalcular um único item preservando os demais já iniciados."""
    padrao, _artigo_mae = _buscar_padrao_caixa(cursor, objeto)
    candidatos = _buscar_candidatos_embalagem(cursor, cd_obj, detalhe)

    if not candidatos:
        _inserir_execucao_planejada(
            cursor,
            id_plano_item,
            {
                "endereco": "SEM ESTOQUE",
                "tipo_caixa": "SEM_ESTOQUE",
                "qt_caixas": 0,
                "mts_por_caixa": 0,
                "mts_planejados": qt_romaneio,
            },
        )
        return

    execucoes = _montar_execucoes_por_caixa(qt_romaneio, candidatos, padrao)
    if execucoes:
        for ex in execucoes:
            _inserir_execucao_planejada(cursor, id_plano_item, ex)
        return

    execucoes_saldo, restante_sem_saldo = _montar_execucoes_por_saldo(qt_romaneio, candidatos)
    for ex in execucoes_saldo:
        _inserir_execucao_planejada(cursor, id_plano_item, ex)

    if restante_sem_saldo > 0.0001:
        _inserir_execucao_planejada(
            cursor,
            id_plano_item,
            {
                "endereco": "SEM ESTOQUE",
                "tipo_caixa": "SEM_ESTOQUE",
                "qt_caixas": 0,
                "mts_por_caixa": 0,
                "mts_planejados": restante_sem_saldo,
            },
        )


def _popular_plano(cursor, id_plano, nr_romaneio):
    cursor.execute(
        """
        SELECT Fat.NrRomaneio, Fat.CdVpo, Vpd.CdVpd, Vpo.CdObj,
               Detalhe = Lot.CdLot, NmLot = Lot.NmLot, Objeto = Obj.NmObj,
               Setor = ISNULL(Obj.CdObjLin, 0),
               QtRomaneio = ISNULL(Fat.QtFatAtend, Fat.QtFat)
        FROM dbo.Stik_Pedido_QtdFat Fat WITH (NOLOCK)
        INNER JOIN dbo.TbVpo Vpo WITH (NOLOCK) ON Vpo.CdVpo = Fat.CdVpo
        INNER JOIN dbo.TbVpd Vpd WITH (NOLOCK) ON Vpd.CdVpd = Vpo.CdVpd
        INNER JOIN dbo.TbObj Obj WITH (NOLOCK) ON Obj.CdObj = Vpo.CdObj
        OUTER APPLY (
            SELECT TOP 1 L.CdLot, L.NmLot
            FROM dbo.TbLot L WITH (NOLOCK)
            WHERE L.CdLot = Fat.CdLot
        ) Lot
        WHERE Fat.NrRomaneio = ?
          AND ISNULL(Fat.TpSitFat, 0) <> 4
    """,
        (nr_romaneio,),
    )
    itens = _fetch_all_dict(cursor)
    if not itens:
        raise ValueError("Itens do romaneio não encontrados.")

    preparados = []
    for item in itens:
        qt_romaneio = _to_float(item.get("QtRomaneio"))
        if qt_romaneio <= 0:
            continue
        padrao, artigo_mae = _buscar_padrao_caixa(cursor, item.get("Objeto"))
        candidatos = _buscar_candidatos_embalagem(cursor, item.get("CdObj"), item.get("Detalhe"))
        preparados.append({
            "item": item,
            "qt_romaneio": qt_romaneio,
            "padrao": padrao,
            "artigo_mae": artigo_mae,
            "candidatos": candidatos,
        })

    _aplicar_proximidade_candidatos(preparados)

    for preparado in preparados:
        item = preparado["item"]
        qt_romaneio = preparado["qt_romaneio"]
        padrao = preparado["padrao"]
        candidatos = preparado["candidatos"]

        cursor.execute(
            """
            INSERT INTO dbo.Stik_WMS_SeparacaoPlanejada_Item
                (IdPlano, CdVpo, CdVpd, CdObj, Detalhe, NmLot, Objeto, QtRomaneio)
            OUTPUT INSERTED.IdPlanoItem
            VALUES (?, ?, ?, ?, ?, ?, ?, ?)
        """,
            (
                id_plano,
                item.get("CdVpo"),
                item.get("CdVpd"),
                item.get("CdObj"),
                item.get("Detalhe"),
                item.get("NmLot"),
                item.get("Objeto"),
                qt_romaneio,
            ),
        )
        id_plano_item = cursor.fetchone()[0]

        if not candidatos:
            _inserir_execucao_planejada(
                cursor,
                id_plano_item,
                {
                    "endereco": "SEM ESTOQUE",
                    "tipo_caixa": "SEM_ESTOQUE",
                    "qt_caixas": 0,
                    "mts_por_caixa": 0,
                    "mts_planejados": qt_romaneio,
                },
            )
            continue

        execucoes = _montar_execucoes_por_caixa(qt_romaneio, candidatos, padrao)
        if execucoes:
            for ex in execucoes:
                _inserir_execucao_planejada(cursor, id_plano_item, ex)
            continue

        execucoes_saldo, restante_sem_saldo = _montar_execucoes_por_saldo(qt_romaneio, candidatos)
        for ex in execucoes_saldo:
            _inserir_execucao_planejada(cursor, id_plano_item, ex)

        if restante_sem_saldo > 0.0001:
            _inserir_execucao_planejada(
                cursor,
                id_plano_item,
                {
                    "endereco": "SEM ESTOQUE",
                    "tipo_caixa": "SEM_ESTOQUE",
                    "qt_caixas": 0,
                    "mts_por_caixa": 0,
                    "mts_planejados": restante_sem_saldo,
                },
            )


def _log_event(cursor, evento, payload, cd_usr=None, nm_usr=None, coletor_id=None,
               id_plano=None, id_plano_item=None, id_execucao=None):
    cursor.execute(
        """
        INSERT INTO dbo.Stik_WMS_SeparacaoPlanejada_Evento
            (IdPlano, IdPlanoItem, IdExecucao, Evento, Payload, CdUsr, NmUsr, ColetorId)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?)
    """,
        (
            id_plano,
            id_plano_item,
            id_execucao,
            evento,
            json.dumps(_json_safe(payload), ensure_ascii=False),
            cd_usr,
            nm_usr,
            coletor_id,
        ),
    )


def _buscar_plano(cursor, nr_romaneio):
    cursor.execute(
        """
        SELECT IdPlano, NrRomaneio, Status, Versao, CdUsrCriacao, ColetorId,
               DtCriacao, DtAtualizacao
        FROM dbo.Stik_WMS_SeparacaoPlanejada WITH (NOLOCK)
        WHERE NrRomaneio = ?
    """,
        (nr_romaneio,),
    )
    plano = _row_dict(cursor, cursor.fetchone())
    if not plano:
        return None

    cursor.execute(
        """
        SELECT I.IdPlanoItem, I.IdPlano, I.CdVpo, I.CdVpd, I.CdObj, I.Detalhe, I.NmLot,
               I.Objeto, Setor = ISNULL(Obj.CdObjLin, 0), I.QtRomaneio,
               I.Status, I.Versao, I.DtCriacao, I.DtAtualizacao
        FROM dbo.Stik_WMS_SeparacaoPlanejada_Item I WITH (NOLOCK)
        INNER JOIN dbo.TbObj Obj WITH (NOLOCK) ON Obj.CdObj = I.CdObj
        WHERE I.IdPlano = ?
        ORDER BY I.IdPlanoItem
    """,
        (plano["IdPlano"],),
    )
    itens = _fetch_all_dict(cursor)

    for item in itens:
        cursor.execute(
            """
            SELECT IdExecucao, IdPlanoItem, Endereco, EnderecoLido, TipoCaixa,
                   QtCaixasPlanejada, MtsPorCaixa, MtsPlanejados,
                   QtCaixasConfirmada, MtsConfirmados, QtCaixasCortada,
                   MtsCortados, PaleteValidado, ItemValidado, Confirmado,
                   Cortado, MotivoCorte, CdUsr, NmUsr, ColetorId,
                   BloqueadoAte, Versao, DtCriacao, DtAtualizacao
            FROM dbo.Stik_WMS_SeparacaoPlanejada_Execucao WITH (NOLOCK)
            WHERE IdPlanoItem = ?
            ORDER BY IdExecucao
        """,
            (item["IdPlanoItem"],),
        )
        item["execucoes"] = _fetch_all_dict(cursor)

    plano["itens"] = itens
    return _json_safe(plano)


def _buscar_execucao(cursor, id_execucao):
    cursor.execute(
        """
        SELECT E.*, I.IdPlano, I.CdVpo, I.CdVpd, I.CdObj, I.Detalhe,
               I.NmLot, I.Objeto, Setor = ISNULL(Obj.CdObjLin, 0), I.QtRomaneio
        FROM dbo.Stik_WMS_SeparacaoPlanejada_Execucao E WITH (NOLOCK)
        INNER JOIN dbo.Stik_WMS_SeparacaoPlanejada_Item I WITH (NOLOCK)
            ON I.IdPlanoItem = E.IdPlanoItem
        INNER JOIN dbo.TbObj Obj WITH (NOLOCK) ON Obj.CdObj = I.CdObj
        WHERE E.IdExecucao = ?
    """,
        (id_execucao,),
    )
    return _json_safe(_row_dict(cursor, cursor.fetchone()))


def _erro_conflito(execucao):
    return jsonify({"error": "Registro atualizado por outro coletor.", "estado_atual": execucao}), 409


def _validar_versao(execucao, versao):
    return _to_int(execucao.get("Versao")) == _to_int(versao)


# Mapeia as siglas compactas do QR da etiqueta (campo "C") para os nomes
# usados em TipoCaixa da execução (ex.: etiqueta grava "ENF", plano grava
# "ENFESTADO").
_TIPO_CAIXA_QR_ABREVIADO = {
    "ENF": "ENFESTADO",
    "ENFR": "ENFRALDADO",
    "P": "P",
    "G": "G",
    "D": "D",
}


def _validar_qr_execucao(execucao, qr):
    cd_obj_lido = _to_int(qr.get("CdObj") or qr.get("cdObj") or qr.get("cd_obj"))
    if cd_obj_lido != _to_int(execucao.get("CdObj")):
        return False, "CdObj lido não corresponde ao planejado."

    # "Detalhe" é a chave do QR compacto atual da etiqueta; DetalheId/DetalheID
    # são mantidas por compatibilidade com formatos antigos.
    detalhe_lido = (
        qr.get("Detalhe")
        or qr.get("DetalheId")
        or qr.get("DetalheID")
        or qr.get("detalheId")
    )
    if detalhe_lido not in (None, "") and _to_int(detalhe_lido) != _to_int(execucao.get("Detalhe")):
        return False, "Detalhe lido não corresponde ao planejado."

    tipo_esperado = _norm(execucao.get("TipoCaixa"))

    # Execuções "FRACIONADO"/"SEM_ESTOQUE" representam sobra de saldo em
    # metros, não uma caixa fechada de um tipo específico (P/G/ENF/ENFR) —
    # foram montadas por _montar_fracionado_restante/_montar_execucoes_por_saldo
    # sem QtCaixasPlanejada nem MtsPorCaixa. Qualquer caixa física do mesmo
    # CdObj/Detalhe serve para abater esse saldo, então tipo e metragem da
    # caixa lida não são comparados ao planejado nesses casos.
    if tipo_esperado in ("FRACIONADO", "SEM_ESTOQUE"):
        return True, None

    # "C" é a chave do QR compacto atual; TipoCaixa/tipoCaixa por compatibilidade.
    tipo_lido_bruto = _norm(qr.get("C") or qr.get("TipoCaixa") or qr.get("tipoCaixa"))
    tipo_lido = _TIPO_CAIXA_QR_ABREVIADO.get(tipo_lido_bruto, tipo_lido_bruto)
    if tipo_lido and tipo_esperado and tipo_lido != tipo_esperado:
        return False, "Tipo de caixa lido não corresponde ao planejado."

    mts_lido = qr.get("MetrosCaixa") or qr.get("metrosCaixa")
    if mts_lido not in (None, ""):
        if abs(_to_float(mts_lido) - _to_float(execucao.get("MtsPorCaixa"))) > 0.0001:
            return False, "Metragem da caixa lida não corresponde ao planejado."

    return True, None


@wms_separacao_planejada_bp.route("/consulta/wms/separacao-planejada", methods=["GET"])
def separacao_planejada_buscar():
    connection = None
    try:
        nr_romaneio = _to_int(request.args.get("nr_romaneio"))
        if nr_romaneio <= 0:
            return jsonify({"error": "Parâmetro obrigatório: nr_romaneio"}), 400

        connection = create_connection_tinturaria()
        if connection is None:
            return jsonify({"status": "SQL_ERROR", "details": "Falha ao conectar ao banco."}), 500

        cursor = connection.cursor()
        cursor.execute("SET NOCOUNT ON; SET XACT_ABORT ON;")
        plano = _buscar_plano(cursor, nr_romaneio)
        if not plano:
            return jsonify({"error": "Plano não encontrado."}), 404
        linhas_divididas = _dividir_execucoes_caixa_agregadas(cursor, plano["IdPlano"])
        if linhas_divididas:
            connection.commit()
            plano = _buscar_plano(cursor, nr_romaneio)

        return jsonify({"success": True, "plano": plano}), 200
    except Exception as e:
        return jsonify({"error": str(e)}), 500
    finally:
        if connection:
            connection.close()


@wms_separacao_planejada_bp.route("/consulta/wms/separacao-planejada/gerar", methods=["POST"])
def separacao_planejada_gerar():
    connection = None
    try:
        data = request.get_json() or {}
        nr_romaneio = _to_int(data.get("nr_romaneio"))
        cd_usr = _to_int(data.get("cd_usr") or data.get("usuario_id"), None)
        nm_usr = (data.get("nm_usr") or data.get("usuario_nome") or "").strip()
        coletor_id = (data.get("coletor_id") or "").strip()

        if nr_romaneio <= 0:
            return jsonify({"error": "Campo obrigatório: nr_romaneio"}), 400

        connection = create_connection_tinturaria()
        if connection is None:
            return jsonify({"status": "SQL_ERROR", "details": "Falha ao conectar ao banco."}), 500

        cursor = connection.cursor()
        cursor.execute("SET NOCOUNT ON; SET XACT_ABORT ON;")

        existente = _buscar_plano(cursor, nr_romaneio)
        if existente:
            linhas_divididas = _dividir_execucoes_caixa_agregadas(cursor, existente["IdPlano"])
            if linhas_divididas:
                _log_event(
                    cursor,
                    "DIVIDIR_EXECUCOES_CAIXA",
                    {**data, "linhas_divididas": linhas_divididas},
                    cd_usr,
                    nm_usr,
                    coletor_id,
                    id_plano=existente["IdPlano"],
                )
                connection.commit()
                existente = _buscar_plano(cursor, nr_romaneio)
            return jsonify({"success": True, "message": "Plano já existente.", "plano": existente}), 200

        cursor.execute(
            """
            INSERT INTO dbo.Stik_WMS_SeparacaoPlanejada
                (NrRomaneio, Status, CdUsrCriacao, ColetorId)
            OUTPUT INSERTED.IdPlano
            VALUES (?, 'planejado', ?, ?)
        """,
            (nr_romaneio, cd_usr, coletor_id),
        )
        id_plano = cursor.fetchone()[0]

        try:
            _popular_plano(cursor, id_plano, nr_romaneio)
        except ValueError as e:
            connection.rollback()
            return jsonify({"error": str(e)}), 404

        _log_event(cursor, "GERAR_PLANO", data, cd_usr, nm_usr, coletor_id, id_plano=id_plano)
        connection.commit()

        plano = _buscar_plano(cursor, nr_romaneio)
        return jsonify({"success": True, "message": "Plano gerado com sucesso.", "plano": plano}), 201
    except Exception as e:
        if connection:
            try:
                connection.rollback()
            except Exception:
                pass
        return jsonify({"error": str(e)}), 500
    finally:
        if connection:
            connection.close()


@wms_separacao_planejada_bp.route("/consulta/wms/separacao-planejada/obter-ou-gerar", methods=["POST"])
def separacao_planejada_obter_ou_gerar():
    return separacao_planejada_gerar()


@wms_separacao_planejada_bp.route("/consulta/wms/separacao-planejada/recalcular", methods=["PATCH"])
def separacao_planejada_recalcular():
    connection = None
    try:
        data = request.get_json() or {}
        nr_romaneio = _to_int(data.get("nr_romaneio"))
        cd_usr = _to_int(data.get("cd_usr") or data.get("usuario_id"), None)
        nm_usr = (data.get("nm_usr") or data.get("usuario_nome") or "").strip()
        coletor_id = (data.get("coletor_id") or "").strip()

        if nr_romaneio <= 0:
            return jsonify({"error": "Campo obrigatório: nr_romaneio"}), 400

        connection = create_connection_tinturaria()
        cursor = connection.cursor()
        cursor.execute("SET NOCOUNT ON; SET XACT_ABORT ON;")

        cursor.execute(
            """
            SELECT IdPlano, Status
            FROM dbo.Stik_WMS_SeparacaoPlanejada WITH (UPDLOCK, HOLDLOCK)
            WHERE NrRomaneio = ?
        """,
            (nr_romaneio,),
        )
        plano = _row_dict(cursor, cursor.fetchone())
        if not plano:
            return jsonify({"error": "Plano não encontrado."}), 404
        if plano.get("Status") in ("finalizado", "enviado_conferencia"):
            return jsonify({"error": "Plano finalizado não pode ser recalculado."}), 400

        cursor.execute(
            """
            SELECT Qtd = COUNT(1)
            FROM dbo.Stik_WMS_SeparacaoPlanejada_Execucao E WITH (NOLOCK)
            INNER JOIN dbo.Stik_WMS_SeparacaoPlanejada_Item I WITH (NOLOCK)
                ON I.IdPlanoItem = E.IdPlanoItem
            WHERE I.IdPlano = ?
              AND (
                    ISNULL(E.PaleteValidado, 0) = 1 OR
                    ISNULL(E.ItemValidado, 0) = 1 OR
                    ISNULL(E.Confirmado, 0) = 1 OR
                    ISNULL(E.Cortado, 0) = 1
              )
        """,
            (plano["IdPlano"],),
        )
        execucoes_iniciadas = _to_int(cursor.fetchone()[0])
        if execucoes_iniciadas > 0:
            return jsonify({
                "error": "Plano já iniciado não pode ser recalculado sem preservar a execução."
            }), 400

        cursor.execute(
            """
            DELETE E
            FROM dbo.Stik_WMS_SeparacaoPlanejada_Execucao E
            INNER JOIN dbo.Stik_WMS_SeparacaoPlanejada_Item I
                ON I.IdPlanoItem = E.IdPlanoItem
            WHERE I.IdPlano = ?
        """,
            (plano["IdPlano"],),
        )
        cursor.execute(
            """
            DELETE FROM dbo.Stik_WMS_SeparacaoPlanejada_Item
            WHERE IdPlano = ?
        """,
            (plano["IdPlano"],),
        )
        try:
            _popular_plano(cursor, plano["IdPlano"], nr_romaneio)
        except ValueError as e:
            connection.rollback()
            return jsonify({"error": str(e)}), 404

        cursor.execute(
            """
            UPDATE dbo.Stik_WMS_SeparacaoPlanejada
            SET Versao = Versao + 1, DtAtualizacao = GETDATE()
            WHERE IdPlano = ?
        """,
            (plano["IdPlano"],),
        )

        _log_event(cursor, "RECALCULAR_PLANO", data, cd_usr, nm_usr, coletor_id, id_plano=plano["IdPlano"])
        connection.commit()
        return jsonify({"success": True, "message": "Plano recalculado.", "plano": _buscar_plano(cursor, nr_romaneio)}), 200
    except Exception as e:
        if connection:
            try:
                connection.rollback()
            except Exception:
                pass
        return jsonify({"error": str(e)}), 500
    finally:
        if connection:
            connection.close()


@wms_separacao_planejada_bp.route("/consulta/wms/separacao-planejada/item/recalcular", methods=["PATCH"])
def separacao_planejada_item_recalcular():
    """Recalcula as execuções de UM item do plano (por nr_romaneio + cd_obj +
    detalhe), preservando os demais itens do mesmo plano já iniciados —
    diferente de /recalcular, que apaga o plano inteiro."""
    connection = None
    try:
        data = request.get_json() or {}
        nr_romaneio = _to_int(data.get("nr_romaneio"))
        cd_obj = _to_int(data.get("cd_obj") or data.get("CdObj"))
        detalhe = _to_int(data.get("detalhe") or data.get("Detalhe"))
        cd_usr = _to_int(data.get("cd_usr") or data.get("usuario_id"), None)
        nm_usr = (data.get("nm_usr") or data.get("usuario_nome") or "").strip()
        coletor_id = (data.get("coletor_id") or "").strip()

        if nr_romaneio <= 0 or cd_obj <= 0:
            return jsonify({"error": "Campos obrigatórios: nr_romaneio, cd_obj"}), 400

        connection = create_connection_tinturaria()
        cursor = connection.cursor()
        cursor.execute("SET NOCOUNT ON; SET XACT_ABORT ON;")

        cursor.execute(
            """
            SELECT I.IdPlanoItem, I.IdPlano, I.CdObj, I.Detalhe, I.Objeto, I.QtRomaneio, P.Status
            FROM dbo.Stik_WMS_SeparacaoPlanejada_Item I WITH (UPDLOCK, HOLDLOCK)
            INNER JOIN dbo.Stik_WMS_SeparacaoPlanejada P WITH (UPDLOCK, HOLDLOCK) ON P.IdPlano = I.IdPlano
            WHERE P.NrRomaneio = ? AND I.CdObj = ? AND ISNULL(I.Detalhe, 0) = ISNULL(?, 0)
            """,
            (nr_romaneio, cd_obj, detalhe),
        )
        item = _row_dict(cursor, cursor.fetchone())
        if not item:
            return jsonify({"error": "Item do plano não encontrado."}), 404
        if item.get("Status") in ("finalizado", "enviado_conferencia"):
            return jsonify({"error": "Plano finalizado não pode ser recalculado."}), 400

        id_plano_item = item["IdPlanoItem"]

        cursor.execute(
            """
            SELECT Qtd = COUNT(1)
            FROM dbo.Stik_WMS_SeparacaoPlanejada_Execucao WITH (NOLOCK)
            WHERE IdPlanoItem = ?
              AND (
                    ISNULL(PaleteValidado, 0) = 1 OR
                    ISNULL(ItemValidado, 0) = 1 OR
                    ISNULL(Confirmado, 0) = 1 OR
                    ISNULL(Cortado, 0) = 1
              )
            """,
            (id_plano_item,),
        )
        execucoes_iniciadas = _to_int(cursor.fetchone()[0])
        if execucoes_iniciadas > 0:
            return jsonify({
                "error": "Item já iniciado não pode ser recalculado sem preservar a execução."
            }), 400

        cursor.execute(
            "DELETE FROM dbo.Stik_WMS_SeparacaoPlanejada_Execucao WHERE IdPlanoItem = ?",
            (id_plano_item,),
        )

        _gerar_execucoes_para_item(
            cursor,
            id_plano_item,
            item.get("CdObj"),
            item.get("Detalhe"),
            item.get("Objeto"),
            _to_float(item.get("QtRomaneio")),
        )

        cursor.execute(
            "UPDATE dbo.Stik_WMS_SeparacaoPlanejada SET Versao = Versao + 1, DtAtualizacao = GETDATE() WHERE IdPlano = ?",
            (item["IdPlano"],),
        )

        _log_event(
            cursor, "RECALCULAR_ITEM", data, cd_usr, nm_usr, coletor_id,
            id_plano=item["IdPlano"], id_plano_item=id_plano_item,
        )
        connection.commit()
        return jsonify({
            "success": True,
            "message": "Item recalculado.",
            "plano": _buscar_plano(cursor, nr_romaneio),
        }), 200
    except Exception as e:
        if connection:
            try:
                connection.rollback()
            except Exception:
                pass
        return jsonify({"error": str(e)}), 500
    finally:
        if connection:
            connection.close()


@wms_separacao_planejada_bp.route("/consulta/wms/separacao-planejada/execucao/assumir", methods=["PATCH"])
def separacao_planejada_assumir():
    connection = None
    try:
        data = request.get_json() or {}
        id_execucao = _to_int(data.get("id_execucao"))
        versao = _to_int(data.get("versao"), None)
        cd_usr = _to_int(data.get("cd_usr") or data.get("usuario_id"), None)
        nm_usr = (data.get("nm_usr") or data.get("usuario_nome") or "").strip()
        coletor_id = (data.get("coletor_id") or "").strip()

        if id_execucao <= 0 or versao is None:
            return jsonify({"error": "Campos obrigatórios: id_execucao, versao"}), 400

        connection = create_connection_tinturaria()
        cursor = connection.cursor()
        cursor.execute("SET NOCOUNT ON; SET XACT_ABORT ON;")

        execucao = _buscar_execucao(cursor, id_execucao)
        if not execucao:
            return jsonify({"error": "Execução não encontrada."}), 404
        if not _validar_versao(execucao, versao):
            return _erro_conflito(execucao)

        bloqueado_ate = execucao.get("BloqueadoAte")
        coletor_atual = (execucao.get("ColetorId") or "").strip()
        if bloqueado_ate and coletor_atual and coletor_atual != coletor_id:
            bloqueado_ate_dt = datetime.datetime.fromisoformat(bloqueado_ate) if isinstance(bloqueado_ate, str) else bloqueado_ate
            if bloqueado_ate_dt > datetime.datetime.now():
                return jsonify({"error": "Execução em uso por outro coletor.", "estado_atual": execucao}), 423

        novo_bloqueio = datetime.datetime.now() + datetime.timedelta(minutes=5)
        cursor.execute(
            """
            UPDATE dbo.Stik_WMS_SeparacaoPlanejada_Execucao
            SET CdUsr = ?, NmUsr = ?, ColetorId = ?, BloqueadoAte = ?,
                Versao = Versao + 1, DtAtualizacao = GETDATE()
            WHERE IdExecucao = ?
        """,
            (cd_usr, nm_usr, coletor_id, novo_bloqueio, id_execucao),
        )

        _log_event(cursor, "ASSUMIR_EXECUCAO", data, cd_usr, nm_usr, coletor_id, id_execucao=id_execucao)
        connection.commit()
        return jsonify({"success": True, "message": "Execução assumida.", "execucao": _buscar_execucao(cursor, id_execucao)}), 200
    except Exception as e:
        if connection:
            try:
                connection.rollback()
            except Exception:
                pass
        return jsonify({"error": str(e)}), 500
    finally:
        if connection:
            connection.close()


@wms_separacao_planejada_bp.route("/consulta/wms/separacao-planejada/execucao/validar-palete", methods=["PATCH"])
def separacao_planejada_validar_palete():
    connection = None
    try:
        data = request.get_json() or {}
        id_execucao = _to_int(data.get("id_execucao"))
        endereco_lido = _norm(data.get("endereco_lido"))
        versao = _to_int(data.get("versao"), None)
        cd_usr = _to_int(data.get("cd_usr") or data.get("usuario_id"), None)
        nm_usr = (data.get("nm_usr") or data.get("usuario_nome") or "").strip()
        coletor_id = (data.get("coletor_id") or "").strip()

        if id_execucao <= 0 or not endereco_lido or versao is None:
            return jsonify({"error": "Campos obrigatórios: id_execucao, endereco_lido, versao"}), 400

        connection = create_connection_tinturaria()
        cursor = connection.cursor()
        cursor.execute("SET NOCOUNT ON; SET XACT_ABORT ON;")
        execucao = _buscar_execucao(cursor, id_execucao)
        if not execucao:
            return jsonify({"error": "Execução não encontrada."}), 404
        if not _validar_versao(execucao, versao):
            return _erro_conflito(execucao)

        esperado = _norm(execucao.get("Endereco"))
        if endereco_lido != esperado:
            return jsonify({"error": "Palete lido não corresponde ao planejado.", "esperado": esperado, "lido": endereco_lido}), 400

        cursor.execute(
            """
            UPDATE dbo.Stik_WMS_SeparacaoPlanejada_Execucao
            SET EnderecoLido = ?, PaleteValidado = 1, CdUsr = ?, NmUsr = ?,
                ColetorId = ?, Versao = Versao + 1, DtAtualizacao = GETDATE()
            WHERE IdExecucao = ?
        """,
            (endereco_lido, cd_usr, nm_usr, coletor_id, id_execucao),
        )
        _log_event(cursor, "VALIDAR_PALETE", data, cd_usr, nm_usr, coletor_id, id_execucao=id_execucao)
        connection.commit()
        return jsonify({"success": True, "message": "Palete validado.", "execucao": _buscar_execucao(cursor, id_execucao)}), 200
    except Exception as e:
        if connection:
            try:
                connection.rollback()
            except Exception:
                pass
        return jsonify({"error": str(e)}), 500
    finally:
        if connection:
            connection.close()


@wms_separacao_planejada_bp.route("/consulta/wms/separacao-planejada/execucao/validar-item", methods=["PATCH"])
def separacao_planejada_validar_item():
    connection = None
    try:
        data = request.get_json() or {}
        id_execucao = _to_int(data.get("id_execucao"))
        qr = data.get("qr") or {}
        versao = _to_int(data.get("versao"), None)
        cd_usr = _to_int(data.get("cd_usr") or data.get("usuario_id"), None)
        nm_usr = (data.get("nm_usr") or data.get("usuario_nome") or "").strip()
        coletor_id = (data.get("coletor_id") or "").strip()

        if id_execucao <= 0 or not isinstance(qr, dict) or versao is None:
            return jsonify({"error": "Campos obrigatórios: id_execucao, qr, versao"}), 400

        connection = create_connection_tinturaria()
        cursor = connection.cursor()
        cursor.execute("SET NOCOUNT ON; SET XACT_ABORT ON;")
        execucao = _buscar_execucao(cursor, id_execucao)
        if not execucao:
            return jsonify({"error": "Execução não encontrada."}), 404
        if not _validar_versao(execucao, versao):
            return _erro_conflito(execucao)

        ok, erro = _validar_qr_execucao(execucao, qr)
        if not ok:
            return jsonify({"error": erro, "esperado": {"CdObj": execucao.get("CdObj"), "Detalhe": execucao.get("Detalhe"), "TipoCaixa": execucao.get("TipoCaixa"), "MtsPorCaixa": execucao.get("MtsPorCaixa")}, "lido": qr}), 400

        # Controle deixou de ser por CX/LI (a etiqueta não tem como o
        # operador confirmar visualmente "essa caixa pertence a este
        # palete", então essa trava gerava mais atrito que precisão real).
        # ItemValidado=1 agora significa só "confirmou ler uma etiqueta do
        # artigo/tipo/metragem esperados" (checado acima por
        # _validar_qr_execucao) — quais caixas físicas são consumidas fica
        # a cargo de separacao_planejada_confirmar, por CdObj+Detalhe+
        # TipoCaixa+endereço (FIFO), não por identidade de CX/LI.
        cursor.execute(
            """
            UPDATE dbo.Stik_WMS_SeparacaoPlanejada_Execucao
            SET ItemValidado = 1, CdUsr = ?, NmUsr = ?, ColetorId = ?,
                Versao = Versao + 1, DtAtualizacao = GETDATE()
            WHERE IdExecucao = ?
        """,
            (cd_usr, nm_usr, coletor_id, id_execucao),
        )
        _log_event(cursor, "VALIDAR_ITEM", data, cd_usr, nm_usr, coletor_id, id_execucao=id_execucao)
        connection.commit()
        return jsonify({"success": True, "message": "Item validado.", "execucao": _buscar_execucao(cursor, id_execucao)}), 200
    except Exception as e:
        if connection:
            try:
                connection.rollback()
            except Exception:
                pass
        return jsonify({"error": str(e)}), 500
    finally:
        if connection:
            connection.close()


@wms_separacao_planejada_bp.route("/consulta/wms/separacao-planejada/execucao/confirmar", methods=["PATCH"])
def separacao_planejada_confirmar():
    connection = None
    try:
        data = request.get_json() or {}
        id_execucao = _to_int(data.get("id_execucao"))
        versao = _to_int(data.get("versao"), None)
        qt_caixas = _to_int(data.get("quantidade_caixas_confirmada") or data.get("qt_caixas_confirmada"))
        mts_confirmados = _to_float(data.get("metros_confirmados") or data.get("mts_confirmados"))
        cd_usr = _to_int(data.get("cd_usr") or data.get("usuario_id"), None)
        nm_usr = (data.get("nm_usr") or data.get("usuario_nome") or "").strip()
        coletor_id = (data.get("coletor_id") or "").strip()

        if id_execucao <= 0 or versao is None:
            return jsonify({"error": "Campos obrigatórios: id_execucao, versao"}), 400

        connection = create_connection_tinturaria()
        cursor = connection.cursor()
        cursor.execute("SET NOCOUNT ON; SET XACT_ABORT ON;")
        execucao = _buscar_execucao(cursor, id_execucao)
        if not execucao:
            return jsonify({"error": "Execução não encontrada."}), 404
        if not _validar_versao(execucao, versao):
            return _erro_conflito(execucao)
        if execucao.get("Confirmado"):
            return jsonify({"error": "Execução já confirmada.", "estado_atual": execucao}), 409
        if not execucao.get("PaleteValidado"):
            return jsonify({"error": "Valide o palete antes de confirmar."}), 400
        if not execucao.get("ItemValidado"):
            return jsonify({"error": "Valide o item antes de confirmar."}), 400

        if mts_confirmados <= 0:
            mts_confirmados = _to_float(execucao.get("MtsPlanejados"))
        if mts_confirmados > _to_float(execucao.get("MtsPlanejados")) + 0.0001:
            return jsonify({"error": "Metros confirmados não podem superar o planejado."}), 400

        endereco = _norm(execucao.get("EnderecoLido") or execucao.get("Endereco"))
        cod_sku = _to_int(execucao.get("CdObj"))
        detalhe = _to_int(execucao.get("Detalhe"))
        tipo = _norm(execucao.get("TipoCaixa"))

        cursor.execute(
            """
            INSERT INTO dbo.Stik_WMS_Movimento
                (Endereco, CodSKU, Detalhe, TpMov, QtMovida, CdUsr, Origem, Observacao, DataMovimento)
            VALUES (?, ?, ?, 2, ?, ?, 'SEPARACAO_PLANEJADA', 'Saída separação planejada', GETDATE())
        """,
            (endereco, cod_sku, detalhe, mts_confirmados, cd_usr),
        )

        qt_p = qt_g = qt_enf = qt_enfr = 0
        if tipo == "P":
            qt_p = qt_caixas
        elif tipo == "G":
            qt_g = qt_caixas
        elif tipo == "ENFESTADO":
            qt_enf = qt_caixas
        elif tipo == "ENFRALDADO":
            qt_enfr = qt_caixas

        if qt_p or qt_g or qt_enf or qt_enfr:
            cursor.execute(
                """
                UPDATE dbo.Stik_WMS_Alocacao_Embalagem
                SET QtCaixaP = CASE WHEN QtCaixaP - ? < 0 THEN 0 ELSE QtCaixaP - ? END,
                    QtCaixaG = CASE WHEN QtCaixaG - ? < 0 THEN 0 ELSE QtCaixaG - ? END,
                    QtEnfestado = CASE WHEN QtEnfestado - ? < 0 THEN 0 ELSE QtEnfestado - ? END,
                    QtEnfraldado = CASE WHEN QtEnfraldado - ? < 0 THEN 0 ELSE QtEnfraldado - ? END,
                    DtAtualizacao = GETDATE()
                WHERE UPPER(LTRIM(RTRIM(Endereco))) = ?
                  AND CodSKU = ?
                  AND ISNULL(Detalhe, 0) = ISNULL(?, 0)
            """,
                (qt_p, qt_p, qt_g, qt_g, qt_enf, qt_enf, qt_enfr, qt_enfr, endereco, cod_sku, detalhe),
            )
            cursor.execute(
                """
                INSERT INTO dbo.Stik_WMS_Movimento_Embalagem
                    (EnderecoOrigem, EnderecoDestino, CodSKU, Detalhe, TpMov,
                     QtCaixaP, QtCaixaG, QtEnfestado, QtEnfraldado,
                     QtMovidaMetro, CdUsr, Origem, Observacao, DataMovimento)
                VALUES (?, NULL, ?, ?, 2, ?, ?, ?, ?, ?, ?, 'SEPARACAO_PLANEJADA', 'Saída embalagem separação planejada', GETDATE())
            """,
                (endereco, cod_sku, detalhe, qt_p, qt_g, qt_enf, qt_enfr, mts_confirmados, cd_usr),
            )

        # Marca como CONSUMIDA as qt_caixas unidades reais disponíveis
        # nesse endereço/artigo/tipo (FIFO por DataAlocacao) — não depende
        # mais de qual CX/LI o operador escaneou, só de CdObj+Detalhe+
        # TipoCaixa+Endereco baterem com o planejado. Tagueia IdExecucao
        # pra permitir o estorno (separacao_planejada_reiniciar_execucao)
        # devolver exatamente essas mesmas unidades depois.
        if tipo in ("P", "G") and qt_caixas > 0:
            cursor.execute(
                """
                ;WITH cte AS (
                    SELECT TOP (?) *
                    FROM dbo.Stik_WMS_Caixa WITH (ROWLOCK, READPAST)
                    WHERE Status = 'DISPONIVEL'
                      AND UPPER(LTRIM(RTRIM(Endereco))) = ?
                      AND CdObj = ?
                      AND ISNULL(Detalhe, 0) = ISNULL(?, 0)
                      AND TipoCaixa = ?
                    ORDER BY DataAlocacao ASC
                )
                UPDATE cte
                SET Status = 'CONSUMIDA', IdExecucao = ?, DataConsumo = GETDATE()
                """,
                (qt_caixas, endereco, cod_sku, detalhe, tipo, id_execucao),
            )

        cursor.execute(
            """
            UPDATE dbo.Stik_WMS_SeparacaoPlanejada_Execucao
            SET QtCaixasConfirmada = ?, MtsConfirmados = ?, Confirmado = 1,
                CdUsr = ?, NmUsr = ?, ColetorId = ?, Versao = Versao + 1,
                DtAtualizacao = GETDATE()
            WHERE IdExecucao = ?
        """,
            (qt_caixas, mts_confirmados, cd_usr, nm_usr, coletor_id, id_execucao),
        )

        _log_event(cursor, "CONFIRMAR_EXECUCAO", data, cd_usr, nm_usr, coletor_id, id_execucao=id_execucao)
        connection.commit()
        return jsonify({"success": True, "message": "Separação confirmada.", "execucao": _buscar_execucao(cursor, id_execucao)}), 200
    except Exception as e:
        if connection:
            try:
                connection.rollback()
            except Exception:
                pass
        return jsonify({"error": str(e)}), 500
    finally:
        if connection:
            connection.close()


@wms_separacao_planejada_bp.route("/consulta/wms/separacao-planejada/execucao/reiniciar", methods=["PATCH"])
def separacao_planejada_reiniciar_execucao():
    connection = None
    try:
        data = request.get_json() or {}
        id_execucao = _to_int(data.get("id_execucao"))
        versao = _to_int(data.get("versao"), None)
        cd_usr = _to_int(data.get("cd_usr") or data.get("usuario_id"), None)
        nm_usr = (data.get("nm_usr") or data.get("usuario_nome") or "").strip()
        coletor_id = (data.get("coletor_id") or "").strip()

        if id_execucao <= 0 or versao is None:
            return jsonify({"error": "Campos obrigatórios: id_execucao, versao"}), 400

        connection = create_connection_tinturaria()
        cursor = connection.cursor()
        cursor.execute("SET NOCOUNT ON; SET XACT_ABORT ON;")

        execucao = _buscar_execucao(cursor, id_execucao)
        if not execucao:
            return jsonify({"error": "Execução não encontrada."}), 404
        if not _validar_versao(execucao, versao):
            return _erro_conflito(execucao)

        endereco = _norm(execucao.get("EnderecoLido") or execucao.get("Endereco"))
        cod_sku = _to_int(execucao.get("CdObj"))
        detalhe = _to_int(execucao.get("Detalhe"))
        mts_confirmados = _to_float(execucao.get("MtsConfirmados"))
        qt_caixas = _to_int(execucao.get("QtCaixasConfirmada"))
        tipo = _norm(execucao.get("TipoCaixa"))

        if execucao.get("Confirmado") and mts_confirmados > 0:
            cursor.execute(
                """
                INSERT INTO dbo.Stik_WMS_Movimento
                    (Endereco, CodSKU, Detalhe, TpMov, QtMovida, CdUsr, Origem, Observacao, DataMovimento)
                VALUES (?, ?, ?, 1, ?, ?, 'SEPARACAO_PLANEJADA_ESTORNO', 'Estorno separação planejada', GETDATE())
            """,
                (endereco, cod_sku, detalhe, mts_confirmados, cd_usr),
            )

            qt_p = qt_g = qt_enf = qt_enfr = 0
            if tipo == "P":
                qt_p = qt_caixas
            elif tipo == "G":
                qt_g = qt_caixas
            elif tipo == "ENFESTADO":
                qt_enf = qt_caixas
            elif tipo == "ENFRALDADO":
                qt_enfr = qt_caixas

            if qt_p or qt_g or qt_enf or qt_enfr:
                cursor.execute(
                    """
                    UPDATE dbo.Stik_WMS_Alocacao_Embalagem
                    SET QtCaixaP = ISNULL(QtCaixaP, 0) + ?,
                        QtCaixaG = ISNULL(QtCaixaG, 0) + ?,
                        QtEnfestado = ISNULL(QtEnfestado, 0) + ?,
                        QtEnfraldado = ISNULL(QtEnfraldado, 0) + ?,
                        DtAtualizacao = GETDATE()
                    WHERE UPPER(LTRIM(RTRIM(Endereco))) = ?
                      AND CodSKU = ?
                      AND ISNULL(Detalhe, 0) = ISNULL(?, 0)
                """,
                    (qt_p, qt_g, qt_enf, qt_enfr, endereco, cod_sku, detalhe),
                )
                if cursor.rowcount == 0:
                    cursor.execute(
                        """
                        INSERT INTO dbo.Stik_WMS_Alocacao_Embalagem
                            (Endereco, CodSKU, Detalhe, QtCaixaP, QtCaixaG, QtEnfestado, QtEnfraldado, DtAtualizacao)
                        VALUES (?, ?, ?, ?, ?, ?, ?, GETDATE())
                    """,
                        (endereco, cod_sku, detalhe, qt_p, qt_g, qt_enf, qt_enfr),
                    )

                cursor.execute(
                    """
                    INSERT INTO dbo.Stik_WMS_Movimento_Embalagem
                        (EnderecoOrigem, EnderecoDestino, CodSKU, Detalhe, TpMov,
                         QtCaixaP, QtCaixaG, QtEnfestado, QtEnfraldado,
                         QtMovidaMetro, CdUsr, Origem, Observacao, DataMovimento)
                    VALUES (NULL, ?, ?, ?, 1, ?, ?, ?, ?, ?, ?, 'SEPARACAO_PLANEJADA_ESTORNO', 'Estorno embalagem separação planejada', GETDATE())
                """,
                    (endereco, cod_sku, detalhe, qt_p, qt_g, qt_enf, qt_enfr, mts_confirmados, cd_usr),
                )

            # Devolve as caixas físicas consumidas na confirmação de volta
            # para disponível, já que a separação está sendo desfeita — não
            # depende de CX/LI, só do IdExecucao gravado na confirmação.
            cursor.execute(
                """
                UPDATE dbo.Stik_WMS_Caixa
                SET Status = 'DISPONIVEL', IdExecucao = NULL, DataConsumo = NULL
                WHERE IdExecucao = ?
                """,
                (id_execucao,),
            )

        cursor.execute(
            """
            UPDATE dbo.Stik_WMS_SeparacaoPlanejada_Execucao
            SET EnderecoLido = NULL,
                CxLido = NULL,
                LiLido = NULL,
                PaleteValidado = 0,
                ItemValidado = 0,
                Confirmado = 0,
                Cortado = 0,
                QtCaixasConfirmada = 0,
                MtsConfirmados = 0,
                QtCaixasCortada = 0,
                MtsCortados = 0,
                MotivoCorte = NULL,
                CdUsr = ?,
                NmUsr = ?,
                ColetorId = ?,
                BloqueadoAte = NULL,
                Versao = Versao + 1,
                DtAtualizacao = GETDATE()
            WHERE IdExecucao = ?
        """,
            (cd_usr, nm_usr, coletor_id, id_execucao),
        )

        _log_event(cursor, "REINICIAR_EXECUCAO", data, cd_usr, nm_usr, coletor_id, id_execucao=id_execucao)
        connection.commit()
        return jsonify({"success": True, "message": "Execução reiniciada.", "execucao": _buscar_execucao(cursor, id_execucao)}), 200
    except Exception as e:
        if connection:
            try:
                connection.rollback()
            except Exception:
                pass
        return jsonify({"error": str(e)}), 500
    finally:
        if connection:
            connection.close()


@wms_separacao_planejada_bp.route("/consulta/wms/separacao-planejada/execucao/cortar", methods=["PATCH"])
def separacao_planejada_cortar():
    connection = None
    try:
        data = request.get_json() or {}
        id_execucao = _to_int(data.get("id_execucao"))
        versao = _to_int(data.get("versao"), None)
        mts_cortados = _to_float(data.get("metros_cortados") or data.get("mts_cortados"))
        qt_caixas = _to_int(data.get("quantidade_caixas_cortada") or data.get("qt_caixas_cortada"))
        motivo = (data.get("motivo") or "").strip()
        cd_usr = _to_int(data.get("cd_usr") or data.get("usuario_id"), None)
        nm_usr = (data.get("nm_usr") or data.get("usuario_nome") or "").strip()
        coletor_id = (data.get("coletor_id") or "").strip()

        if id_execucao <= 0 or versao is None:
            return jsonify({"error": "Campos obrigatórios: id_execucao, versao"}), 400
        if not motivo:
            return jsonify({"error": "Campo obrigatório: motivo"}), 400

        connection = create_connection_tinturaria()
        cursor = connection.cursor()
        cursor.execute("SET NOCOUNT ON; SET XACT_ABORT ON;")
        execucao = _buscar_execucao(cursor, id_execucao)
        if not execucao:
            return jsonify({"error": "Execução não encontrada."}), 404
        if not _validar_versao(execucao, versao):
            return _erro_conflito(execucao)
        if execucao.get("Confirmado"):
            return jsonify({"error": "Execução confirmada não pode ser cortada."}), 409

        if mts_cortados <= 0:
            mts_cortados = _to_float(execucao.get("MtsPlanejados"))
        if mts_cortados > _to_float(execucao.get("MtsPlanejados")) + 0.0001:
            return jsonify({"error": "Metros cortados não podem superar o planejado."}), 400

        cursor.execute(
            """
            UPDATE dbo.Stik_WMS_SeparacaoPlanejada_Execucao
            SET QtCaixasCortada = ?, MtsCortados = ?, Cortado = 1,
                MotivoCorte = ?, CdUsr = ?, NmUsr = ?, ColetorId = ?,
                Versao = Versao + 1, DtAtualizacao = GETDATE()
            WHERE IdExecucao = ?
        """,
            (qt_caixas, mts_cortados, motivo, cd_usr, nm_usr, coletor_id, id_execucao),
        )
        _log_event(cursor, "CORTAR_EXECUCAO", data, cd_usr, nm_usr, coletor_id, id_execucao=id_execucao)
        connection.commit()
        return jsonify({"success": True, "message": "Corte registrado.", "execucao": _buscar_execucao(cursor, id_execucao)}), 200
    except Exception as e:
        if connection:
            try:
                connection.rollback()
            except Exception:
                pass
        return jsonify({"error": str(e)}), 500
    finally:
        if connection:
            connection.close()


@wms_separacao_planejada_bp.route("/consulta/wms/separacao-planejada/enviar-conferencia", methods=["POST"])
def separacao_planejada_enviar_conferencia():
    connection = None
    try:
        data = request.get_json() or {}
        nr_romaneio = _to_int(data.get("nr_romaneio"))
        cd_usr = _to_int(data.get("cd_usr") or data.get("usuario_id"), None)
        nm_usr = (data.get("nm_usr") or data.get("usuario_nome") or "").strip()
        coletor_id = (data.get("coletor_id") or "").strip()

        if nr_romaneio <= 0:
            return jsonify({"error": "Campo obrigatório: nr_romaneio"}), 400

        connection = create_connection_tinturaria()
        cursor = connection.cursor()
        cursor.execute("SET NOCOUNT ON; SET XACT_ABORT ON;")
        cursor.execute(
            """
            SELECT IdPlano, Status
            FROM dbo.Stik_WMS_SeparacaoPlanejada WITH (UPDLOCK, HOLDLOCK)
            WHERE NrRomaneio = ?
        """,
            (nr_romaneio,),
        )
        plano = _row_dict(cursor, cursor.fetchone())
        if not plano:
            return jsonify({"error": "Plano não encontrado."}), 404

        cursor.execute(
            """
            SELECT E.IdExecucao, I.CdObj, I.Detalhe, I.NmLot, E.Endereco
            FROM dbo.Stik_WMS_SeparacaoPlanejada_Execucao E WITH (NOLOCK)
            INNER JOIN dbo.Stik_WMS_SeparacaoPlanejada_Item I WITH (NOLOCK)
                ON I.IdPlanoItem = E.IdPlanoItem
            WHERE I.IdPlano = ?
              AND ISNULL(E.Confirmado, 0) = 0
              AND ISNULL(E.Cortado, 0) = 0
        """,
            (plano["IdPlano"],),
        )
        pendentes = _fetch_all_dict(cursor)
        if pendentes:
            return jsonify({"error": "Existem execuções pendentes.", "pendentes": _json_safe(pendentes)}), 400

        cursor.execute(
            """
            SELECT I.CdVpo, I.CdObj, I.Detalhe, NmLot = MAX(ISNULL(I.NmLot, '')),
                   QtRomaneio = MAX(I.QtRomaneio),
                   QtSeparada = SUM(ISNULL(E.MtsConfirmados, 0))
            FROM dbo.Stik_WMS_SeparacaoPlanejada_Item I WITH (NOLOCK)
            INNER JOIN dbo.Stik_WMS_SeparacaoPlanejada_Execucao E WITH (NOLOCK)
                ON E.IdPlanoItem = I.IdPlanoItem
            WHERE I.IdPlano = ?
            GROUP BY I.CdVpo, I.CdObj, I.Detalhe
        """,
            (plano["IdPlano"],),
        )
        itens_consolidados = _fetch_all_dict(cursor)

        cd_usr_str = str(cd_usr) if cd_usr is not None else ""
        for item in itens_consolidados:
            cursor.execute(
                """
                INSERT INTO dbo.Stik_WMS_Romaneio_Conferencia
                    (NrRomaneio, CdVpo, CdObj, Detalhe, SituacaoConferencia, CdUsrConf, DtConf)
                SELECT ?, ?, ?, ?, 'Separado', ?, GETDATE()
                WHERE NOT EXISTS (
                    SELECT 1 FROM dbo.Stik_WMS_Romaneio_Conferencia WITH (NOLOCK)
                    WHERE NrRomaneio = ? AND CdVpo = ?
                )
                """,
                (
                    nr_romaneio,
                    item["CdVpo"],
                    item["CdObj"],
                    item.get("NmLot") or "",
                    cd_usr_str,
                    nr_romaneio,
                    item["CdVpo"],
                ),
            )

        cursor.execute(
            """
            UPDATE dbo.Stik_WMS_SeparacaoPlanejada
            SET Status = 'enviado_conferencia', Versao = Versao + 1,
                DtAtualizacao = GETDATE()
            WHERE IdPlano = ?
        """,
            (plano["IdPlano"],),
        )
        _log_event(cursor, "ENVIAR_CONFERENCIA", {**data, "itens_consolidados": _json_safe(itens_consolidados)}, cd_usr, nm_usr, coletor_id, id_plano=plano["IdPlano"])
        connection.commit()
        return jsonify({"success": True, "message": "Romaneio enviado para conferência.", "nr_romaneio": nr_romaneio, "status": "enviado_conferencia", "itens": _json_safe(itens_consolidados)}), 200
    except Exception as e:
        if connection:
            try:
                connection.rollback()
            except Exception:
                pass
        return jsonify({"error": str(e)}), 500
    finally:
        if connection:
            connection.close()


@wms_separacao_planejada_bp.route("/consulta/wms/separacao-planejada/lista-conferencia", methods=["GET"])
def separacao_planejada_lista_conferencia():
    connection = None
    try:
        connection = create_connection_tinturaria()
        if connection is None:
            return jsonify({"error": "Falha ao conectar ao banco."}), 500

        cursor = connection.cursor()
        cursor.execute(
            """
            SELECT
                P.NrRomaneio,
                ID               = I.IdPlanoItem,
                I.CdVpo,
                I.CdVpd,
                CdObj            = I.CdObj,
                CdLot            = I.Detalhe,
                Cliente          = ISNULL(
                    (SELECT TOP 1 C.NmCli
                     FROM dbo.TbVpd V WITH (NOLOCK)
                     INNER JOIN dbo.TbCli C WITH (NOLOCK) ON C.CdCli = V.CdCli
                     WHERE V.CdVpd = I.CdVpd),
                    ''
                ),
                Objeto           = I.Objeto,
                Detalhe          = I.NmLot,
                DataExpedicao    = NULL,
                DataConclusaoSep = P.DtAtualizacao,
                Separador        = ISNULL((
                    SELECT TOP 1 NmUsr
                    FROM dbo.Stik_WMS_SeparacaoPlanejada_Execucao WITH (NOLOCK)
                    WHERE IdPlanoItem = I.IdPlanoItem
                      AND NmUsr IS NOT NULL AND NmUsr <> ''
                ), ''),
                TotalItens       = (
                    SELECT COUNT(*)
                    FROM dbo.Stik_WMS_SeparacaoPlanejada_Item WITH (NOLOCK)
                    WHERE IdPlano = P.IdPlano
                ),
                QtRomaneio       = I.QtRomaneio,
                QtSeparada       = ISNULL((
                    SELECT SUM(MtsConfirmados)
                    FROM dbo.Stik_WMS_SeparacaoPlanejada_Execucao WITH (NOLOCK)
                    WHERE IdPlanoItem = I.IdPlanoItem
                      AND ISNULL(Confirmado, 0) = 1
                ), 0),
                Fonte            = 'wms'
            FROM dbo.Stik_WMS_SeparacaoPlanejada P WITH (NOLOCK)
            INNER JOIN dbo.Stik_WMS_SeparacaoPlanejada_Item I WITH (NOLOCK)
                ON I.IdPlano = P.IdPlano
            WHERE P.Status = 'enviado_conferencia'
            ORDER BY P.NrRomaneio DESC, I.IdPlanoItem
            """
        )
        items = _fetch_all_dict(cursor)
        return jsonify(items), 200
    except Exception as e:
        return jsonify({"error": str(e)}), 500
    finally:
        if connection:
            connection.close()


@wms_separacao_planejada_bp.route("/consulta/wms/separacao-planejada/preparar-conferencia", methods=["POST"])
def separacao_planejada_preparar_conferencia():
    """Garante que os itens WMS existam em Stik_WMS_Romaneio_Conferencia
    para que o endpoint ERP /separado_conferido os encontre."""
    connection = None
    try:
        data = request.get_json() or {}
        nr_romaneio = _to_int(data.get("nr_romaneio"))
        cd_usr = _to_int(data.get("cd_usr") or data.get("usuario_id"), None)

        if nr_romaneio <= 0:
            return jsonify({"error": "Campo obrigatório: nr_romaneio"}), 400

        connection = create_connection_tinturaria()
        cursor = connection.cursor()
        cursor.execute("SET NOCOUNT ON; SET XACT_ABORT ON;")

        cursor.execute(
            """
            SELECT IdPlano FROM dbo.Stik_WMS_SeparacaoPlanejada WITH (NOLOCK)
            WHERE NrRomaneio = ? AND Status = 'enviado_conferencia'
            """,
            (nr_romaneio,),
        )
        row = cursor.fetchone()
        if not row:
            return jsonify({"error": "Romaneio não encontrado ou não está em conferência."}), 404

        id_plano = row[0]
        cursor.execute(
            """
            SELECT I.CdVpo, I.CdObj, ISNULL(I.NmLot, '') AS NmLot
            FROM dbo.Stik_WMS_SeparacaoPlanejada_Item I WITH (NOLOCK)
            WHERE I.IdPlano = ?
            """,
            (id_plano,),
        )
        itens = _fetch_all_dict(cursor)

        cd_usr_str = str(cd_usr) if cd_usr is not None else ""
        inseridos = 0
        for item in itens:
            cursor.execute(
                """
                INSERT INTO dbo.Stik_WMS_Romaneio_Conferencia
                    (NrRomaneio, CdVpo, CdObj, Detalhe, SituacaoConferencia, CdUsrConf, DtConf)
                SELECT ?, ?, ?, ?, 'Separado', ?, GETDATE()
                WHERE NOT EXISTS (
                    SELECT 1 FROM dbo.Stik_WMS_Romaneio_Conferencia WITH (NOLOCK)
                    WHERE NrRomaneio = ? AND CdVpo = ?
                )
                """,
                (
                    nr_romaneio, item["CdVpo"], item["CdObj"], item["NmLot"],
                    cd_usr_str,
                    nr_romaneio, item["CdVpo"],
                ),
            )
            inseridos += cursor.rowcount

        connection.commit()
        return jsonify({"success": True, "nr_romaneio": nr_romaneio, "itens_inseridos": inseridos}), 200
    except Exception as e:
        if connection:
            try:
                connection.rollback()
            except Exception:
                pass
        return jsonify({"error": str(e)}), 500
    finally:
        if connection:
            connection.close()


@wms_separacao_planejada_bp.route("/consulta/wms/separacao-planejada/conferir", methods=["POST"])
def separacao_planejada_conferir():
    connection = None
    try:
        data = request.get_json() or {}
        nr_romaneio = _to_int(data.get("nr_romaneio"))
        cd_usr = _to_int(data.get("cd_usr") or data.get("usuario_id"), None)
        nm_usr = (data.get("nm_usr") or data.get("usuario_nome") or "").strip()
        coletor_id = (data.get("coletor_id") or "").strip()

        if nr_romaneio <= 0:
            return jsonify({"error": "Campo obrigatório: nr_romaneio"}), 400

        connection = create_connection_tinturaria()
        cursor = connection.cursor()
        cursor.execute("SET NOCOUNT ON; SET XACT_ABORT ON;")

        cursor.execute(
            """
            SELECT IdPlano FROM dbo.Stik_WMS_SeparacaoPlanejada WITH (UPDLOCK, HOLDLOCK)
            WHERE NrRomaneio = ? AND Status = 'enviado_conferencia'
            """,
            (nr_romaneio,),
        )
        row = cursor.fetchone()
        if not row:
            return jsonify({"error": "Romaneio não encontrado ou não está em conferência."}), 404

        id_plano = row[0]
        cursor.execute(
            """
            UPDATE dbo.Stik_WMS_SeparacaoPlanejada
            SET Status = 'conferido', Versao = Versao + 1, DtAtualizacao = GETDATE()
            WHERE IdPlano = ?
            """,
            (id_plano,),
        )
        tp_sit_fat = _to_int(data.get("tp_sit_fat"), 4) or 4
        cd_usr_str = str(cd_usr) if cd_usr is not None else None
        cursor.execute(
            """
            UPDATE dbo.Stik_Pedido_QtdFat
            SET TpSitFat = ?,
                CdUsrConf = ISNULL(?, CdUsrConf),
                DtConf    = GETDATE()
            WHERE NrRomaneio = ?
            """,
            (tp_sit_fat, cd_usr_str, nr_romaneio),
        )
        _log_event(cursor, "CONFERIR", data, cd_usr, nm_usr, coletor_id, id_plano=id_plano)
        connection.commit()
        return jsonify({"success": True, "nr_romaneio": nr_romaneio, "status": "conferido"}), 200
    except Exception as e:
        if connection:
            try:
                connection.rollback()
            except Exception:
                pass
        return jsonify({"error": str(e)}), 500
    finally:
        if connection:
            connection.close()
