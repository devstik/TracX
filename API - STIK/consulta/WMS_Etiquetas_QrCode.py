# import json
# import re
# import time
# from datetime import date

# from flask import Blueprint, jsonify, request

# from database.server import create_connection_tinturaria

# WMS_Etiquetas_QrCode_bp = Blueprint("WMS_Etiquetas_QrCode", __name__)

# _MESES_LETRA = ['A', 'B', 'C', 'D', 'E', 'F', 'G', 'H', 'I', 'J', 'K', 'L']

# # CdObjs que exigem DETALHE obrigatório e imprimem detalhe/lote especial
# _CDOBJ_DETALHE_OBRIGATORIO = {20287, 52218, 21532, 94439, 92377, 97874, 99516, 100771}

# # CdObjs PRETO especial que fazem auto-resolve do detalhe pelo Max(CdLot)
# _CDOBJ_PRETO_AUTO_LOT = {92149, 86237, 84992, 31025, 98471, 21532, 94439, 92377, 97874, 100771, 81849}


# _B36 = "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ"

# def _gerar_cx() -> str:
#     """Gera código único de rastreio da caixa: timestamp ms em base-36 (ex.: KNUP0G4)."""
#     val = int(time.time() * 1000)
#     digits = []
#     while val:
#         digits.append(_B36[val % 36])
#         val //= 36
#     return "".join(reversed(digits))


# def _to_int(value, default=0):
#     try:
#         if value in (None, ""):
#             return default
#         return int(value)
#     except Exception:
#         return default


# def _row_dict(cursor, row):
#     if not row:
#         return None
#     columns = [col[0] for col in cursor.description]
#     return {columns[i]: row[i] for i in range(len(columns))}


# def _only_digits(value):
#     return (value or "").strip().isdigit()


# def _calcular_data_codificada(dia, mes, ano):
#     return f"{str(dia).zfill(2)}{_MESES_LETRA[mes - 1]}{str(ano)[-1]}"


# def _calcular_mes_ano_codificado(mes, ano):
#     return f"{_MESES_LETRA[mes - 1]}{str(ano)[-1]}"


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
#         return {}

#     cursor.execute(
#         """
#         SELECT TOP 1
#             caixa_p = ISNULL(caixa_p, 0),
#             caixa_g = ISNULL(caixa_g, 0)
#         FROM dbo.Stik_PadraoCaixa WITH (NOLOCK)
#         WHERE UPPER(LTRIM(RTRIM(artigo))) = UPPER(LTRIM(RTRIM(?)))
#         """,
#         (artigo_mae,),
#     )
#     return _row_dict(cursor, cursor.fetchone()) or {}


# @WMS_Etiquetas_QrCode_bp.route("/consulta/wms/artigo-info", methods=["GET"])
# def WMS_Etiquetas_QrCode_artigo_info():
#     """Retorna metadados do artigo para a etapa de busca (sem metros/ordem)."""
#     connection = None
#     try:
#         cd_obj = _to_int(
#             request.args.get("cd_obj")
#             or request.args.get("CdObj")
#             or request.args.get("cd")
#         )
#         if cd_obj <= 0:
#             return jsonify({"error": "Parâmetro obrigatório: cd_obj"}), 400

#         connection = create_connection_tinturaria()
#         if connection is None:
#             return jsonify({"error": "Falha ao conectar ao banco."}), 500

#         cursor = connection.cursor()
#         cursor.execute(
#             """
#             SELECT TOP 1
#                 Obj.CdObj,
#                 NmObj  = UPPER(Obj.NmObj),
#                 NmObj1 = UPPER(CASE
#                     WHEN CHARINDEX('MM', UPPER(Obj.NmObj)) > 0
#                     THEN LEFT(Obj.NmObj, CHARINDEX('MM', UPPER(Obj.NmObj)) + 1)
#                     ELSE Obj.NmObj END),
#                 NmObj2 = UPPER(CASE
#                     WHEN CHARINDEX('MM', UPPER(Obj.NmObj)) > 0
#                     THEN LTRIM(SUBSTRING(Obj.NmObj, CHARINDEX('MM', UPPER(Obj.NmObj)) + 2, LEN(Obj.NmObj)))
#                     ELSE '' END),
#                 Descricao = ISNULL(Obj.TtObj, ''),
#                 Setor     = ISNULL(Obj.CdObjLin, 0),
#                 TipoCaixa = CASE
#                     WHEN Carretel.NmOpc = 'ENF'                   THEN 'ENFE'
#                     WHEN Carretel.NmOpc = 'ENFRALDADO'            THEN 'ENFR'
#                     WHEN Carretel.NmOpc IS NULL                   THEN ''
#                     WHEN TRY_CAST(Carretel.NmOpc AS int) <= 1200  THEN 'P'
#                     WHEN TRY_CAST(Carretel.NmOpc AS int) >  1200  THEN 'G'
#                     ELSE 'D' END,
#                 Metragem = CASE
#                     WHEN Carretel.NmOpc = 'ENF'        THEN 'ENF - Enfestado'
#                     WHEN Carretel.NmOpc = 'ENFRALDADO' THEN 'ENFRALDADO'
#                     WHEN Carretel.NmOpc IS NULL         THEN ''
#                     ELSE CONVERT(varchar(50), Carretel.NmOpc) + ' Mts' END
#             FROM dbo.TbObj Obj WITH (NOLOCK)
#             LEFT JOIN (
#                 SELECT Opo.CdObj, NmOpc = Opc.NmOpc
#                 FROM dbo.TbOpo Opo WITH (NOLOCK)
#                 JOIN dbo.TbCrc Crc WITH (NOLOCK) ON Crc.CdCrc = Opo.CdCrc
#                 JOIN dbo.TbCgr Cgr WITH (NOLOCK)
#                   ON Cgr.CdCgr = Opo.CdCgr AND Cgr.CdCrc = Crc.CdCrc AND Crc.CdCrc = 96
#                 LEFT JOIN dbo.TbOpc Opc WITH (NOLOCK) ON Opc.CdOpc = Opo.CdOpc
#                 WHERE EXISTS (
#                     SELECT 1 FROM dbo.TbArvObj ArvObj WITH (NOLOCK)
#                     WHERE ArvObj.CdObjFil = Opo.CdObj AND ArvObj.CdObj = ?
#                 )
#             ) Carretel ON Carretel.CdObj = Obj.CdObj
#             WHERE EXISTS (
#                 SELECT 1 FROM dbo.TbArvObj ArvObj WITH (NOLOCK)
#                 WHERE ArvObj.CdObjFil = Obj.CdObj AND ArvObj.CdObj = ?
#             )
#             ORDER BY Obj.CdObj
#             """,
#             (cd_obj, cd_obj),
#         )
#         row = _row_dict(cursor, cursor.fetchone())
#         if not row:
#             return jsonify({"error": f"Artigo {cd_obj} não encontrado."}), 404

#         nm_obj = str(row.get("NmObj") or "").strip().upper()
#         setor = int(row.get("Setor") or 0)
#         tem_preto = "PRETO" in nm_obj
#         nao_imprime_lote_linha = "ENFRALDADO" in nm_obj or "ENFESTADO" in nm_obj
#         detalhe_obrigatorio = cd_obj in _CDOBJ_DETALHE_OBRIGATORIO or setor == 10180

#         result = {
#             "CdObj": cd_obj,
#             "NmObj": nm_obj,
#             "NmObj1": str(row.get("NmObj1") or "").strip(),
#             "NmObj2": str(row.get("NmObj2") or "").strip(),
#             "Descricao": str(row.get("Descricao") or "").strip(),
#             "TipoCaixa": str(row.get("TipoCaixa") or "").strip().upper(),
#             "Metragem": str(row.get("Metragem") or "").strip(),
#             "Setor": setor,
#             "Setor10180": setor == 10180,
#             "TemPreto": tem_preto,
#             "NaoImprimeLoteLinha": nao_imprime_lote_linha,
#             "DetalheObrigatorio": detalhe_obrigatorio,
#         }
#         return jsonify({"success": True, "data": result}), 200

#     except Exception as e:
#         return jsonify({"error": str(e)}), 500
#     finally:
#         if connection:
#             connection.close()


# @WMS_Etiquetas_QrCode_bp.route("/consulta/wms/etiqueta-caixa", methods=["GET"])
# def WMS_Etiquetas_QrCode_etiqueta_caixa():
#     connection = None
#     try:
#         cd_obj = _to_int(
#             request.args.get("cd_obj")
#             or request.args.get("CdObj")
#             or request.args.get("cd")
#         )
#         detalhe = _to_int(
#             request.args.get("detalhe")
#             or request.args.get("Detalhe")
#             or request.args.get("cd_lot"),
#             0,
#         )
#         metros = (request.args.get("metros") or request.args.get("Metros") or "").strip()
#         nr_ordem = (
#             request.args.get("nr_ordem")
#             or request.args.get("NrOrdem")
#             or request.args.get("nro_ordem")
#             or request.args.get("ordem")
#             or ""
#         ).strip()

#         if cd_obj <= 0:
#             return jsonify({"error": "Parâmetro obrigatório: cd_obj"}), 400
#         if not metros:
#             return jsonify({"error": "Parâmetro obrigatório: metros"}), 400
#         if not _only_digits(metros):
#             return jsonify({"error": "Parâmetro metros aceita apenas números."}), 400
#         if nr_ordem and not _only_digits(nr_ordem):
#             return jsonify({"error": "Parâmetro nr_ordem aceita apenas números."}), 400

#         connection = create_connection_tinturaria()
#         if connection is None:
#             return jsonify({"status": "SQL_ERROR", "details": "Falha ao conectar ao banco."}), 500

#         cursor = connection.cursor()
#         cursor.execute(
#             """
#             SELECT TOP 1
#                 Obj.CdObj,
#                 DetalheId = ISNULL(Lot.CdLot, 0),
#                 NmObj = UPPER(Obj.NmObj),
#                 NmObj1 = UPPER(
#                     CASE
#                         WHEN CHARINDEX('MM', UPPER(Obj.NmObj)) > 0
#                         THEN LEFT(Obj.NmObj, CHARINDEX('MM', UPPER(Obj.NmObj)) + 1)
#                         ELSE Obj.NmObj
#                     END
#                 ),
#                 NmObj2 = UPPER(
#                     CASE
#                         WHEN CHARINDEX('MM', UPPER(Obj.NmObj)) > 0
#                         THEN LTRIM(SUBSTRING(Obj.NmObj, CHARINDEX('MM', UPPER(Obj.NmObj)) + 2, LEN(Obj.NmObj)))
#                         ELSE ''
#                     END
#                 ),
#                 Detalhe = ISNULL(Lot.NmLot, ''),
#                 Descricao = ISNULL(Obj.TtObj, ''),
#                 Ean13 = ISNULL(dbo.UFN_GeraCodigoEAN(CaoEan13.NrCao), ''),
#                 Ean14 = ISNULL(CONVERT(varchar(50), CaoEan14.NrCao), ''),
#                 Metros = '',
#                 Lote = '',
#                 Operador = '',
#                 NrOrdem = '',
#                 TipoCaixa = CASE
#                     WHEN Carretel.NmOpc = 'ENF'                   THEN 'ENFE'
#                     WHEN Carretel.NmOpc = 'ENFRALDADO'            THEN 'ENFR'
#                     WHEN Carretel.NmOpc IS NULL                   THEN ''
#                     WHEN TRY_CAST(Carretel.NmOpc AS int) <= 1200  THEN 'P'
#                     WHEN TRY_CAST(Carretel.NmOpc AS int) >  1200  THEN 'G'
#                     ELSE 'D'
#                 END,
#                 DataFabricacao = CONVERT(varchar(10), GETDATE(), 103),
#                 Metragem = CASE
#                     WHEN Carretel.NmOpc = 'ENF' THEN 'ENF - Enfestado'
#                     WHEN Carretel.NmOpc = 'ENFRALDADO' THEN 'ENFRALDADO'
#                     WHEN Carretel.NmOpc IS NULL THEN ''
#                     ELSE CONVERT(varchar(50), Carretel.NmOpc) + ' Mts'
#                 END,
#                 Mae = Obj.CdObjMae
#             FROM dbo.TbObj Obj WITH (NOLOCK)
#             LEFT JOIN dbo.TbLot Lot WITH (NOLOCK)
#                    ON Lot.CdObj = Obj.CdObj
#                   AND Lot.CdLot = ?
#             LEFT JOIN dbo.TbCao CaoEan13 WITH (NOLOCK)
#                    ON CaoEan13.CdObj = Obj.CdObj
#                   AND CaoEan13.CdTca = 2
#             LEFT JOIN dbo.TbCao CaoEan14 WITH (NOLOCK)
#                    ON CaoEan14.CdObj = Obj.CdObj
#                   AND CaoEan14.CdTca = 4
#             LEFT JOIN (
#                 SELECT
#                     Opo.CdObj,
#                     Opo.CdCrc,
#                     NmOpc = Opc.NmOpc
#                 FROM dbo.TbOpo Opo WITH (NOLOCK)
#                 JOIN dbo.TbCrc Crc WITH (NOLOCK)
#                   ON Crc.CdCrc = Opo.CdCrc
#                 JOIN dbo.TbCgr Cgr WITH (NOLOCK)
#                   ON Cgr.CdCgr = Opo.CdCgr
#                  AND Cgr.CdCrc = Crc.CdCrc
#                  AND Crc.CdCrc = 96
#                 LEFT JOIN dbo.TbOpc Opc WITH (NOLOCK)
#                   ON Opc.CdOpc = Opo.CdOpc
#                 WHERE EXISTS (
#                     SELECT 1
#                     FROM dbo.TbArvObj ArvObj WITH (NOLOCK)
#                     WHERE ArvObj.CdObjFil = Opo.CdObj
#                       AND ArvObj.CdObj = ?
#                 )
#             ) Carretel
#               ON Carretel.CdObj = Obj.CdObj
#             WHERE EXISTS (
#                 SELECT 1
#                 FROM dbo.TbArvObj ArvObj WITH (NOLOCK)
#                 WHERE ArvObj.CdObjFil = Obj.CdObj
#                   AND ArvObj.CdObj = ?
#             )
#             ORDER BY Obj.CdObj
#             """,
#             (detalhe, cd_obj, cd_obj),
#         )
#         data = _row_dict(cursor, cursor.fetchone())
#         if not data:
#             return jsonify({"error": "Dados da etiqueta caixa não encontrados."}), 404

#         tipo_caixa = str(data.get("TipoCaixa") or "").strip().upper()
#         if tipo_caixa not in ("P", "G", "ENFE", "ENFR", "D"):
#             return jsonify({
#                 "error": "Tipo de caixa inválido ou não localizado pela API.",
#                 "tipo_caixa": tipo_caixa,
#                 "permitidos": ["P", "G", "ENFE", "ENFR", "D"],
#             }), 400

#         data["Metros"] = metros
#         data["NrOrdem"] = nr_ordem
#         data["QrCode"] = json.dumps({
#             "CdObj": data.get("CdObj") or 0,
#             "Detalhe": data.get("DetalheId") or 0,
#             "TipoCaixa": tipo_caixa,
#             "Fabricacao": data.get("DataFabricacao") or "",
#             "NrOrdem": nr_ordem,
#         }, ensure_ascii=False, separators=(",", ":"))
#         data["TipoCaixa"] = tipo_caixa

#         return jsonify({"success": True, "data": data}), 200

#     except Exception as e:
#         return jsonify({"error": str(e)}), 500

#     finally:
#         if connection:
#             connection.close()


# @WMS_Etiquetas_QrCode_bp.route("/consulta/wms/etiqueta-caixa-v2", methods=["POST"])
# def WMS_Etiquetas_QrCode_etiqueta_caixa_v2():
#     connection = None
#     try:
#         body = request.get_json(silent=True) or {}

#         cd_obj = _to_int(body.get("cd_obj") or body.get("CdObj"))
#         metros = str(body.get("metros") or body.get("Metros") or "").strip()
#         nr_ordem = str(body.get("nr_ordem") or body.get("NrOrdem") or "").strip()
#         detalhe = _to_int(body.get("detalhe") or body.get("Detalhe"), 0)
#         lote = str(body.get("lote") or body.get("Lote") or "").strip().upper()
#         operador = _to_int(body.get("operador") or body.get("Operador"), 0)
#         pedido_especial = bool(body.get("pedido_especial") or body.get("PedidoEspecial"))
#         qtde_imp = max(1, _to_int(body.get("qtde_imp") or body.get("QtdeImp"), 1))
#         lote_inline = bool(body.get("lote_inline") or body.get("LoteInline"))

#         # Validações básicas
#         if cd_obj <= 0:
#             return jsonify({"error": "Parâmetro obrigatório: cd_obj"}), 400
#         if not metros:
#             return jsonify({"error": "Parâmetro obrigatório: metros"}), 400
#         if not _only_digits(metros):
#             return jsonify({"error": "Parâmetro metros aceita apenas números."}), 400
#         if nr_ordem and not _only_digits(nr_ordem):
#             return jsonify({"error": "Parâmetro nr_ordem aceita apenas números."}), 400

#         connection = create_connection_tinturaria()
#         if connection is None:
#             return jsonify({"error": "Falha ao conectar ao banco."}), 500

#         cursor = connection.cursor()

#         # Busca dados do artigo + setor + metragem + Ean14
#         cursor.execute(
#             """
#             SELECT TOP 1
#                 Obj.CdObj,
#                 NmObj     = UPPER(Obj.NmObj),
#                 NmObj1    = UPPER(CASE
#                     WHEN CHARINDEX('MM', UPPER(Obj.NmObj)) > 0
#                     THEN LEFT(Obj.NmObj, CHARINDEX('MM', UPPER(Obj.NmObj)) + 1)
#                     ELSE Obj.NmObj END),
#                 NmObj2    = UPPER(CASE
#                     WHEN CHARINDEX('MM', UPPER(Obj.NmObj)) > 0
#                     THEN LTRIM(SUBSTRING(Obj.NmObj, CHARINDEX('MM', UPPER(Obj.NmObj)) + 2, LEN(Obj.NmObj)))
#                     ELSE '' END),
#                 Descricao = ISNULL(Obj.TtObj, ''),
#                 Setor     = ISNULL(Obj.CdObjLin, 0),
#                 Ean14     = ISNULL(CONVERT(varchar(50), CaoEan14.NrCao), ''),
#                 TipoCaixa = CASE
#                     WHEN Carretel.NmOpc = 'ENF'                   THEN 'ENFE'
#                     WHEN Carretel.NmOpc = 'ENFRALDADO'            THEN 'ENFR'
#                     WHEN Carretel.NmOpc IS NULL                   THEN ''
#                     WHEN TRY_CAST(Carretel.NmOpc AS int) <= 1200  THEN 'P'
#                     WHEN TRY_CAST(Carretel.NmOpc AS int) >  1200  THEN 'G'
#                     ELSE 'D' END,
#                 Metragem = CASE
#                     WHEN Carretel.NmOpc = 'ENF'        THEN 'ENF - Enfestado'
#                     WHEN Carretel.NmOpc = 'ENFRALDADO' THEN 'ENFRALDADO'
#                     WHEN Carretel.NmOpc IS NULL         THEN ''
#                     ELSE CONVERT(varchar(50), Carretel.NmOpc) + ' Mts' END,
#                 MetragemCurta = CASE
#                     WHEN Carretel.NmOpc = 'ENF'        THEN 'ENF'
#                     WHEN Carretel.NmOpc = 'ENFRALDADO' THEN 'ENFR'
#                     WHEN Carretel.NmOpc IS NULL         THEN ''
#                     ELSE CONVERT(varchar(50), Carretel.NmOpc) END
#             FROM dbo.TbObj Obj WITH (NOLOCK)
#             LEFT JOIN dbo.TbCao CaoEan14 WITH (NOLOCK)
#                    ON CaoEan14.CdObj = Obj.CdObj AND CaoEan14.CdTca = 4
#             LEFT JOIN (
#                 SELECT Opo.CdObj, NmOpc = Opc.NmOpc
#                 FROM dbo.TbOpo Opo WITH (NOLOCK)
#                 JOIN dbo.TbCrc Crc WITH (NOLOCK) ON Crc.CdCrc = Opo.CdCrc
#                 JOIN dbo.TbCgr Cgr WITH (NOLOCK)
#                   ON Cgr.CdCgr = Opo.CdCgr AND Cgr.CdCrc = Crc.CdCrc AND Crc.CdCrc = 96
#                 LEFT JOIN dbo.TbOpc Opc WITH (NOLOCK) ON Opc.CdOpc = Opo.CdOpc
#                 WHERE EXISTS (
#                     SELECT 1 FROM dbo.TbArvObj ArvObj WITH (NOLOCK)
#                     WHERE ArvObj.CdObjFil = Opo.CdObj AND ArvObj.CdObj = ?
#                 )
#             ) Carretel ON Carretel.CdObj = Obj.CdObj
#             WHERE EXISTS (
#                 SELECT 1 FROM dbo.TbArvObj ArvObj WITH (NOLOCK)
#                 WHERE ArvObj.CdObjFil = Obj.CdObj AND ArvObj.CdObj = ?
#             )
#             ORDER BY Obj.CdObj
#             """,
#             (cd_obj, cd_obj),
#         )
#         row = _row_dict(cursor, cursor.fetchone())
#         if not row:
#             return jsonify({"error": "Artigo não encontrado."}), 404

#         nm_obj = str(row.get("NmObj") or "").strip().upper()
#         nm_obj1 = str(row.get("NmObj1") or "").strip()
#         nm_obj2 = str(row.get("NmObj2") or "").strip()
#         descricao = str(row.get("Descricao") or "").strip()
#         setor = int(row.get("Setor") or 0)
#         tipo_caixa = str(row.get("TipoCaixa") or "").strip().upper()
#         metragem = str(row.get("Metragem") or "").strip()
#         metragem_curta = str(row.get("MetragemCurta") or "").strip()
#         ean14 = str(row.get("Ean14") or "").strip()

#         # P/G determinado pelos metros enviados na requisição, não pela config do BD.
#         # As faixas (caixa_p/caixa_g) são as cadastradas para o artigo em
#         # Stik_PadraoCaixa; sem cadastro, cai no limiar genérico de 1200m.
#         # Quando há cadastro, só marca P/G se os metros baterem EXATAMENTE
#         # com a caixa cheia — qualquer outro valor é saldo (S). Se os metros
#         # passarem de uma caixa cheia (equivalem a caixa fechada + saldo),
#         # NÃO divide automaticamente: bloqueia e orienta o usuário a
#         # imprimir a caixa fechada primeiro, depois o saldo separadamente.
#         if tipo_caixa in ("P", "G"):
#             metros_int = _to_int(metros, 0)
#             padrao = _buscar_padrao_caixa(cursor, nm_obj)
#             caixa_p = _to_int(padrao.get("caixa_p"), 0)
#             caixa_g = _to_int(padrao.get("caixa_g"), 0)
#             if caixa_p > 0 or caixa_g > 0:
#                 if caixa_p > 0 and metros_int == caixa_p:
#                     tipo_caixa = "P"
#                 elif caixa_g > 0 and metros_int == caixa_g:
#                     tipo_caixa = "G"
#                 elif caixa_g > 0 and metros_int > caixa_g:
#                     saldo = metros_int - caixa_g
#                     return jsonify({
#                         "error": (
#                             f"{metros_int}m equivale a 1 caixa G ({caixa_g}m) + {saldo}m de saldo. "
#                             f"Imprima a caixa G primeiro (informe {caixa_g}), depois imprima o "
#                             f"saldo separadamente (informe {saldo})."
#                         )
#                     }), 400
#                 elif caixa_p > 0 and metros_int > caixa_p:
#                     saldo = metros_int - caixa_p
#                     return jsonify({
#                         "error": (
#                             f"{metros_int}m equivale a 1 caixa P ({caixa_p}m) + {saldo}m de saldo. "
#                             f"Imprima a caixa P primeiro (informe {caixa_p}), depois imprima o "
#                             f"saldo separadamente (informe {saldo})."
#                         )
#                     }), 400
#                 else:
#                     tipo_caixa = "S"
#             else:
#                 tipo_caixa = "P" if metros_int <= 1200 else "G"

#         # Valida TipoCaixa
#         if tipo_caixa == "CAIXA M":
#             return jsonify({"error": "Tipo de caixa inválido: CAIXA M. Preencha com P, G, ENFE, ENFR ou D."}), 400
#         if tipo_caixa not in ("P", "G", "ENFE", "ENFR", "D", "S"):
#             return jsonify({"error": f"Tipo de caixa inválido: '{tipo_caixa}'. Use: P, G, S, ENFE, ENFR ou D."}), 400

#         # Detecta flags
#         tem_preto = "PRETO" in nm_obj
#         eh_preto_especial = tem_preto and any(x in nm_obj for x in [
#             "PRETO FX", "PRETO LSB", "PRETO LP", "PRETO MP 3", "PRETO FD",
#         ])
#         nao_imprime_lote_linha = "ENFRALDADO" in nm_obj or "ENFESTADO" in nm_obj
#         detalhe_obrigatorio = cd_obj in _CDOBJ_DETALHE_OBRIGATORIO or setor == 10180
#         imprime_detalhe_ao_lado = cd_obj in _CDOBJ_DETALHE_OBRIGATORIO
#         imprime_lote_abaixo_metros = cd_obj in _CDOBJ_DETALHE_OBRIGATORIO

#         detalhe_vazio = detalhe <= 0

#         # Validações de negócio
#         if detalhe_obrigatorio and detalhe_vazio:
#             sufixo = f"Setor 10180" if setor == 10180 else f"CdObj {cd_obj}"
#             return jsonify({"error": f"{sufixo}: é obrigatório preencher o DETALHE."}), 400

#         if tem_preto:
#             faltando = []
#             if detalhe_vazio:
#                 faltando.append("DETALHE")
#             if not lote:
#                 faltando.append("LOTE")
#             if faltando:
#                 return jsonify({"error": f"Artigo PRETO: é obrigatório preencher {' e '.join(faltando)}."}), 400

#         # Auto-resolve do Detalhe quando não informado
#         detalhe_id = detalhe
#         nm_detalhe = ""

#         if detalhe_id <= 0:
#             if tem_preto and eh_preto_especial and cd_obj in _CDOBJ_PRETO_AUTO_LOT:
#                 cursor.execute(
#                     "SELECT CdLot = MAX(CdLot) FROM TbLot WHERE CdObj = ?",
#                     (cd_obj,),
#                 )
#                 r = cursor.fetchone()
#                 if r and r[0]:
#                     detalhe_id = int(r[0])
#             elif not tem_preto:
#                 cursor.execute(
#                     "SELECT TOP 1 CdLot FROM TbLot WHERE CdObj = ? ORDER BY CdLot DESC",
#                     (cd_obj,),
#                 )
#                 r = cursor.fetchone()
#                 if r and r[0]:
#                     detalhe_id = int(r[0])

#         # Lookup NmLot do detalhe resolvido
#         if detalhe_id > 0:
#             cursor.execute(
#                 "SELECT NmLot FROM TbLot WHERE CdLot = ?",
#                 (detalhe_id,),
#             )
#             r = cursor.fetchone()
#             if r and r[0]:
#                 nm_detalhe = str(r[0]).strip().upper()

#         # Valida e resolve operador
#         operador_qr = "0"
#         if operador > 0:
#             cursor.execute(
#                 """
#                 SELECT TOP 1 CodigoQR
#                 FROM Stik_WMS_OperadorQRCode
#                 WHERE CodigoOperador = ?
#                 """,
#                 (operador,),
#             )
#             r = cursor.fetchone()
#             if r and r[0]:
#                 operador_qr = str(r[0]).strip()
#             else:
#                 return jsonify({
#                     "error": f"Operador {operador} não encontrado na tabela Stik_WMS_OperadorQRCode.",
#                 }), 400

#         # Datas
#         hoje = date.today()
#         data_fabricacao = f"{str(hoje.day).zfill(2)}/{str(hoje.month).zfill(2)}/{hoje.year}"
#         data_codificada = _calcular_data_codificada(hoje.day, hoje.month, hoje.year)

#         # Lote redundante (PRETO onde LOTE == NmObj → não imprime linha de lote)
#         nao_imprime_lote_redundante = (
#             tem_preto and bool(lote) and lote == nm_obj
#         )
#         nao_imprime_lote_final = nao_imprime_lote_linha or nao_imprime_lote_redundante

#         # ── Monta as linhas do layout (equivale às posições ZPL) ──

#         # Linha 230
#         if setor == 10180:
#             linha230 = f"COR: {nm_detalhe}" if nm_detalhe else f"COR: {detalhe_id if detalhe_id > 0 else ''}"
#         else:
#             linha230 = f"{metros} Metros"
#             if imprime_detalhe_ao_lado and nm_detalhe:
#                 linha230 += f" {nm_detalhe}"
#             if pedido_especial:
#                 linha230 += " PDE"
#             if lote_inline and lote:
#                 linha230 += f" {lote}"

#         # Linha 260
#         linha260 = ""
#         if setor == 10180:
#             linha260 = f"{metros} Metros"
#             if pedido_especial:
#                 linha260 += " PDE"
#             if imprime_detalhe_ao_lado and nm_detalhe:
#                 linha260 += f" {nm_detalhe}"
#             if lote_inline and lote:
#                 linha260 += f" {lote}"
#         elif lote_inline:
#             linha260 = ""  # já foi inline na linha 230
#         elif imprime_lote_abaixo_metros:
#             linha260 = lote if lote else ""
#         elif nao_imprime_lote_final:
#             linha260 = ""
#         else:
#             if lote:
#                 linha260 = f"LOTE: {lote}"
#                 if pedido_especial:
#                     linha260 += " PDE"
#             else:
#                 linha260 = ""

#         # Linha 300
#         if setor == 10180:
#             linha300 = "" if (nao_imprime_lote_final or lote_inline) else (lote or "")
#         else:
#             linha300 = f"CARR. {metragem_curta}" if metragem_curta else ""

#         # Tipo de caixa no QR — mapeado para código curto
#         # ENFE (banco) → ENF no QR | ENFR, P, G, D permanecem iguais
#         _tipo_caixa_qr_map = {"ENFE": "ENF", "ENFR": "ENFR", "P": "P", "G": "G", "D": "D", "S": "S"}
#         tipo_caixa_qr = _tipo_caixa_qr_map.get(tipo_caixa, tipo_caixa)

#         # Data de fabricação como inteiro YYYYMMDD (ex.: 20260527)
#         data_int = hoje.year * 10000 + hoje.month * 100 + hoje.day

#         # Ordem como inteiro
#         nr_ordem_int = _to_int(nr_ordem, 0)

#         # QR Code — formato compacto com chaves de 1 letra
#         # CdObj  = código do artigo
#         # Detalhe = CdLot (cor/lote)
#         # D      = data fabricação YYYYMMDD
#         # C      = tipo caixa (P | G | ENF | ENFR | D)
#         # O      = número da ordem de produção
#         # CX     = código único de rastreio da caixa (gerado no momento da impressão)
#         qr_dict = {
#             "CdObj": cd_obj,
#             "Detalhe": detalhe_id,
#             "D": data_int,
#             "C": tipo_caixa_qr,
#             "O": nr_ordem_int,
#             "CX": _gerar_cx(),
#         }

#         if operador_qr != "0":
#             qr_dict["operador"] = operador_qr

#         qr_code = json.dumps(qr_dict, ensure_ascii=False, separators=(",", ":"))

#         result = {
#             "CdObj": cd_obj,
#             "DetalheId": detalhe_id,
#             "NmObj": nm_obj,
#             "NmObj1": nm_obj1,
#             "NmObj2": nm_obj2,
#             "NmDetalhe": nm_detalhe,
#             "Descricao": descricao,
#             "TipoCaixa": tipo_caixa,
#             "Ean14": ean14,
#             "Metragem": metragem,
#             "DataFabricacao": data_fabricacao,
#             "Metros": metros,
#             "NrOrdem": nr_ordem,
#             "Lote": lote,
#             "Operador": operador,
#             "OperadorQr": operador_qr,
#             "PedidoEspecial": pedido_especial,
#             "QtdeImp": qtde_imp,
#             "LoteInline": lote_inline,
#             # Flags
#             "Setor": setor,
#             "Setor10180": setor == 10180,
#             "TemPreto": tem_preto,
#             "EhPretoEspecial": eh_preto_especial,
#             "NaoImprimeLoteLinha": nao_imprime_lote_final,
#             "DetalheObrigatorio": detalhe_obrigatorio,
#             # Linhas de layout pré-computadas
#             "Linha230": linha230,
#             "Linha260": linha260,
#             "Linha300": linha300,
#             "LinhaData": f"DATA DE FABRICACAO: {data_fabricacao}",
#             # QR Code — formato novo
#             "QrCode": qr_code,
#         }

#         return jsonify({"success": True, "data": result}), 200

#     except Exception as e:
#         return jsonify({"error": str(e)}), 500

#     finally:
#         if connection:
#             connection.close()


# # ===================================================================
# # ROTA: ETIQUETA DE CARRETEL (POST)
# # Aba nova de impressão (EPL2), distinta da etiqueta de Caixa (ZPL).
# # Busca NmObj/Descricao/Ean13/Metragem do artigo (Metragem vem do mesmo
# # grupo de característica 96 "Carretel" já usado nas etiquetas de caixa,
# # não é digitada); Lote/Operador/QtdeImp vêm da tela e só são ecoados.
# # ===================================================================
# @WMS_Etiquetas_QrCode_bp.route("/consulta/wms/etiqueta-carretel", methods=["POST"])
# def WMS_Etiquetas_QrCode_etiqueta_carretel():
#     connection = None
#     try:
#         data = request.get_json() or {}

#         cd_obj = _to_int(data.get("cd_obj") or data.get("CdObj"))
#         lote = str(data.get("lote") or data.get("Lote") or "").strip().upper()
#         operador = str(data.get("operador") or data.get("Operador") or "").strip()
#         qtde_imp = max(1, _to_int(data.get("qtde_imp") or data.get("QtdeImp"), 1))

#         if cd_obj <= 0:
#             return jsonify({"error": "Parâmetro obrigatório: cd_obj"}), 400

#         connection = create_connection_tinturaria()
#         if connection is None:
#             return jsonify({"error": "Falha ao conectar ao banco."}), 500

#         cursor = connection.cursor()
#         cursor.execute(
#             """
#             SELECT TOP 1
#                 Obj.CdObj,
#                 NmObj = UPPER(Obj.NmObj),
#                 Descricao = ISNULL(Obj.TtObj, ''),
#                 Ean13 = ISNULL(dbo.UFN_GeraCodigoEAN(CaoEan13.NrCao), ''),
#                 Metragem = CASE
#                     WHEN Carretel.NmOpc = 'ENF'        THEN 'ENF - Enfestado'
#                     WHEN Carretel.NmOpc = 'ENFRALDADO' THEN 'ENFRALDADO'
#                     WHEN Carretel.NmOpc IS NULL        THEN ''
#                     ELSE CONVERT(varchar(50), Carretel.NmOpc) + ' Mts'
#                 END
#             FROM dbo.TbObj Obj WITH (NOLOCK)
#             LEFT JOIN dbo.TbCao CaoEan13 WITH (NOLOCK)
#                    ON CaoEan13.CdObj = Obj.CdObj
#                   AND CaoEan13.CdTca = 2
#             LEFT JOIN (
#                 SELECT Opo.CdObj, NmOpc = Opc.NmOpc
#                 FROM dbo.TbOpo Opo WITH (NOLOCK)
#                 JOIN dbo.TbCrc Crc WITH (NOLOCK) ON Crc.CdCrc = Opo.CdCrc
#                 JOIN dbo.TbCgr Cgr WITH (NOLOCK)
#                   ON Cgr.CdCgr = Opo.CdCgr AND Cgr.CdCrc = Crc.CdCrc AND Crc.CdCrc = 96
#                 LEFT JOIN dbo.TbOpc Opc WITH (NOLOCK) ON Opc.CdOpc = Opo.CdOpc
#                 WHERE EXISTS (
#                     SELECT 1 FROM dbo.TbArvObj ArvObj WITH (NOLOCK)
#                     WHERE ArvObj.CdObjFil = Opo.CdObj AND ArvObj.CdObj = ?
#                 )
#             ) Carretel ON Carretel.CdObj = Obj.CdObj
#             WHERE Obj.CdObj = ?
#             """,
#             (cd_obj, cd_obj),
#         )
#         row = _row_dict(cursor, cursor.fetchone())
#         if not row:
#             return jsonify({"error": f"Artigo {cd_obj} não encontrado."}), 404

#         hoje = date.today()
#         data_codificada = _calcular_mes_ano_codificado(hoje.month, hoje.year)

#         result = {
#             "CdObj": cd_obj,
#             "NmObj": str(row.get("NmObj") or "").strip(),
#             "Descricao": str(row.get("Descricao") or "").strip(),
#             "Ean13": str(row.get("Ean13") or "").strip(),
#             "Metragem": str(row.get("Metragem") or "").strip(),
#             "Lote": lote,
#             "Operador": operador,
#             "QtdeImp": qtde_imp,
#             "DataCodificada": data_codificada,
#         }
#         return jsonify({"success": True, "data": result}), 200

#     except Exception as e:
#         return jsonify({"error": str(e)}), 500

#     finally:
#         if connection:
#             connection.close()


# @WMS_Etiquetas_QrCode_bp.route("/consulta/wms/artigos-busca", methods=["GET"])
# def WMS_Etiquetas_QrCode_artigos_busca():
#     """Autocomplete de artigos por nome ou código (mínimo 2 caracteres)."""
#     q = (request.args.get("q") or "").strip()
#     if len(q) < 2:
#         return jsonify({"data": []}), 200

#     connection = None
#     try:
#         connection = create_connection_tinturaria()
#         if connection is None:
#             return jsonify({"error": "Falha ao conectar ao banco."}), 500

#         cursor = connection.cursor()
#         cursor.execute(
#             """
#             SELECT TOP 30
#                 CdObj = Obj.CdObj,
#                 NmObj = RTRIM(ISNULL(CONVERT(varchar(50), CaoDefault.NrCao) + '   ', '') + Obj.NmObj)
#             FROM dbo.TbObj Obj WITH (NOLOCK)
#             JOIN dbo.TbArvObj ArvObj WITH (NOLOCK)
#                 ON ArvObj.CdObjFil = Obj.CdObj
#                AND ArvObj.CdObj = 1
#             LEFT JOIN (
#                 SELECT Cao.CdObj, Cao.NrCao
#                 FROM dbo.TbCao Cao WITH (NOLOCK)
#                 JOIN dbo.TbTca Tca WITH (NOLOCK)
#                   ON Tca.CdTca = Cao.CdTca
#                  AND Tca.FlTcaDef = 1
#             ) CaoDefault ON CaoDefault.CdObj = Obj.CdObj
#             WHERE (
#                     UPPER(Obj.NmObj) LIKE '%' + UPPER(?) + '%'
#                  OR CONVERT(varchar, Obj.CdObj) LIKE ? + '%'
#             )
#             ORDER BY Obj.NrObjOrd001, Obj.NrObjOrd002, Obj.NrObjOrd003
#             """,
#             (q, q),
#         )
#         rows = cursor.fetchall()
#         data = [
#             {"CdObj": row[0], "NmObj": str(row[1] or "").strip()}
#             for row in rows
#         ]
#         return jsonify({"data": data}), 200

#     except Exception as e:
#         return jsonify({"error": str(e)}), 500
#     finally:
#         if connection:
#             connection.close()


# _IMPRESSORAS = [
#     {"nome": "ZebraZD220", "ip": "168.190.30.223", "porta": 9100},
#     {"nome":"ZebraZD220", "ip": '168.190.30.172', "porta": 9100},
#     {"nome":"ZebraZD220", "ip": '168.190.30.181', "porta": 9100},
#     {"nome":"ZebraZD220", "ip": '168.190.30.206', "porta": 9100},
#     {"nome":"ZebraZD220", "ip": '168.190.30.201', "porta": 9100},
# ]


# @WMS_Etiquetas_QrCode_bp.route("/consulta/wms/impressoras", methods=["GET"])
# def WMS_Etiquetas_QrCode_impressoras():
#     """Retorna a lista de impressoras Zebra configuradas."""
#     return jsonify({"data": _IMPRESSORAS}), 200


# @WMS_Etiquetas_QrCode_bp.route("/consulta/wms/artigo-lotes", methods=["GET"])
# def WMS_Etiquetas_QrCode_artigo_lotes():
#     """Retorna os lotes (detalhe) de um artigo para seleção em dropdown."""
#     cd_obj = _to_int(
#         request.args.get("cd_obj") or request.args.get("CdObj")
#     )
#     if cd_obj <= 0:
#         return jsonify({"error": "Parâmetro obrigatório: cd_obj"}), 400

#     connection = None
#     try:
#         connection = create_connection_tinturaria()
#         if connection is None:
#             return jsonify({"error": "Falha ao conectar ao banco."}), 500

#         cursor = connection.cursor()
#         cursor.execute(
#             """
#             SELECT Lot.CdLot, Lot.NmLot
#               FROM dbo.TbLot Lot WITH (NOLOCK)
#              WHERE Lot.CdObj = ?
#              ORDER BY Lot.CdLot DESC
#             """,
#             (cd_obj,),
#         )
#         rows = cursor.fetchall()
#         data = [
#             {"CdLot": row[0], "NmLot": str(row[1] or "").strip()}
#             for row in rows
#         ]
#         return jsonify({"data": data}), 200

#     except Exception as e:
#         return jsonify({"error": str(e)}), 500
#     finally:
#         if connection:
#             connection.close()

import json
import re
import time
from datetime import date

from flask import Blueprint, jsonify, request

from database.server import create_connection_tinturaria

WMS_Etiquetas_QrCode_bp = Blueprint("WMS_Etiquetas_QrCode", __name__)

_MESES_LETRA = ['A', 'B', 'C', 'D', 'E', 'F', 'G', 'H', 'I', 'J', 'K', 'L']

# CdObjs que exigem DETALHE obrigatório e imprimem detalhe/lote especial
_CDOBJ_DETALHE_OBRIGATORIO = {20287, 52218, 21532, 94439, 92377, 97874, 99516, 100771}

# CdObjs PRETO especial que fazem auto-resolve do detalhe pelo Max(CdLot)
_CDOBJ_PRETO_AUTO_LOT = {92149, 86237, 84992, 31025, 98471, 21532, 94439, 92377, 97874, 100771, 81849}


_B36 = "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ"

def _gerar_cx() -> str:
    """Gera código único de rastreio da caixa: timestamp ms em base-36 (ex.: KNUP0G4)."""
    val = int(time.time() * 1000)
    digits = []
    while val:
        digits.append(_B36[val % 36])
        val //= 36
    return "".join(reversed(digits))


def _gerar_li() -> str:
    """Gera código único de lote de impressão (LI): agrupa N caixas impressas
    na mesma leva para permitir, na Entrada, 1 única leitura recuperar todas
    as CX do lote em vez de escanear caixa por caixa. Mesmo algoritmo do CX
    (timestamp em base-36), porém em coluna própria — nunca é comparado ao CX."""
    return _gerar_cx()


def _to_int(value, default=0):
    try:
        if value in (None, ""):
            return default
        return int(value)
    except Exception:
        return default


def _row_dict(cursor, row):
    if not row:
        return None
    columns = [col[0] for col in cursor.description]
    return {columns[i]: row[i] for i in range(len(columns))}


def _only_digits(value):
    return (value or "").strip().isdigit()


def _calcular_data_codificada(dia, mes, ano):
    return f"{str(dia).zfill(2)}{_MESES_LETRA[mes - 1]}{str(ano)[-1]}"


def _calcular_mes_ano_codificado(mes, ano):
    return f"{_MESES_LETRA[mes - 1]}{str(ano)[-1]}"


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
        return {}

    cursor.execute(
        """
        SELECT TOP 1
            caixa_p = ISNULL(caixa_p, 0),
            caixa_g = ISNULL(caixa_g, 0)
        FROM dbo.Stik_PadraoCaixa WITH (NOLOCK)
        WHERE UPPER(LTRIM(RTRIM(artigo))) = UPPER(LTRIM(RTRIM(?)))
        """,
        (artigo_mae,),
    )
    return _row_dict(cursor, cursor.fetchone()) or {}


@WMS_Etiquetas_QrCode_bp.route("/consulta/wms/artigo-info", methods=["GET"])
def WMS_Etiquetas_QrCode_artigo_info():
    """Retorna metadados do artigo para a etapa de busca (sem metros/ordem)."""
    connection = None
    try:
        cd_obj = _to_int(
            request.args.get("cd_obj")
            or request.args.get("CdObj")
            or request.args.get("cd")
        )
        if cd_obj <= 0:
            return jsonify({"error": "Parâmetro obrigatório: cd_obj"}), 400

        connection = create_connection_tinturaria()
        if connection is None:
            return jsonify({"error": "Falha ao conectar ao banco."}), 500

        cursor = connection.cursor()
        cursor.execute(
            """
            SELECT TOP 1
                Obj.CdObj,
                NmObj  = UPPER(Obj.NmObj),
                NmObj1 = UPPER(CASE
                    WHEN CHARINDEX('MM', UPPER(Obj.NmObj)) > 0
                    THEN LEFT(Obj.NmObj, CHARINDEX('MM', UPPER(Obj.NmObj)) + 1)
                    ELSE Obj.NmObj END),
                NmObj2 = UPPER(CASE
                    WHEN CHARINDEX('MM', UPPER(Obj.NmObj)) > 0
                    THEN LTRIM(SUBSTRING(Obj.NmObj, CHARINDEX('MM', UPPER(Obj.NmObj)) + 2, LEN(Obj.NmObj)))
                    ELSE '' END),
                Descricao = ISNULL(Obj.TtObj, ''),
                Setor     = ISNULL(Obj.CdObjLin, 0),
                TipoCaixa = CASE
                    WHEN Carretel.NmOpc = 'ENF'                   THEN 'ENFE'
                    WHEN Carretel.NmOpc = 'ENFRALDADO'            THEN 'ENFR'
                    WHEN Carretel.NmOpc IS NULL                   THEN ''
                    WHEN TRY_CAST(Carretel.NmOpc AS int) <= 1200  THEN 'P'
                    WHEN TRY_CAST(Carretel.NmOpc AS int) >  1200  THEN 'G'
                    ELSE 'D' END,
                Metragem = CASE
                    WHEN Carretel.NmOpc = 'ENF'        THEN 'ENF - Enfestado'
                    WHEN Carretel.NmOpc = 'ENFRALDADO' THEN 'ENFRALDADO'
                    WHEN Carretel.NmOpc IS NULL         THEN ''
                    ELSE CONVERT(varchar(50), Carretel.NmOpc) + ' Mts' END
            FROM dbo.TbObj Obj WITH (NOLOCK)
            LEFT JOIN (
                SELECT Opo.CdObj, NmOpc = Opc.NmOpc
                FROM dbo.TbOpo Opo WITH (NOLOCK)
                JOIN dbo.TbCrc Crc WITH (NOLOCK) ON Crc.CdCrc = Opo.CdCrc
                JOIN dbo.TbCgr Cgr WITH (NOLOCK)
                  ON Cgr.CdCgr = Opo.CdCgr AND Cgr.CdCrc = Crc.CdCrc AND Crc.CdCrc = 96
                LEFT JOIN dbo.TbOpc Opc WITH (NOLOCK) ON Opc.CdOpc = Opo.CdOpc
                WHERE EXISTS (
                    SELECT 1 FROM dbo.TbArvObj ArvObj WITH (NOLOCK)
                    WHERE ArvObj.CdObjFil = Opo.CdObj AND ArvObj.CdObj = ?
                )
            ) Carretel ON Carretel.CdObj = Obj.CdObj
            WHERE EXISTS (
                SELECT 1 FROM dbo.TbArvObj ArvObj WITH (NOLOCK)
                WHERE ArvObj.CdObjFil = Obj.CdObj AND ArvObj.CdObj = ?
            )
            ORDER BY Obj.CdObj
            """,
            (cd_obj, cd_obj),
        )
        row = _row_dict(cursor, cursor.fetchone())
        if not row:
            return jsonify({"error": f"Artigo {cd_obj} não encontrado."}), 404

        nm_obj = str(row.get("NmObj") or "").strip().upper()
        setor = int(row.get("Setor") or 0)
        tem_preto = "PRETO" in nm_obj
        nao_imprime_lote_linha = "ENFRALDADO" in nm_obj or "ENFESTADO" in nm_obj
        detalhe_obrigatorio = cd_obj in _CDOBJ_DETALHE_OBRIGATORIO or setor == 10180

        result = {
            "CdObj": cd_obj,
            "NmObj": nm_obj,
            "NmObj1": str(row.get("NmObj1") or "").strip(),
            "NmObj2": str(row.get("NmObj2") or "").strip(),
            "Descricao": str(row.get("Descricao") or "").strip(),
            "TipoCaixa": str(row.get("TipoCaixa") or "").strip().upper(),
            "Metragem": str(row.get("Metragem") or "").strip(),
            "Setor": setor,
            "Setor10180": setor == 10180,
            "TemPreto": tem_preto,
            "NaoImprimeLoteLinha": nao_imprime_lote_linha,
            "DetalheObrigatorio": detalhe_obrigatorio,
        }
        return jsonify({"success": True, "data": result}), 200

    except Exception as e:
        return jsonify({"error": str(e)}), 500
    finally:
        if connection:
            connection.close()


@WMS_Etiquetas_QrCode_bp.route("/consulta/wms/etiqueta-caixa", methods=["GET"])
def WMS_Etiquetas_QrCode_etiqueta_caixa():
    connection = None
    try:
        cd_obj = _to_int(
            request.args.get("cd_obj")
            or request.args.get("CdObj")
            or request.args.get("cd")
        )
        detalhe = _to_int(
            request.args.get("detalhe")
            or request.args.get("Detalhe")
            or request.args.get("cd_lot"),
            0,
        )
        metros = (request.args.get("metros") or request.args.get("Metros") or "").strip()
        nr_ordem = (
            request.args.get("nr_ordem")
            or request.args.get("NrOrdem")
            or request.args.get("nro_ordem")
            or request.args.get("ordem")
            or ""
        ).strip()

        if cd_obj <= 0:
            return jsonify({"error": "Parâmetro obrigatório: cd_obj"}), 400
        if not metros:
            return jsonify({"error": "Parâmetro obrigatório: metros"}), 400
        if not _only_digits(metros):
            return jsonify({"error": "Parâmetro metros aceita apenas números."}), 400
        if nr_ordem and not _only_digits(nr_ordem):
            return jsonify({"error": "Parâmetro nr_ordem aceita apenas números."}), 400

        connection = create_connection_tinturaria()
        if connection is None:
            return jsonify({"status": "SQL_ERROR", "details": "Falha ao conectar ao banco."}), 500

        cursor = connection.cursor()
        cursor.execute(
            """
            SELECT TOP 1
                Obj.CdObj,
                DetalheId = ISNULL(Lot.CdLot, 0),
                NmObj = UPPER(Obj.NmObj),
                NmObj1 = UPPER(
                    CASE
                        WHEN CHARINDEX('MM', UPPER(Obj.NmObj)) > 0
                        THEN LEFT(Obj.NmObj, CHARINDEX('MM', UPPER(Obj.NmObj)) + 1)
                        ELSE Obj.NmObj
                    END
                ),
                NmObj2 = UPPER(
                    CASE
                        WHEN CHARINDEX('MM', UPPER(Obj.NmObj)) > 0
                        THEN LTRIM(SUBSTRING(Obj.NmObj, CHARINDEX('MM', UPPER(Obj.NmObj)) + 2, LEN(Obj.NmObj)))
                        ELSE ''
                    END
                ),
                Detalhe = ISNULL(Lot.NmLot, ''),
                Descricao = ISNULL(Obj.TtObj, ''),
                Ean13 = ISNULL(dbo.UFN_GeraCodigoEAN(CaoEan13.NrCao), ''),
                Ean14 = ISNULL(CONVERT(varchar(50), CaoEan14.NrCao), ''),
                Metros = '',
                Lote = '',
                Operador = '',
                NrOrdem = '',
                TipoCaixa = CASE
                    WHEN Carretel.NmOpc = 'ENF'                   THEN 'ENFE'
                    WHEN Carretel.NmOpc = 'ENFRALDADO'            THEN 'ENFR'
                    WHEN Carretel.NmOpc IS NULL                   THEN ''
                    WHEN TRY_CAST(Carretel.NmOpc AS int) <= 1200  THEN 'P'
                    WHEN TRY_CAST(Carretel.NmOpc AS int) >  1200  THEN 'G'
                    ELSE 'D'
                END,
                DataFabricacao = CONVERT(varchar(10), GETDATE(), 103),
                Metragem = CASE
                    WHEN Carretel.NmOpc = 'ENF' THEN 'ENF - Enfestado'
                    WHEN Carretel.NmOpc = 'ENFRALDADO' THEN 'ENFRALDADO'
                    WHEN Carretel.NmOpc IS NULL THEN ''
                    ELSE CONVERT(varchar(50), Carretel.NmOpc) + ' Mts'
                END,
                Mae = Obj.CdObjMae
            FROM dbo.TbObj Obj WITH (NOLOCK)
            LEFT JOIN dbo.TbLot Lot WITH (NOLOCK)
                   ON Lot.CdObj = Obj.CdObj
                  AND Lot.CdLot = ?
            LEFT JOIN dbo.TbCao CaoEan13 WITH (NOLOCK)
                   ON CaoEan13.CdObj = Obj.CdObj
                  AND CaoEan13.CdTca = 2
            LEFT JOIN dbo.TbCao CaoEan14 WITH (NOLOCK)
                   ON CaoEan14.CdObj = Obj.CdObj
                  AND CaoEan14.CdTca = 4
            LEFT JOIN (
                SELECT
                    Opo.CdObj,
                    Opo.CdCrc,
                    NmOpc = Opc.NmOpc
                FROM dbo.TbOpo Opo WITH (NOLOCK)
                JOIN dbo.TbCrc Crc WITH (NOLOCK)
                  ON Crc.CdCrc = Opo.CdCrc
                JOIN dbo.TbCgr Cgr WITH (NOLOCK)
                  ON Cgr.CdCgr = Opo.CdCgr
                 AND Cgr.CdCrc = Crc.CdCrc
                 AND Crc.CdCrc = 96
                LEFT JOIN dbo.TbOpc Opc WITH (NOLOCK)
                  ON Opc.CdOpc = Opo.CdOpc
                WHERE EXISTS (
                    SELECT 1
                    FROM dbo.TbArvObj ArvObj WITH (NOLOCK)
                    WHERE ArvObj.CdObjFil = Opo.CdObj
                      AND ArvObj.CdObj = ?
                )
            ) Carretel
              ON Carretel.CdObj = Obj.CdObj
            WHERE EXISTS (
                SELECT 1
                FROM dbo.TbArvObj ArvObj WITH (NOLOCK)
                WHERE ArvObj.CdObjFil = Obj.CdObj
                  AND ArvObj.CdObj = ?
            )
            ORDER BY Obj.CdObj
            """,
            (detalhe, cd_obj, cd_obj),
        )
        data = _row_dict(cursor, cursor.fetchone())
        if not data:
            return jsonify({"error": "Dados da etiqueta caixa não encontrados."}), 404

        tipo_caixa = str(data.get("TipoCaixa") or "").strip().upper()
        if tipo_caixa not in ("P", "G", "ENFE", "ENFR", "D"):
            return jsonify({
                "error": "Tipo de caixa inválido ou não localizado pela API.",
                "tipo_caixa": tipo_caixa,
                "permitidos": ["P", "G", "ENFE", "ENFR", "D"],
            }), 400

        data["Metros"] = metros
        data["NrOrdem"] = nr_ordem
        data["QrCode"] = json.dumps({
            "CdObj": data.get("CdObj") or 0,
            "Detalhe": data.get("DetalheId") or 0,
            "TipoCaixa": tipo_caixa,
            "Fabricacao": data.get("DataFabricacao") or "",
            "NrOrdem": nr_ordem,
        }, ensure_ascii=False, separators=(",", ":"))
        data["TipoCaixa"] = tipo_caixa

        return jsonify({"success": True, "data": data}), 200

    except Exception as e:
        return jsonify({"error": str(e)}), 500

    finally:
        if connection:
            connection.close()


@WMS_Etiquetas_QrCode_bp.route("/consulta/wms/etiqueta-caixa-v2", methods=["POST"])
def WMS_Etiquetas_QrCode_etiqueta_caixa_v2():
    connection = None
    try:
        body = request.get_json(silent=True) or {}

        cd_obj = _to_int(body.get("cd_obj") or body.get("CdObj"))
        metros = str(body.get("metros") or body.get("Metros") or "").strip()
        nr_ordem = str(body.get("nr_ordem") or body.get("NrOrdem") or "").strip()
        detalhe = _to_int(body.get("detalhe") or body.get("Detalhe"), 0)
        lote = str(body.get("lote") or body.get("Lote") or "").strip().upper()
        operador = _to_int(body.get("operador") or body.get("Operador"), 0)
        pedido_especial = bool(body.get("pedido_especial") or body.get("PedidoEspecial"))
        qtde_imp = max(1, _to_int(body.get("qtde_imp") or body.get("QtdeImp"), 1))
        lote_inline = bool(body.get("lote_inline") or body.get("LoteInline"))
        # LI (lote de impressão): opcional. Se o cliente enviar o LI já
        # gerado na 1ª caixa de um lote, as próximas chamadas reaproveitam o
        # mesmo valor, agrupando todas as caixas impressas juntas. Se vier
        # vazio, gera um novo — retrocompatível com clientes que não enviam.
        li = str(body.get("li") or body.get("LI") or "").strip() or None
        if not li:
            li = _gerar_li()

        # Validações básicas
        if cd_obj <= 0:
            return jsonify({"error": "Parâmetro obrigatório: cd_obj"}), 400
        if not metros:
            return jsonify({"error": "Parâmetro obrigatório: metros"}), 400
        if not _only_digits(metros):
            return jsonify({"error": "Parâmetro metros aceita apenas números."}), 400
        if nr_ordem and not _only_digits(nr_ordem):
            return jsonify({"error": "Parâmetro nr_ordem aceita apenas números."}), 400

        connection = create_connection_tinturaria()
        if connection is None:
            return jsonify({"error": "Falha ao conectar ao banco."}), 500

        cursor = connection.cursor()

        # Busca dados do artigo + setor + metragem + Ean14
        cursor.execute(
            """
            SELECT TOP 1
                Obj.CdObj,
                NmObj     = UPPER(Obj.NmObj),
                NmObj1    = UPPER(CASE
                    WHEN CHARINDEX('MM', UPPER(Obj.NmObj)) > 0
                    THEN LEFT(Obj.NmObj, CHARINDEX('MM', UPPER(Obj.NmObj)) + 1)
                    ELSE Obj.NmObj END),
                NmObj2    = UPPER(CASE
                    WHEN CHARINDEX('MM', UPPER(Obj.NmObj)) > 0
                    THEN LTRIM(SUBSTRING(Obj.NmObj, CHARINDEX('MM', UPPER(Obj.NmObj)) + 2, LEN(Obj.NmObj)))
                    ELSE '' END),
                Descricao = ISNULL(Obj.TtObj, ''),
                Setor     = ISNULL(Obj.CdObjLin, 0),
                Ean14     = ISNULL(CONVERT(varchar(50), CaoEan14.NrCao), ''),
                TipoCaixa = CASE
                    WHEN Carretel.NmOpc = 'ENF'                   THEN 'ENFE'
                    WHEN Carretel.NmOpc = 'ENFRALDADO'            THEN 'ENFR'
                    WHEN Carretel.NmOpc IS NULL                   THEN ''
                    WHEN TRY_CAST(Carretel.NmOpc AS int) <= 1200  THEN 'P'
                    WHEN TRY_CAST(Carretel.NmOpc AS int) >  1200  THEN 'G'
                    ELSE 'D' END,
                Metragem = CASE
                    WHEN Carretel.NmOpc = 'ENF'        THEN 'ENF - Enfestado'
                    WHEN Carretel.NmOpc = 'ENFRALDADO' THEN 'ENFRALDADO'
                    WHEN Carretel.NmOpc IS NULL         THEN ''
                    ELSE CONVERT(varchar(50), Carretel.NmOpc) + ' Mts' END,
                MetragemCurta = CASE
                    WHEN Carretel.NmOpc = 'ENF'        THEN 'ENF'
                    WHEN Carretel.NmOpc = 'ENFRALDADO' THEN 'ENFR'
                    WHEN Carretel.NmOpc IS NULL         THEN ''
                    ELSE CONVERT(varchar(50), Carretel.NmOpc) END
            FROM dbo.TbObj Obj WITH (NOLOCK)
            LEFT JOIN dbo.TbCao CaoEan14 WITH (NOLOCK)
                   ON CaoEan14.CdObj = Obj.CdObj AND CaoEan14.CdTca = 4
            LEFT JOIN (
                SELECT Opo.CdObj, NmOpc = Opc.NmOpc
                FROM dbo.TbOpo Opo WITH (NOLOCK)
                JOIN dbo.TbCrc Crc WITH (NOLOCK) ON Crc.CdCrc = Opo.CdCrc
                JOIN dbo.TbCgr Cgr WITH (NOLOCK)
                  ON Cgr.CdCgr = Opo.CdCgr AND Cgr.CdCrc = Crc.CdCrc AND Crc.CdCrc = 96
                LEFT JOIN dbo.TbOpc Opc WITH (NOLOCK) ON Opc.CdOpc = Opo.CdOpc
                WHERE EXISTS (
                    SELECT 1 FROM dbo.TbArvObj ArvObj WITH (NOLOCK)
                    WHERE ArvObj.CdObjFil = Opo.CdObj AND ArvObj.CdObj = ?
                )
            ) Carretel ON Carretel.CdObj = Obj.CdObj
            WHERE EXISTS (
                SELECT 1 FROM dbo.TbArvObj ArvObj WITH (NOLOCK)
                WHERE ArvObj.CdObjFil = Obj.CdObj AND ArvObj.CdObj = ?
            )
            ORDER BY Obj.CdObj
            """,
            (cd_obj, cd_obj),
        )
        row = _row_dict(cursor, cursor.fetchone())
        if not row:
            return jsonify({"error": "Artigo não encontrado."}), 404

        nm_obj = str(row.get("NmObj") or "").strip().upper()
        nm_obj1 = str(row.get("NmObj1") or "").strip()
        nm_obj2 = str(row.get("NmObj2") or "").strip()
        descricao = str(row.get("Descricao") or "").strip()
        setor = int(row.get("Setor") or 0)
        tipo_caixa = str(row.get("TipoCaixa") or "").strip().upper()
        metragem = str(row.get("Metragem") or "").strip()
        metragem_curta = str(row.get("MetragemCurta") or "").strip()
        ean14 = str(row.get("Ean14") or "").strip()

        # P/G determinado pelos metros enviados na requisição, não pela config do BD.
        # As faixas (caixa_p/caixa_g) são as cadastradas para o artigo em
        # Stik_PadraoCaixa; sem cadastro, cai no limiar genérico de 1200m.
        # Quando há cadastro, só marca P/G se os metros baterem EXATAMENTE
        # com a caixa cheia — qualquer outro valor é saldo (S). Se os metros
        # passarem de uma caixa cheia (equivalem a caixa fechada + saldo),
        # NÃO divide automaticamente: bloqueia e orienta o usuário a
        # imprimir a caixa fechada primeiro, depois o saldo separadamente.
        if tipo_caixa in ("P", "G"):
            metros_int = _to_int(metros, 0)
            padrao = _buscar_padrao_caixa(cursor, nm_obj)
            caixa_p = _to_int(padrao.get("caixa_p"), 0)
            caixa_g = _to_int(padrao.get("caixa_g"), 0)
            if caixa_p > 0 or caixa_g > 0:
                if caixa_p > 0 and metros_int == caixa_p:
                    tipo_caixa = "P"
                elif caixa_g > 0 and metros_int == caixa_g:
                    tipo_caixa = "G"
                elif caixa_g > 0 and metros_int > caixa_g:
                    saldo = metros_int - caixa_g
                    return jsonify({
                        "error": (
                            f"{metros_int}m equivale a 1 caixa G ({caixa_g}m) + {saldo}m de saldo. "
                            f"Imprima a caixa G primeiro (informe {caixa_g}), depois imprima o "
                            f"saldo separadamente (informe {saldo})."
                        )
                    }), 400
                elif caixa_p > 0 and metros_int > caixa_p:
                    saldo = metros_int - caixa_p
                    return jsonify({
                        "error": (
                            f"{metros_int}m equivale a 1 caixa P ({caixa_p}m) + {saldo}m de saldo. "
                            f"Imprima a caixa P primeiro (informe {caixa_p}), depois imprima o "
                            f"saldo separadamente (informe {saldo})."
                        )
                    }), 400
                else:
                    tipo_caixa = "S"
            else:
                tipo_caixa = "P" if metros_int <= 1200 else "G"

        # Valida TipoCaixa
        if tipo_caixa == "CAIXA M":
            return jsonify({"error": "Tipo de caixa inválido: CAIXA M. Preencha com P, G, ENFE, ENFR ou D."}), 400
        if tipo_caixa not in ("P", "G", "ENFE", "ENFR", "D", "S"):
            return jsonify({"error": f"Tipo de caixa inválido: '{tipo_caixa}'. Use: P, G, S, ENFE, ENFR ou D."}), 400

        # Detecta flags
        tem_preto = "PRETO" in nm_obj
        eh_preto_especial = tem_preto and any(x in nm_obj for x in [
            "PRETO FX", "PRETO LSB", "PRETO LP", "PRETO MP 3", "PRETO FD",
        ])
        nao_imprime_lote_linha = "ENFRALDADO" in nm_obj or "ENFESTADO" in nm_obj
        detalhe_obrigatorio = cd_obj in _CDOBJ_DETALHE_OBRIGATORIO or setor == 10180
        imprime_detalhe_ao_lado = cd_obj in _CDOBJ_DETALHE_OBRIGATORIO
        imprime_lote_abaixo_metros = cd_obj in _CDOBJ_DETALHE_OBRIGATORIO

        detalhe_vazio = detalhe <= 0

        # Validações de negócio
        if detalhe_obrigatorio and detalhe_vazio:
            sufixo = f"Setor 10180" if setor == 10180 else f"CdObj {cd_obj}"
            return jsonify({"error": f"{sufixo}: é obrigatório preencher o DETALHE."}), 400

        if tem_preto:
            faltando = []
            if detalhe_vazio:
                faltando.append("DETALHE")
            if not lote:
                faltando.append("LOTE")
            if faltando:
                return jsonify({"error": f"Artigo PRETO: é obrigatório preencher {' e '.join(faltando)}."}), 400

        # Auto-resolve do Detalhe quando não informado
        detalhe_id = detalhe
        nm_detalhe = ""

        if detalhe_id <= 0:
            if tem_preto and eh_preto_especial and cd_obj in _CDOBJ_PRETO_AUTO_LOT:
                cursor.execute(
                    "SELECT CdLot = MAX(CdLot) FROM TbLot WHERE CdObj = ?",
                    (cd_obj,),
                )
                r = cursor.fetchone()
                if r and r[0]:
                    detalhe_id = int(r[0])
            elif not tem_preto:
                cursor.execute(
                    "SELECT TOP 1 CdLot FROM TbLot WHERE CdObj = ? ORDER BY CdLot DESC",
                    (cd_obj,),
                )
                r = cursor.fetchone()
                if r and r[0]:
                    detalhe_id = int(r[0])

        # Lookup NmLot do detalhe resolvido
        if detalhe_id > 0:
            cursor.execute(
                "SELECT NmLot FROM TbLot WHERE CdLot = ?",
                (detalhe_id,),
            )
            r = cursor.fetchone()
            if r and r[0]:
                nm_detalhe = str(r[0]).strip().upper()

        # Valida e resolve operador
        operador_qr = "0"
        if operador > 0:
            cursor.execute(
                """
                SELECT TOP 1 CodigoQR
                FROM Stik_WMS_OperadorQRCode
                WHERE CodigoOperador = ?
                """,
                (operador,),
            )
            r = cursor.fetchone()
            if r and r[0]:
                operador_qr = str(r[0]).strip()
            else:
                return jsonify({
                    "error": f"Operador {operador} não encontrado na tabela Stik_WMS_OperadorQRCode.",
                }), 400

        # Datas
        hoje = date.today()
        data_fabricacao = f"{str(hoje.day).zfill(2)}/{str(hoje.month).zfill(2)}/{hoje.year}"
        data_codificada = _calcular_data_codificada(hoje.day, hoje.month, hoje.year)

        # Lote redundante (PRETO onde LOTE == NmObj → não imprime linha de lote)
        nao_imprime_lote_redundante = (
            tem_preto and bool(lote) and lote == nm_obj
        )
        nao_imprime_lote_final = nao_imprime_lote_linha or nao_imprime_lote_redundante

        # ── Monta as linhas do layout (equivale às posições ZPL) ──

        # Linha 230
        if setor == 10180:
            linha230 = f"COR: {nm_detalhe}" if nm_detalhe else f"COR: {detalhe_id if detalhe_id > 0 else ''}"
        else:
            linha230 = f"{metros} Metros"
            if imprime_detalhe_ao_lado and nm_detalhe:
                linha230 += f" {nm_detalhe}"
            if pedido_especial:
                linha230 += " PDE"
            if lote_inline and lote:
                linha230 += f" {lote}"

        # Linha 260
        linha260 = ""
        if setor == 10180:
            linha260 = f"{metros} Metros"
            if pedido_especial:
                linha260 += " PDE"
            if imprime_detalhe_ao_lado and nm_detalhe:
                linha260 += f" {nm_detalhe}"
            if lote_inline and lote:
                linha260 += f" {lote}"
        elif lote_inline:
            linha260 = ""  # já foi inline na linha 230
        elif imprime_lote_abaixo_metros:
            linha260 = lote if lote else ""
        elif nao_imprime_lote_final:
            linha260 = ""
        else:
            if lote:
                linha260 = f"LOTE: {lote}"
                if pedido_especial:
                    linha260 += " PDE"
            else:
                linha260 = ""

        # Linha 300
        if setor == 10180:
            linha300 = "" if (nao_imprime_lote_final or lote_inline) else (lote or "")
        else:
            linha300 = f"CARR. {metragem_curta}" if metragem_curta else ""

        # Tipo de caixa no QR — mapeado para código curto
        # ENFE (banco) → ENF no QR | ENFR, P, G, D permanecem iguais
        _tipo_caixa_qr_map = {"ENFE": "ENF", "ENFR": "ENFR", "P": "P", "G": "G", "D": "D", "S": "S"}
        tipo_caixa_qr = _tipo_caixa_qr_map.get(tipo_caixa, tipo_caixa)

        # Data de fabricação como inteiro YYYYMMDD (ex.: 20260527)
        data_int = hoje.year * 10000 + hoje.month * 100 + hoje.day

        # Ordem como inteiro
        nr_ordem_int = _to_int(nr_ordem, 0)

        # QR Code — formato compacto com chaves de 1 letra
        # CdObj  = código do artigo
        # Detalhe = CdLot (cor/lote)
        # D      = data fabricação YYYYMMDD
        # C      = tipo caixa (P | G | ENF | ENFR | D)
        # O      = número da ordem de produção
        # CX     = código único de rastreio da caixa (gerado no momento da impressão)
        # LI     = lote de impressão (agrupa as caixas impressas na mesma leva)
        cx_gerado = _gerar_cx()
        qr_dict = {
            "CdObj": cd_obj,
            "Detalhe": detalhe_id,
            "D": data_int,
            "C": tipo_caixa_qr,
            "O": nr_ordem_int,
            "CX": cx_gerado,
            "LI": li,
        }

        if operador_qr != "0":
            qr_dict["operador"] = operador_qr

        qr_code = json.dumps(qr_dict, ensure_ascii=False, separators=(",", ":"))

        # ------------------------------------------------------------
        # Persistência opcional (best-effort) do lote de impressão: grava a
        # caixa já na impressão, com Status='IMPRESSA' e Endereco em branco,
        # para permitir que a Entrada leia 1 única etiqueta do lote (LI) e
        # recupere todas as CX impressas juntas, sem escanear caixa por
        # caixa. Puramente aditivo — se a coluna LI ainda não existir no
        # banco (migration em api/sql/ não aplicada) ou qualquer erro
        # ocorrer aqui, a impressão da etiqueta segue normalmente; nada do
        # fluxo atual é afetado.
        # ------------------------------------------------------------
        try:
            cursor.execute(
                """
                INSERT INTO dbo.Stik_WMS_Caixa
                    (CX, LI, CdObj, Detalhe, TipoCaixa, NrOrdem, DataFabricacao,
                     Status, CdUsr, DataImpressao)
                VALUES (?, ?, ?, ?, ?, ?, ?, 'IMPRESSA', ?, GETDATE())
                """,
                (
                    cx_gerado,
                    li,
                    cd_obj,
                    detalhe_id if detalhe_id > 0 else None,
                    tipo_caixa_qr,
                    nr_ordem_int if nr_ordem_int > 0 else None,
                    str(data_int),
                    operador if operador > 0 else None,
                ),
            )
            connection.commit()
        except Exception as persist_error:
            try:
                connection.rollback()
            except Exception:
                pass
            print(
                f"[etiqueta-caixa-v2] Aviso: não foi possível persistir LI/CX "
                f"na impressão ({persist_error}). Etiqueta segue normalmente."
            )

        result = {
            "CdObj": cd_obj,
            "DetalheId": detalhe_id,
            "NmObj": nm_obj,
            "NmObj1": nm_obj1,
            "NmObj2": nm_obj2,
            "NmDetalhe": nm_detalhe,
            "Descricao": descricao,
            "TipoCaixa": tipo_caixa,
            "Ean14": ean14,
            "Metragem": metragem,
            "DataFabricacao": data_fabricacao,
            "Metros": metros,
            "NrOrdem": nr_ordem,
            "Lote": lote,
            "Operador": operador,
            "OperadorQr": operador_qr,
            "PedidoEspecial": pedido_especial,
            "QtdeImp": qtde_imp,
            "LoteInline": lote_inline,
            # Flags
            "Setor": setor,
            "Setor10180": setor == 10180,
            "TemPreto": tem_preto,
            "EhPretoEspecial": eh_preto_especial,
            "NaoImprimeLoteLinha": nao_imprime_lote_final,
            "DetalheObrigatorio": detalhe_obrigatorio,
            # Linhas de layout pré-computadas
            "Linha230": linha230,
            "Linha260": linha260,
            "Linha300": linha300,
            "LinhaData": f"DATA DE FABRICACAO: {data_fabricacao}",
            # QR Code — formato novo
            "QrCode": qr_code,
            # Lote de impressão: cliente reenvia este valor nas próximas
            # chamadas do mesmo lote (mesmo destino/artigo) para agrupar as
            # caixas sob o mesmo LI.
            "LI": li,
        }

        return jsonify({"success": True, "data": result}), 200

    except Exception as e:
        return jsonify({"error": str(e)}), 500

    finally:
        if connection:
            connection.close()


# ===================================================================
# ROTA: ETIQUETA DE CARRETEL (POST)
# Aba nova de impressão (EPL2), distinta da etiqueta de Caixa (ZPL).
# Busca NmObj/Descricao/Ean13/Metragem do artigo (Metragem vem do mesmo
# grupo de característica 96 "Carretel" já usado nas etiquetas de caixa,
# não é digitada); Lote/Operador/QtdeImp vêm da tela e só são ecoados.
# ===================================================================
@WMS_Etiquetas_QrCode_bp.route("/consulta/wms/etiqueta-carretel", methods=["POST"])
def WMS_Etiquetas_QrCode_etiqueta_carretel():
    connection = None
    try:
        data = request.get_json() or {}

        cd_obj = _to_int(data.get("cd_obj") or data.get("CdObj"))
        lote = str(data.get("lote") or data.get("Lote") or "").strip().upper()
        operador = str(data.get("operador") or data.get("Operador") or "").strip()
        qtde_imp = max(1, _to_int(data.get("qtde_imp") or data.get("QtdeImp"), 1))

        if cd_obj <= 0:
            return jsonify({"error": "Parâmetro obrigatório: cd_obj"}), 400

        connection = create_connection_tinturaria()
        if connection is None:
            return jsonify({"error": "Falha ao conectar ao banco."}), 500

        cursor = connection.cursor()
        cursor.execute(
            """
            SELECT TOP 1
                Obj.CdObj,
                NmObj = UPPER(Obj.NmObj),
                Descricao = ISNULL(Obj.TtObj, ''),
                Ean13 = ISNULL(dbo.UFN_GeraCodigoEAN(CaoEan13.NrCao), ''),
                Metragem = CASE
                    WHEN Carretel.NmOpc = 'ENF'        THEN 'ENF - Enfestado'
                    WHEN Carretel.NmOpc = 'ENFRALDADO' THEN 'ENFRALDADO'
                    WHEN Carretel.NmOpc IS NULL        THEN ''
                    ELSE CONVERT(varchar(50), Carretel.NmOpc) + ' Mts'
                END
            FROM dbo.TbObj Obj WITH (NOLOCK)
            LEFT JOIN dbo.TbCao CaoEan13 WITH (NOLOCK)
                   ON CaoEan13.CdObj = Obj.CdObj
                  AND CaoEan13.CdTca = 2
            LEFT JOIN (
                SELECT Opo.CdObj, NmOpc = Opc.NmOpc
                FROM dbo.TbOpo Opo WITH (NOLOCK)
                JOIN dbo.TbCrc Crc WITH (NOLOCK) ON Crc.CdCrc = Opo.CdCrc
                JOIN dbo.TbCgr Cgr WITH (NOLOCK)
                  ON Cgr.CdCgr = Opo.CdCgr AND Cgr.CdCrc = Crc.CdCrc AND Crc.CdCrc = 96
                LEFT JOIN dbo.TbOpc Opc WITH (NOLOCK) ON Opc.CdOpc = Opo.CdOpc
                WHERE EXISTS (
                    SELECT 1 FROM dbo.TbArvObj ArvObj WITH (NOLOCK)
                    WHERE ArvObj.CdObjFil = Opo.CdObj AND ArvObj.CdObj = ?
                )
            ) Carretel ON Carretel.CdObj = Obj.CdObj
            WHERE Obj.CdObj = ?
            """,
            (cd_obj, cd_obj),
        )
        row = _row_dict(cursor, cursor.fetchone())
        if not row:
            return jsonify({"error": f"Artigo {cd_obj} não encontrado."}), 404

        hoje = date.today()
        data_codificada = _calcular_mes_ano_codificado(hoje.month, hoje.year)

        result = {
            "CdObj": cd_obj,
            "NmObj": str(row.get("NmObj") or "").strip(),
            "Descricao": str(row.get("Descricao") or "").strip(),
            "Ean13": str(row.get("Ean13") or "").strip(),
            "Metragem": str(row.get("Metragem") or "").strip(),
            "Lote": lote,
            "Operador": operador,
            "QtdeImp": qtde_imp,
            "DataCodificada": data_codificada,
        }
        return jsonify({"success": True, "data": result}), 200

    except Exception as e:
        return jsonify({"error": str(e)}), 500

    finally:
        if connection:
            connection.close()


@WMS_Etiquetas_QrCode_bp.route("/consulta/wms/artigos-busca", methods=["GET"])
def WMS_Etiquetas_QrCode_artigos_busca():
    """Autocomplete de artigos por nome ou código (mínimo 2 caracteres)."""
    q = (request.args.get("q") or "").strip()
    if len(q) < 2:
        return jsonify({"data": []}), 200

    connection = None
    try:
        connection = create_connection_tinturaria()
        if connection is None:
            return jsonify({"error": "Falha ao conectar ao banco."}), 500

        cursor = connection.cursor()
        cursor.execute(
            """
            SELECT TOP 30
                CdObj = Obj.CdObj,
                NmObj = RTRIM(ISNULL(CONVERT(varchar(50), CaoDefault.NrCao) + '   ', '') + Obj.NmObj)
            FROM dbo.TbObj Obj WITH (NOLOCK)
            JOIN dbo.TbArvObj ArvObj WITH (NOLOCK)
                ON ArvObj.CdObjFil = Obj.CdObj
               AND ArvObj.CdObj = 1
            LEFT JOIN (
                SELECT Cao.CdObj, Cao.NrCao
                FROM dbo.TbCao Cao WITH (NOLOCK)
                JOIN dbo.TbTca Tca WITH (NOLOCK)
                  ON Tca.CdTca = Cao.CdTca
                 AND Tca.FlTcaDef = 1
            ) CaoDefault ON CaoDefault.CdObj = Obj.CdObj
            WHERE (
                    UPPER(Obj.NmObj) LIKE '%' + UPPER(?) + '%'
                 OR CONVERT(varchar, Obj.CdObj) LIKE ? + '%'
            )
            ORDER BY Obj.NrObjOrd001, Obj.NrObjOrd002, Obj.NrObjOrd003
            """,
            (q, q),
        )
        rows = cursor.fetchall()
        data = [
            {"CdObj": row[0], "NmObj": str(row[1] or "").strip()}
            for row in rows
        ]
        return jsonify({"data": data}), 200

    except Exception as e:
        return jsonify({"error": str(e)}), 500
    finally:
        if connection:
            connection.close()


_IMPRESSORAS = [
    {"nome": "ZebraZD220", "ip": "168.190.30.223", "porta": 9100},
    {"nome":"ZebraZD220", "ip": '168.190.30.172', "porta": 9100},
    {"nome":"ZebraZD220", "ip": '168.190.30.181', "porta": 9100},
    {"nome":"ZebraZD220", "ip": '168.190.30.206', "porta": 9100},
    {"nome":"ZebraZD220", "ip": '168.190.30.201', "porta": 9100},
    {"nome":"ZebraZD220", "ip": '168.190.31.20', "porta": 9100},
    {"nome":"EtqManual", "ip": '168.190.31.22', "porta": 9100},
]


@WMS_Etiquetas_QrCode_bp.route("/consulta/wms/impressoras", methods=["GET"])
def WMS_Etiquetas_QrCode_impressoras():
    """Retorna a lista de impressoras Zebra configuradas."""
    return jsonify({"data": _IMPRESSORAS}), 200


@WMS_Etiquetas_QrCode_bp.route("/consulta/wms/artigo-lotes", methods=["GET"])
def WMS_Etiquetas_QrCode_artigo_lotes():
    """Retorna os lotes (detalhe) de um artigo para seleção em dropdown."""
    cd_obj = _to_int(
        request.args.get("cd_obj") or request.args.get("CdObj")
    )
    if cd_obj <= 0:
        return jsonify({"error": "Parâmetro obrigatório: cd_obj"}), 400

    connection = None
    try:
        connection = create_connection_tinturaria()
        if connection is None:
            return jsonify({"error": "Falha ao conectar ao banco."}), 500

        cursor = connection.cursor()
        cursor.execute(
            """
            SELECT Lot.CdLot, Lot.NmLot
              FROM dbo.TbLot Lot WITH (NOLOCK)
             WHERE Lot.CdObj = ?
             ORDER BY Lot.CdLot DESC
            """,
            (cd_obj,),
        )
        rows = cursor.fetchall()
        data = [
            {"CdLot": row[0], "NmLot": str(row[1] or "").strip()}
            for row in rows
        ]
        return jsonify({"data": data}), 200

    except Exception as e:
        return jsonify({"error": str(e)}), 500
    finally:
        if connection:
            connection.close()
