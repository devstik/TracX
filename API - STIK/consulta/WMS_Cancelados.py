# # import requests
# # import re
# # import unicodedata
# # from flask import Blueprint, jsonify, request
# # from database.server import create_connection_tinturaria 
# # import datetime
# # from datetime import timedelta


# # wms_cancelados_bp = Blueprint('wms_cancelados', __name__)

# # # ===================================================================
# # # ROTA: Cancelamento
# # def _normalizar_texto(valor):
# #     texto = (valor or '').strip()
# #     if not texto:
# #         return ''
# #     texto = unicodedata.normalize('NFKD', texto)
# #     texto = ''.join(ch for ch in texto if not unicodedata.combining(ch))
# #     return ' '.join(texto.split()).strip()


# # def _extrair_artigo_base(artigo):
# #     texto = _normalizar_texto(artigo)
# #     if not texto:
# #         return ''

# #     match = re.search(r'^(.+?\bmm)\b', texto, flags=re.IGNORECASE)
# #     if match:
# #         return match.group(1).strip()

# #     return texto.strip()


# # def _obter_token_node_api():
# #     urls_login = [
# #         'https://mediumpurple-loris-159660.hostingersite.com/auth/login',
# #     ]

# #     payload = {
# #         'username': 'anderson',
# #         'password': '142046',
# #     }

# #     for url in urls_login:
# #         try:
# #             resp = requests.post(
# #                 url,
# #                 json=payload,
# #                 timeout=15,
# #                 headers={'Content-Type': 'application/json'}
# #             )
# #             if resp.status_code != 200:
# #                 continue

# #             body = resp.json() or {}
# #             token = body.get('accessToken') or body.get('token')
# #             if token:
# #                 return token
# #         except Exception:
# #             continue

# #     return None


# # def _resolver_artigo_oficial_por_sku(cod_sku):
# #     token = _obter_token_node_api()
# #     if not token:
# #         return None

# #     urls_artigos = [
# #         'https://mediumpurple-loris-159660.hostingersite.com/api/artigos',
# #     ]

# #     for url in urls_artigos:
# #         try:
# #             resp = requests.get(
# #                 url,
# #                 params={'CdObj': cod_sku},
# #                 timeout=15,
# #                 headers={
# #                     'Content-Type': 'application/json',
# #                     'Authorization': f'Bearer {token}',
# #                 }
# #             )
# #             if resp.status_code != 200:
# #                 continue

# #             payload = resp.json() or {}
# #             rows = payload.get('data') or payload.get('rows') or payload.get('result') or []

# #             if not isinstance(rows, list) or not rows:
# #                 continue

# #             for row in rows:
# #                 if not isinstance(row, dict):
# #                     continue

# #                 artigo = str(
# #                     row.get('artigo')
# #                     or row.get('Artigo')
# #                     or row.get('ARTIGO')
# #                     or row.get('Objeto')
# #                     or row.get('objeto')
# #                     or row.get('NmArtigo')
# #                     or ''
# #                 ).strip()

# #                 if artigo:
# #                     return artigo
# #         except Exception:
# #             continue

# #     return None


# # def _buscar_padrao_embalagem_por_artigo(artigo):
# #     urls_padrao = [
# #         'https://mediumpurple-loris-159660.hostingersite.com/consulta/wms/stik_padrao_caixa',
# #         'http://168.190.90.2:3000/consulta/wms/stik_padrao_caixa',
# #     ]

# #     artigo_normalizado = _normalizar_texto(artigo).lower()

# #     for url in urls_padrao:
# #         try:
# #             resp = requests.get(url, timeout=15)
# #             if resp.status_code != 200:
# #                 continue

# #             payload = resp.json() or {}
# #             rows = payload.get('data') or payload.get('rows') or payload.get('result') or []

# #             if not isinstance(rows, list) or not rows:
# #                 continue

# #             for row in rows:
# #                 if not isinstance(row, dict):
# #                     continue

# #                 artigo_row = str(
# #                     row.get('artigo')
# #                     or row.get('Artigo')
# #                     or row.get('ARTIGO')
# #                     or row.get('Objeto')
# #                     or row.get('objeto')
# #                     or row.get('NmArtigo')
# #                     or ''
# #                 ).strip()

# #                 if not artigo_row:
# #                     continue

# #                 artigo_row_normalizado = _normalizar_texto(artigo_row).lower()
# #                 if artigo_row_normalizado == artigo_normalizado:
# #                     return row

# #             for row in rows:
# #                 if not isinstance(row, dict):
# #                     continue

# #                 artigo_row = str(
# #                     row.get('artigo')
# #                     or row.get('Artigo')
# #                     or row.get('ARTIGO')
# #                     or row.get('Objeto')
# #                     or row.get('objeto')
# #                     or row.get('NmArtigo')
# #                     or ''
# #                 ).strip()

# #                 if not artigo_row:
# #                     continue

# #                 artigo_row_normalizado = _normalizar_texto(artigo_row).lower()
# #                 if artigo_normalizado in artigo_row_normalizado:
# #                     return row
# #         except Exception:
# #             continue

# #     return None

# # @wms_cancelados_bp.route('/consulta/wms/cancelados/saldo', methods=['GET'])
# # def saldo_item_cancelado():
# #     connection = None
# #     try:
# #         cd_obj = request.args.get('CdObj')
# #         cd_lot = request.args.get('CdLot', 0)
# #         data_inicial = request.args.get('data_inicial')
# #         data_final = request.args.get('data_final')

# #         if cd_obj is None or not data_inicial or not data_final:
# #             return jsonify({
# #                 "error": "Campos obrigatórios: CdObj, data_inicial, data_final"
# #             }), 400

# #         try:
# #             cd_obj = int(cd_obj)
# #             cd_lot = int(cd_lot or 0)
# #         except (TypeError, ValueError):
# #             return jsonify({"error": "CdObj/CdLot inválidos"}), 400

# #         connection = create_connection_tinturaria()
# #         if connection is None:
# #             return jsonify({
# #                 "status": "SQL_ERROR",
# #                 "details": "Falha ao conectar ao banco."
# #             }), 500

# #         cursor = connection.cursor()
# #         cursor.execute("SET NOCOUNT ON;")

# #         cursor.execute("""
# #             WITH Cancelados AS (
# #                 SELECT
# #                     Fat.NrRomaneio,
# #                     Fat.CdVpo,
# #                     Fat.CdObj,
# #                     ISNULL(Fat.CdLot, 0) AS CdLot,
# #                     QtCancelada = CASE
# #                         WHEN ISNULL(Fat.QtFatAtend, 0) > 0 THEN Fat.QtFatAtend
# #                         ELSE Fat.QtFat
# #                     END
# #                 FROM dbo.Stik_Pedido_QtdFat Fat WITH (NOLOCK)
# #                 WHERE Fat.TpSitFat = 11
# #                   AND Fat.CdObj = ?
# #                   AND ISNULL(Fat.CdLot, 0) = ISNULL(?, 0)
# #                   AND CONVERT(date, Fat.DtExp) >= CONVERT(date, ?)
# #                   AND CONVERT(date, Fat.DtExp) <= CONVERT(date, ?)
# #             ),
# #             Alocados AS (
# #                 SELECT
# #                     A.NrRomaneio,
# #                     A.CdVpo,
# #                     A.CdObj,
# #                     ISNULL(A.CdLot, 0) AS CdLot,
# #                     QtAlocada = SUM(A.Quantidade)
# #                 FROM dbo.Stik_WMS_Cancelados_Alocados A WITH (NOLOCK)
# #                 WHERE A.CdObj = ?
# #                   AND ISNULL(A.CdLot, 0) = ISNULL(?, 0)
# #                   AND CONVERT(date, A.DtAlocacao) >= CONVERT(date, ?)
# #                   AND CONVERT(date, A.DtAlocacao) <= CONVERT(date, ?)
# #                 GROUP BY
# #                     A.NrRomaneio, A.CdVpo, A.CdObj, A.CdLot
# #             )
# #             SELECT
# #                 C.NrRomaneio,
# #                 C.CdVpo,
# #                 C.CdObj,
# #                 C.CdLot,
# #                 C.QtCancelada,
# #                 QtAlocada = ISNULL(A.QtAlocada, 0),
# #                 QtDisponivel = C.QtCancelada - ISNULL(A.QtAlocada, 0)
# #             FROM Cancelados C
# #             LEFT JOIN Alocados A
# #                 ON A.NrRomaneio = C.NrRomaneio
# #                AND A.CdVpo = C.CdVpo
# #                AND A.CdObj = C.CdObj
# #                AND ISNULL(A.CdLot, 0) = ISNULL(C.CdLot, 0)
# #             WHERE (C.QtCancelada - ISNULL(A.QtAlocada, 0)) > 0
# #             ORDER BY C.NrRomaneio, C.CdVpo
# #         """, (
# #             cd_obj, cd_lot, data_inicial, data_final,
# #             cd_obj, cd_lot, data_inicial, data_final
# #         ))

# #         rows = cursor.fetchall()
# #         colunas = [c[0] for c in cursor.description]
# #         itens = [dict(zip(colunas, row)) for row in rows]

# #         qt_cancelada = sum(float(item['QtCancelada'] or 0) for item in itens)
# #         qt_alocada = sum(float(item['QtAlocada'] or 0) for item in itens)
# #         qt_disponivel = sum(float(item['QtDisponivel'] or 0) for item in itens)

# #         return jsonify({
# #             "CdObj": cd_obj,
# #             "CdLot": cd_lot,
# #             "QtCancelada": qt_cancelada,
# #             "QtAlocada": qt_alocada,
# #             "QtDisponivel": qt_disponivel,
# #             "romaneios": itens
# #         }), 200

# #     except Exception as e:
# #         return jsonify({"error": str(e)}), 500
# #     finally:
# #         if connection:
# #             connection.close()

# # @wms_cancelados_bp.route('/consulta/wms/cancelados/alocar', methods=['POST'])
# # def alocar_item_cancelado():
# #     connection = None
# #     try:
# #         data = request.get_json() or {}

# #         endereco = (data.get('Endereco') or '').strip()
# #         cd_obj = data.get('CdObj')
# #         cd_lot = data.get('CdLot', 0)
# #         quantidade = data.get('Quantidade')
# #         data_inicial = data.get('DataInicial')
# #         data_final = data.get('DataFinal')
# #         cd_usr = data.get('CdUsr')
# #         fonte = (data.get('Fonte') or 'romaneios').strip().lower()

# #         if not endereco or cd_obj is None or quantidade is None or not data_inicial or not data_final:
# #             return jsonify({
# #                 "error": "Campos obrigatórios: Endereco, CdObj, Quantidade, DataInicial, DataFinal"
# #             }), 400

# #         if fonte not in ('romaneios', 'notas'):
# #             return jsonify({
# #                 "error": "Fonte inválida. Use 'romaneios' ou 'notas'."
# #             }), 400

# #         try:
# #             cd_obj = int(cd_obj)
# #             cd_lot = int(cd_lot or 0)
# #             quantidade = float(str(quantidade).replace(',', '.'))
# #             cd_usr = int(cd_usr) if cd_usr not in (None, '', '0', 0) else None
# #             #dt_ini = datetime.strptime(data_inicial, '%Y-%m-%d')
# #             #dt_fim = datetime.strptime(data_final, '%Y-%m-%d') + timedelta(days=1)
# #             dt_ini = datetime.datetime.strptime(data_inicial, '%Y-%m-%d')
# #             dt_fim = datetime.datetime.strptime(data_final, '%Y-%m-%d') + timedelta(days=1)


# #         except (TypeError, ValueError):
# #             return jsonify({
# #                 "error": "CdObj/CdLot/Quantidade/CdUsr/DataInicial/DataFinal inválidos"
# #             }), 400

# #         if quantidade <= 0:
# #             return jsonify({"error": "Quantidade deve ser maior que zero"}), 400

# #         connection = create_connection_tinturaria()
# #         if connection is None:
# #             return jsonify({
# #                 "status": "SQL_ERROR",
# #                 "details": "Falha ao conectar ao banco."
# #             }), 500

# #         cursor = connection.cursor()
# #         cursor.execute("SET NOCOUNT ON; SET XACT_ABORT ON;")

# #         if fonte == 'romaneios':
# #             cursor.execute("""
# #                 WITH Cancelados AS (
# #                     SELECT
# #                         RefID = CONCAT('ROM|', Fat.NrRomaneio, '|', Fat.CdVpo),
# #                         Fat.NrRomaneio,
# #                         Fat.CdVpo,
# #                         Fat.CdObj,
# #                         ISNULL(Fat.CdLot, 0) AS CdLot,
# #                         QtCancelada = CASE
# #                             WHEN ISNULL(Fat.QtFatAtend, 0) > 0 THEN Fat.QtFatAtend
# #                             ELSE Fat.QtFat
# #                         END
# #                     FROM dbo.Stik_Pedido_QtdFat Fat WITH (UPDLOCK, HOLDLOCK)
# #                     WHERE Fat.TpSitFat = 11
# #                       AND Fat.CdObj = ?
# #                       AND ISNULL(Fat.CdLot, 0) = ISNULL(?, 0)
# #                       AND Fat.DtExp >= ?
# #                       AND Fat.DtExp < ?
# #                 ),
# #                 Alocados AS (
# #                     SELECT
# #                         RefID = CONCAT('ROM|', A.NrRomaneio, '|', A.CdVpo),
# #                         QtAlocada = SUM(A.Quantidade)
# #                     FROM dbo.Stik_WMS_Cancelados_Alocados A WITH (NOLOCK)
# #                     WHERE A.CdObj = ?
# #                       AND ISNULL(A.CdLot, 0) = ISNULL(?, 0)
# #                       AND A.Origem = 'APP_CANCELADOS_ROMANEIO'
# #                     GROUP BY A.NrRomaneio, A.CdVpo
# #                 )
# #                 SELECT
# #                     C.RefID,
# #                     C.NrRomaneio,
# #                     C.CdVpo,
# #                     C.CdObj,
# #                     C.CdLot,
# #                     C.QtCancelada,
# #                     QtAlocada = ISNULL(A.QtAlocada, 0),
# #                     QtDisponivel = C.QtCancelada - ISNULL(A.QtAlocada, 0)
# #                 FROM Cancelados C
# #                 LEFT JOIN Alocados A
# #                     ON A.RefID = C.RefID
# #                 WHERE (C.QtCancelada - ISNULL(A.QtAlocada, 0)) > 0
# #                 ORDER BY C.NrRomaneio, C.CdVpo
# #             """, (
# #                 cd_obj, cd_lot, dt_ini, dt_fim,
# #                 cd_obj, cd_lot
# #             ))
# #         else:
# #             cursor.execute("""
# #                 WITH NotasCanceladas AS (
# #                     SELECT
# #                         RefID = CONCAT('NOTA|', Rcd.CdRcd, '|', ISNULL(Rco.CdVpo, 0), '|', Rco.CdObj, '|', ISNULL(Rco.CdLot, 0)),
# #                         NrRomaneio = 0,
# #                         CdVpo = ISNULL(Rco.CdVpo, 0),
# #                         CdObj = Rco.CdObj,
# #                         CdLot = ISNULL(Rco.CdLot, 0),
# #                         QtCancelada = SUM(ISNULL(Rco.QtRco, 0))
# #                     FROM TbRcd Rcd
# #                     LEFT JOIN TbRco Rco ON Rco.CdRcd = Rcd.CdRcd
# #                     WHERE Rcd.DtRcdEmi >= ?
# #                       AND Rcd.DtRcdEmi < ?
# #                       AND (
# #                             Rcd.TpRcdSta = 3
# #                             OR (Rcd.CdTop = 98 AND Rcd.TpRcdSta = 2)
# #                       )
# #                       AND Rcd.CdTop IN (97,98,378,391,598)
# #                       AND Rco.CdObj = ?
# #                       AND ISNULL(Rco.CdLot, 0) = ISNULL(?, 0)
# #                     GROUP BY
# #                         Rcd.CdRcd, Rco.CdVpo, Rco.CdObj, Rco.CdLot
# #                 ),
# #                 Alocados AS (
# #                     SELECT
# #                         RefID = CONCAT('NOTA|', ISNULL(A.NrRomaneio, 0), '|', ISNULL(A.CdVpo, 0), '|', A.CdObj, '|', ISNULL(A.CdLot, 0)),
# #                         QtAlocada = SUM(A.Quantidade)
# #                     FROM dbo.Stik_WMS_Cancelados_Alocados A WITH (NOLOCK)
# #                     WHERE A.CdObj = ?
# #                       AND ISNULL(A.CdLot, 0) = ISNULL(?, 0)
# #                       AND A.Origem = 'APP_CANCELADOS_NOTA'
# #                     GROUP BY A.NrRomaneio, A.CdVpo, A.CdObj, A.CdLot
# #                 )
# #                 SELECT
# #                     N.RefID,
# #                     N.NrRomaneio,
# #                     N.CdVpo,
# #                     N.CdObj,
# #                     N.CdLot,
# #                     N.QtCancelada,
# #                     QtAlocada = ISNULL(A.QtAlocada, 0),
# #                     QtDisponivel = N.QtCancelada - ISNULL(A.QtAlocada, 0)
# #                 FROM NotasCanceladas N
# #                 LEFT JOIN Alocados A
# #                     ON A.RefID = N.RefID
# #                 WHERE (N.QtCancelada - ISNULL(A.QtAlocada, 0)) > 0
# #                 ORDER BY N.CdVpo, N.CdObj, N.CdLot
# #             """, (
# #                 dt_ini, dt_fim, cd_obj, cd_lot,
# #                 cd_obj, cd_lot
# #             ))

# #         rows = cursor.fetchall()
# #         if not rows:
# #             return jsonify({
# #                 "error": "Nenhum saldo cancelado disponível para alocação."
# #             }), 409

# #         saldo_total = sum(float(row[7] or 0) for row in rows)
# #         if quantidade > saldo_total:
# #             return jsonify({
# #                 "error": "Quantidade excede o saldo disponível.",
# #                 "QtDisponivel": saldo_total
# #             }), 409

# #         cursor.execute("""
# #             INSERT INTO dbo.stik_WMS_Movimento
# #                 (Endereco, CodSKU, TpMov, QtMovida, Detalhe, DataMovimento)
# #             VALUES
# #                 (?, ?, 1, ?, ?, GETDATE())
# #         """, (endereco, cd_obj, quantidade, cd_lot))

# #         restante = quantidade
# #         alocacoes = []
# #         origem_gravacao = 'APP_CANCELADOS_ROMANEIO' if fonte == 'romaneios' else 'APP_CANCELADOS_NOTA'

# #         for row in rows:
# #             ref_id = str(row[0] or '')
# #             nr_romaneio = int(row[1] or 0)
# #             cd_vpo = int(row[2] or 0)
# #             row_cd_obj = int(row[3] or 0)
# #             row_cd_lot = int(row[4] or 0)
# #             qt_disponivel = float(row[7] or 0)

# #             if restante <= 0:
# #                 break

# #             qt_alocar = min(restante, qt_disponivel)
# #             if qt_alocar <= 0:
# #                 continue

# #             cursor.execute("""
# #                 INSERT INTO dbo.Stik_WMS_Cancelados_Alocados
# #                     (NrRomaneio, CdVpo, CdObj, CdLot, Endereco, Quantidade, CdUsr, Origem, DtAlocacao)
# #                 VALUES
# #                     (?, ?, ?, ?, ?, ?, ?, ?, GETDATE())
# #             """, (
# #                 nr_romaneio, cd_vpo, row_cd_obj, row_cd_lot,
# #                 endereco, qt_alocar, cd_usr, origem_gravacao
# #             ))

# #             alocacoes.append({
# #                 "RefID": ref_id,
# #                 "NrRomaneio": nr_romaneio,
# #                 "CdVpo": cd_vpo,
# #                 "CdObj": row_cd_obj,
# #                 "CdLot": row_cd_lot,
# #                 "Quantidade": qt_alocar
# #             })

# #             restante -= qt_alocar

# #         if restante > 0.0001:
# #             connection.rollback()
# #             return jsonify({
# #                 "error": "Falha ao distribuir toda a quantidade."
# #             }), 409

# #         connection.commit()

# #         return jsonify({
# #             "success": True,
# #             "message": "Alocação realizada com sucesso.",
# #             "Fonte": fonte,
# #             "Endereco": endereco,
# #             "CdObj": cd_obj,
# #             "CdLot": cd_lot,
# #             "Quantidade": quantidade,
# #             "alocacoes": alocacoes
# #         }), 201

# #     except Exception as e:
# #         if connection:
# #             try:
# #                 connection.rollback()
# #             except Exception:
# #                 pass
# #         return jsonify({"error": str(e)}), 500
# #     finally:
# #         if connection:
# #             connection.close()


# # @wms_cancelados_bp.route('/consulta/wms/alocar_embalagem', methods=['POST'])
# # def alocar_embalagem():
# #     connection = None
# #     try:
# #         data = request.get_json() or {}

# #         endereco = (data.get('endereco') or '').strip().upper()
# #         cod_sku = data.get('cod_sku')
# #         detalhe = data.get('detalhe', 0)
# #         artigo_payload = (data.get('artigo') or '').strip()
# #         quantidade = data.get('quantidade')
# #         cd_usr = data.get('cd_usr')
# #         origem = (data.get('origem') or 'CANCELADOS').strip().upper()

# #         qt_caixa_p = data.get('qt_caixa_p', 0)
# #         qt_caixa_g = data.get('qt_caixa_g', 0)
# #         qt_enfestado = data.get('qt_enfestado', 0)
# #         qt_enfraldado = data.get('qt_enfraldado', 0)

# #         if not endereco or cod_sku is None or quantidade is None:
# #             return jsonify({
# #                 "error": "Campos obrigatórios: endereco, cod_sku, quantidade"
# #             }), 400

# #         try:
# #             cod_sku = int(cod_sku)
# #             detalhe = int(detalhe or 0)
# #             quantidade = float(str(quantidade).replace(',', '.'))
# #             cd_usr = int(cd_usr) if cd_usr not in (None, '', '0', 0) else None
# #             qt_caixa_p = int(qt_caixa_p or 0)
# #             qt_caixa_g = int(qt_caixa_g or 0)
# #             qt_enfestado = int(qt_enfestado or 0)
# #             qt_enfraldado = int(qt_enfraldado or 0)
# #         except (TypeError, ValueError):
# #             return jsonify({"error": "Parâmetros inválidos"}), 400

# #         if quantidade <= 0:
# #             return jsonify({"error": "Quantidade deve ser maior que zero"}), 400

# #         if min(qt_caixa_p, qt_caixa_g, qt_enfestado, qt_enfraldado) < 0:
# #             return jsonify({"error": "Quantidades de embalagem não podem ser negativas"}), 400

# #         if qt_caixa_p == 0 and qt_caixa_g == 0 and qt_enfestado == 0 and qt_enfraldado == 0:
# #             return jsonify({
# #                 "success": True,
# #                 "message": "Nenhuma embalagem informada. Nada a registrar."
# #             }), 200

# #         artigo_oficial = _resolver_artigo_oficial_por_sku(cod_sku)
# #         artigo_origem = artigo_oficial or artigo_payload
# #         artigo_consulta = _extrair_artigo_base(artigo_origem)

# #         if not artigo_consulta:
# #             return jsonify({
# #                 "error": f"Não foi possível resolver o artigo base para o SKU {cod_sku}."
# #             }), 404

# #         row = _buscar_padrao_embalagem_por_artigo(artigo_consulta)
# #         if not row:
# #             return jsonify({
# #                 "error": f"Padrão de embalagem não encontrado para o SKU {cod_sku} / artigo base '{artigo_consulta}'."
# #             }), 404

# #         metros_caixa_p = float(row.get('caixa_p') or 0)
# #         metros_caixa_g = float(row.get('caixa_g') or 0)
# #         metros_enfestado = float(row.get('enfestado') or 0)
# #         metros_enfraldado = float(row.get('enfraldado') or 0)

# #         metros_embalagens = (
# #             (qt_caixa_p * metros_caixa_p) +
# #             (qt_caixa_g * metros_caixa_g) +
# #             (qt_enfestado * metros_enfestado) +
# #             (qt_enfraldado * metros_enfraldado)
# #         )

# #         if abs(metros_embalagens - quantidade) > 0.0001:
# #             return jsonify({
# #                 "error": "A metragem calculada das embalagens difere da quantidade enviada.",
# #                 "QtInformada": quantidade,
# #                 "QtEmbalagensMetro": metros_embalagens
# #             }), 409

# #         connection = create_connection_tinturaria()
# #         if connection is None:
# #             return jsonify({
# #                 "status": "SQL_ERROR",
# #                 "details": "Falha ao conectar ao banco."
# #             }), 500

# #         cursor = connection.cursor()
# #         cursor.execute("SET NOCOUNT ON; SET XACT_ABORT ON;")

# #         cursor.execute("""
# #             IF EXISTS (
# #                 SELECT 1
# #                 FROM dbo.Stik_WMS_Alocacao_Embalagem
# #                 WHERE Endereco = ?
# #                   AND CodSKU = ?
# #                   AND ISNULL(Detalhe, 0) = ISNULL(?, 0)
# #             )
# #             BEGIN
# #                 UPDATE dbo.Stik_WMS_Alocacao_Embalagem
# #                 SET
# #                     QtCaixaP = QtCaixaP + ?,
# #                     QtCaixaG = QtCaixaG + ?,
# #                     QtEnfestado = QtEnfestado + ?,
# #                     QtEnfraldado = QtEnfraldado + ?,
# #                     DtAtualizacao = GETDATE()
# #                 WHERE Endereco = ?
# #                   AND CodSKU = ?
# #                   AND ISNULL(Detalhe, 0) = ISNULL(?, 0)
# #             END
# #             ELSE
# #             BEGIN
# #                 INSERT INTO dbo.Stik_WMS_Alocacao_Embalagem
# #                     (Endereco, CodSKU, Detalhe, QtCaixaP, QtCaixaG, QtEnfestado, QtEnfraldado, DtAtualizacao)
# #                 VALUES
# #                     (?, ?, ?, ?, ?, ?, ?, GETDATE())
# #             END
# #         """, (
# #             endereco, cod_sku, detalhe,
# #             qt_caixa_p, qt_caixa_g, qt_enfestado, qt_enfraldado,
# #             endereco, cod_sku, detalhe,
# #             endereco, cod_sku, detalhe,
# #             qt_caixa_p, qt_caixa_g, qt_enfestado, qt_enfraldado
# #         ))

# #         cursor.execute("""
# #             INSERT INTO dbo.Stik_WMS_Movimento_Embalagem
# #                 (EnderecoOrigem, EnderecoDestino, CodSKU, Detalhe, TpMov,
# #                  QtCaixaP, QtCaixaG, QtEnfestado, QtEnfraldado,
# #                  QtMovidaMetro, CdUsr, Origem, Observacao, DataMovimento)
# #             VALUES
# #                 (NULL, ?, ?, ?, 1, ?, ?, ?, ?, ?, ?, ?, 'Alocação de embalagem', GETDATE())
# #         """, (
# #             endereco,
# #             cod_sku,
# #             detalhe,
# #             qt_caixa_p,
# #             qt_caixa_g,
# #             qt_enfestado,
# #             qt_enfraldado,
# #             quantidade,
# #             cd_usr,
# #             origem
# #         ))

# #         connection.commit()

# #         return jsonify({
# #             "success": True,
# #             "message": "Embalagem alocada com sucesso.",
# #             "endereco": endereco,
# #             "cod_sku": cod_sku,
# #             "detalhe": detalhe,
# #             "artigo_base": artigo_consulta,
# #             "quantidade": quantidade,
# #             "metros_embalagens": metros_embalagens,
# #             "origem": origem
# #         }), 201

# #     except Exception as e:
# #         if connection:
# #             try:
# #                 connection.rollback()
# #             except Exception:
# #                 pass
# #         return jsonify({"error": str(e)}), 500
# #     finally:
# #         if connection:
# #             connection.close()

# import requests
# import re
# import unicodedata
# from flask import Blueprint, jsonify, request
# from database.server import create_connection_tinturaria
# import datetime
# from datetime import timedelta


# wms_cancelados_bp = Blueprint('wms_cancelados', __name__)

# # ===================================================================
# # ROTA: Cancelamento
# def _normalizar_texto(valor):
#     texto = (valor or '').strip()
#     if not texto:
#         return ''
#     texto = unicodedata.normalize('NFKD', texto)
#     texto = ''.join(ch for ch in texto if not unicodedata.combining(ch))
#     return ' '.join(texto.split()).strip()


# def _extrair_artigo_base(artigo):
#     texto = _normalizar_texto(artigo)
#     if not texto:
#         return ''

#     match = re.search(r'^(.+?\bmm)\b', texto, flags=re.IGNORECASE)
#     if match:
#         return match.group(1).strip()

#     return texto.strip()


# def _obter_token_node_api():
#     urls_login = [
#         'https://api.stiktech.com.br/auth/login',
#     ]

#     payload = {
#         'username': 'anderson',
#         'password': '142046',
#     }

#     for url in urls_login:
#         try:
#             resp = requests.post(
#                 url,
#                 json=payload,
#                 timeout=15,
#                 headers={'Content-Type': 'application/json'}
#             )
#             if resp.status_code != 200:
#                 continue

#             body = resp.json() or {}
#             token = body.get('accessToken') or body.get('token')
#             if token:
#                 return token
#         except Exception:
#             continue

#     return None


# def _resolver_artigo_oficial_por_sku(cod_sku):
#     token = _obter_token_node_api()
#     if not token:
#         return None

#     urls_artigos = [
#         'https://api.stiktech.com.br/api/artigos',
#     ]

#     for url in urls_artigos:
#         try:
#             resp = requests.get(
#                 url,
#                 params={'CdObj': cod_sku},
#                 timeout=15,
#                 headers={
#                     'Content-Type': 'application/json',
#                     'Authorization': f'Bearer {token}',
#                 }
#             )
#             if resp.status_code != 200:
#                 continue

#             payload = resp.json() or {}
#             rows = payload.get('data') or payload.get('rows') or payload.get('result') or []

#             if not isinstance(rows, list) or not rows:
#                 continue

#             for row in rows:
#                 if not isinstance(row, dict):
#                     continue

#                 artigo = str(
#                     row.get('artigo')
#                     or row.get('Artigo')
#                     or row.get('ARTIGO')
#                     or row.get('Objeto')
#                     or row.get('objeto')
#                     or row.get('NmArtigo')
#                     or ''
#                 ).strip()

#                 if artigo:
#                     return artigo
#         except Exception:
#             continue

#     return None


# def _buscar_padrao_embalagem_por_artigo(artigo):
#     urls_padrao = [
#         'https://api.stiktech.com.br/consulta/wms/padrao_caixa',
#     ]

#     artigo_normalizado = _normalizar_texto(artigo).lower()

#     for url in urls_padrao:
#         try:
#             resp = requests.get(url, timeout=15)
#             if resp.status_code != 200:
#                 continue

#             payload = resp.json() or {}
#             rows = payload.get('data') or payload.get('rows') or payload.get('result') or []

#             if not isinstance(rows, list) or not rows:
#                 continue

#             for row in rows:
#                 if not isinstance(row, dict):
#                     continue

#                 artigo_row = str(
#                     row.get('artigo')
#                     or row.get('Artigo')
#                     or row.get('ARTIGO')
#                     or row.get('Objeto')
#                     or row.get('objeto')
#                     or row.get('NmArtigo')
#                     or ''
#                 ).strip()

#                 if not artigo_row:
#                     continue

#                 artigo_row_normalizado = _normalizar_texto(artigo_row).lower()
#                 if artigo_row_normalizado == artigo_normalizado:
#                     return row

#             for row in rows:
#                 if not isinstance(row, dict):
#                     continue

#                 artigo_row = str(
#                     row.get('artigo')
#                     or row.get('Artigo')
#                     or row.get('ARTIGO')
#                     or row.get('Objeto')
#                     or row.get('objeto')
#                     or row.get('NmArtigo')
#                     or ''
#                 ).strip()

#                 if not artigo_row:
#                     continue

#                 artigo_row_normalizado = _normalizar_texto(artigo_row).lower()
#                 if artigo_normalizado in artigo_row_normalizado:
#                     return row
#         except Exception:
#             continue

#     return None

# @wms_cancelados_bp.route('/consulta/wms/cancelados/saldo', methods=['GET'])
# def saldo_item_cancelado():
#     connection = None
#     try:
#         cd_obj = request.args.get('CdObj')
#         cd_lot = request.args.get('CdLot', 0)
#         data_inicial = request.args.get('data_inicial')
#         data_final = request.args.get('data_final')

#         if cd_obj is None or not data_inicial or not data_final:
#             return jsonify({
#                 "error": "Campos obrigatórios: CdObj, data_inicial, data_final"
#             }), 400

#         try:
#             cd_obj = int(cd_obj)
#             cd_lot = int(cd_lot or 0)
#         except (TypeError, ValueError):
#             return jsonify({"error": "CdObj/CdLot inválidos"}), 400

#         connection = create_connection_tinturaria()
#         if connection is None:
#             return jsonify({
#                 "status": "SQL_ERROR",
#                 "details": "Falha ao conectar ao banco."
#             }), 500

#         cursor = connection.cursor()
#         cursor.execute("SET NOCOUNT ON;")

#         cursor.execute("""
#             WITH Cancelados AS (
#                 SELECT
#                     Fat.NrRomaneio,
#                     Fat.CdVpo,
#                     Fat.CdObj,
#                     ISNULL(Fat.CdLot, 0) AS CdLot,
#                     QtCancelada = CASE
#                         WHEN ISNULL(Fat.QtFatAtend, 0) > 0 THEN Fat.QtFatAtend
#                         ELSE Fat.QtFat
#                     END
#                 FROM dbo.Stik_Pedido_QtdFat Fat WITH (NOLOCK)
#                 WHERE Fat.TpSitFat = 11
#                   AND Fat.CdObj = ?
#                   AND ISNULL(Fat.CdLot, 0) = ISNULL(?, 0)
#                   AND CONVERT(date, Fat.DtExp) >= CONVERT(date, ?)
#                   AND CONVERT(date, Fat.DtExp) <= CONVERT(date, ?)
#             ),
#             Alocados AS (
#                 SELECT
#                     A.NrRomaneio,
#                     A.CdVpo,
#                     A.CdObj,
#                     ISNULL(A.CdLot, 0) AS CdLot,
#                     QtAlocada = SUM(A.Quantidade)
#                 FROM dbo.Stik_WMS_Cancelados_Alocados A WITH (NOLOCK)
#                 WHERE A.CdObj = ?
#                   AND ISNULL(A.CdLot, 0) = ISNULL(?, 0)
#                   AND CONVERT(date, A.DtAlocacao) >= CONVERT(date, ?)
#                   AND CONVERT(date, A.DtAlocacao) <= CONVERT(date, ?)
#                 GROUP BY
#                     A.NrRomaneio, A.CdVpo, A.CdObj, A.CdLot
#             )
#             SELECT
#                 C.NrRomaneio,
#                 C.CdVpo,
#                 C.CdObj,
#                 C.CdLot,
#                 C.QtCancelada,
#                 QtAlocada = ISNULL(A.QtAlocada, 0),
#                 QtDisponivel = C.QtCancelada - ISNULL(A.QtAlocada, 0)
#             FROM Cancelados C
#             LEFT JOIN Alocados A
#                 ON A.NrRomaneio = C.NrRomaneio
#                AND A.CdVpo = C.CdVpo
#                AND A.CdObj = C.CdObj
#                AND ISNULL(A.CdLot, 0) = ISNULL(C.CdLot, 0)
#             WHERE (C.QtCancelada - ISNULL(A.QtAlocada, 0)) > 0
#             ORDER BY C.NrRomaneio, C.CdVpo
#         """, (
#             cd_obj, cd_lot, data_inicial, data_final,
#             cd_obj, cd_lot, data_inicial, data_final
#         ))

#         rows = cursor.fetchall()
#         colunas = [c[0] for c in cursor.description]
#         itens = [dict(zip(colunas, row)) for row in rows]

#         qt_cancelada = sum(float(item['QtCancelada'] or 0) for item in itens)
#         qt_alocada = sum(float(item['QtAlocada'] or 0) for item in itens)
#         qt_disponivel = sum(float(item['QtDisponivel'] or 0) for item in itens)

#         return jsonify({
#             "CdObj": cd_obj,
#             "CdLot": cd_lot,
#             "QtCancelada": qt_cancelada,
#             "QtAlocada": qt_alocada,
#             "QtDisponivel": qt_disponivel,
#             "romaneios": itens
#         }), 200

#     except Exception as e:
#         return jsonify({"error": str(e)}), 500
#     finally:
#         if connection:
#             connection.close()

# @wms_cancelados_bp.route('/consulta/wms/cancelados/alocar', methods=['POST'])
# def alocar_item_cancelado():
#     connection = None
#     try:
#         data = request.get_json() or {}

#         endereco = (data.get('Endereco') or '').strip()
#         cd_obj = data.get('CdObj')
#         cd_lot = data.get('CdLot', 0)
#         quantidade = data.get('Quantidade')
#         data_inicial = data.get('DataInicial')
#         data_final = data.get('DataFinal')
#         cd_usr = data.get('CdUsr')
#         fonte = (data.get('Fonte') or 'romaneios').strip().lower()

#         if not endereco or cd_obj is None or quantidade is None or not data_inicial or not data_final:
#             return jsonify({
#                 "error": "Campos obrigatórios: Endereco, CdObj, Quantidade, DataInicial, DataFinal"
#             }), 400

#         if fonte not in ('romaneios', 'notas'):
#             return jsonify({
#                 "error": "Fonte inválida. Use 'romaneios' ou 'notas'."
#             }), 400

#         try:
#             cd_obj = int(cd_obj)
#             cd_lot = int(cd_lot or 0)
#             quantidade = float(str(quantidade).replace(',', '.'))
#             cd_usr = int(cd_usr) if cd_usr not in (None, '', '0', 0) else None
#             #dt_ini = datetime.strptime(data_inicial, '%Y-%m-%d')
#             #dt_fim = datetime.strptime(data_final, '%Y-%m-%d') + timedelta(days=1)
#             dt_ini = datetime.datetime.strptime(data_inicial, '%Y-%m-%d')
#             dt_fim = datetime.datetime.strptime(data_final, '%Y-%m-%d') + timedelta(days=1)


#         except (TypeError, ValueError):
#             return jsonify({
#                 "error": "CdObj/CdLot/Quantidade/CdUsr/DataInicial/DataFinal inválidos"
#             }), 400

#         if quantidade <= 0:
#             return jsonify({"error": "Quantidade deve ser maior que zero"}), 400

#         connection = create_connection_tinturaria()
#         if connection is None:
#             return jsonify({
#                 "status": "SQL_ERROR",
#                 "details": "Falha ao conectar ao banco."
#             }), 500

#         cursor = connection.cursor()
#         cursor.execute("SET NOCOUNT ON; SET XACT_ABORT ON;")

#         if fonte == 'romaneios':
#             cursor.execute("""
#                 WITH Cancelados AS (
#                     SELECT
#                         RefID = CONCAT('ROM|', Fat.NrRomaneio, '|', Fat.CdVpo),
#                         Fat.NrRomaneio,
#                         Fat.CdVpo,
#                         Fat.CdObj,
#                         ISNULL(Fat.CdLot, 0) AS CdLot,
#                         QtCancelada = CASE
#                             WHEN ISNULL(Fat.QtFatAtend, 0) > 0 THEN Fat.QtFatAtend
#                             ELSE Fat.QtFat
#                         END
#                     FROM dbo.Stik_Pedido_QtdFat Fat WITH (UPDLOCK, HOLDLOCK)
#                     WHERE Fat.TpSitFat = 11
#                       AND Fat.CdObj = ?
#                       AND ISNULL(Fat.CdLot, 0) = ISNULL(?, 0)
#                       AND Fat.DtExp >= ?
#                       AND Fat.DtExp < ?
#                 ),
#                 Alocados AS (
#                     SELECT
#                         RefID = CONCAT('ROM|', A.NrRomaneio, '|', A.CdVpo),
#                         QtAlocada = SUM(A.Quantidade)
#                     FROM dbo.Stik_WMS_Cancelados_Alocados A WITH (NOLOCK)
#                     WHERE A.CdObj = ?
#                       AND ISNULL(A.CdLot, 0) = ISNULL(?, 0)
#                       AND A.Origem = 'APP_CANCELADOS_ROMANEIO'
#                     GROUP BY A.NrRomaneio, A.CdVpo
#                 )
#                 SELECT
#                     C.RefID,
#                     C.NrRomaneio,
#                     C.CdVpo,
#                     C.CdObj,
#                     C.CdLot,
#                     C.QtCancelada,
#                     QtAlocada = ISNULL(A.QtAlocada, 0),
#                     QtDisponivel = C.QtCancelada - ISNULL(A.QtAlocada, 0)
#                 FROM Cancelados C
#                 LEFT JOIN Alocados A
#                     ON A.RefID = C.RefID
#                 WHERE (C.QtCancelada - ISNULL(A.QtAlocada, 0)) > 0
#                 ORDER BY C.NrRomaneio, C.CdVpo
#             """, (
#                 cd_obj, cd_lot, dt_ini, dt_fim,
#                 cd_obj, cd_lot
#             ))
#         else:
#             cursor.execute("""
#                 WITH NotasCanceladas AS (
#                     SELECT
#                         RefID = CONCAT('NOTA|', Rcd.CdRcd, '|', ISNULL(Rco.CdVpo, 0), '|', Rco.CdObj, '|', ISNULL(Rco.CdLot, 0)),
#                         NrRomaneio = 0,
#                         CdVpo = ISNULL(Rco.CdVpo, 0),
#                         CdObj = Rco.CdObj,
#                         CdLot = ISNULL(Rco.CdLot, 0),
#                         QtCancelada = SUM(ISNULL(Rco.QtRco, 0))
#                     FROM TbRcd Rcd
#                     LEFT JOIN TbRco Rco ON Rco.CdRcd = Rcd.CdRcd
#                     WHERE Rcd.DtRcdEmi >= ?
#                       AND Rcd.DtRcdEmi < ?
#                       AND (
#                             Rcd.TpRcdSta = 3
#                             OR (Rcd.CdTop = 98 AND Rcd.TpRcdSta = 2)
#                       )
#                       AND Rcd.CdTop IN (97,98,378,391,598)
#                       AND Rco.CdObj = ?
#                       AND ISNULL(Rco.CdLot, 0) = ISNULL(?, 0)
#                     GROUP BY
#                         Rcd.CdRcd, Rco.CdVpo, Rco.CdObj, Rco.CdLot
#                 ),
#                 Alocados AS (
#                     SELECT
#                         RefID = CONCAT('NOTA|', ISNULL(A.NrRomaneio, 0), '|', ISNULL(A.CdVpo, 0), '|', A.CdObj, '|', ISNULL(A.CdLot, 0)),
#                         QtAlocada = SUM(A.Quantidade)
#                     FROM dbo.Stik_WMS_Cancelados_Alocados A WITH (NOLOCK)
#                     WHERE A.CdObj = ?
#                       AND ISNULL(A.CdLot, 0) = ISNULL(?, 0)
#                       AND A.Origem = 'APP_CANCELADOS_NOTA'
#                     GROUP BY A.NrRomaneio, A.CdVpo, A.CdObj, A.CdLot
#                 )
#                 SELECT
#                     N.RefID,
#                     N.NrRomaneio,
#                     N.CdVpo,
#                     N.CdObj,
#                     N.CdLot,
#                     N.QtCancelada,
#                     QtAlocada = ISNULL(A.QtAlocada, 0),
#                     QtDisponivel = N.QtCancelada - ISNULL(A.QtAlocada, 0)
#                 FROM NotasCanceladas N
#                 LEFT JOIN Alocados A
#                     ON A.RefID = N.RefID
#                 WHERE (N.QtCancelada - ISNULL(A.QtAlocada, 0)) > 0
#                 ORDER BY N.CdVpo, N.CdObj, N.CdLot
#             """, (
#                 dt_ini, dt_fim, cd_obj, cd_lot,
#                 cd_obj, cd_lot
#             ))

#         rows = cursor.fetchall()
#         if not rows:
#             return jsonify({
#                 "error": "Nenhum saldo cancelado disponível para alocação."
#             }), 409

#         saldo_total = sum(float(row[7] or 0) for row in rows)
#         if quantidade > saldo_total:
#             return jsonify({
#                 "error": "Quantidade excede o saldo disponível.",
#                 "QtDisponivel": saldo_total
#             }), 409

#         cursor.execute("""
#             INSERT INTO dbo.stik_WMS_Movimento
#                 (Endereco, CodSKU, TpMov, QtMovida, Detalhe, DataMovimento)
#             VALUES
#                 (?, ?, 1, ?, ?, GETDATE())
#         """, (endereco, cd_obj, quantidade, cd_lot))

#         restante = quantidade
#         alocacoes = []
#         origem_gravacao = 'APP_CANCELADOS_ROMANEIO' if fonte == 'romaneios' else 'APP_CANCELADOS_NOTA'

#         for row in rows:
#             ref_id = str(row[0] or '')
#             nr_romaneio = int(row[1] or 0)
#             cd_vpo = int(row[2] or 0)
#             row_cd_obj = int(row[3] or 0)
#             row_cd_lot = int(row[4] or 0)
#             qt_disponivel = float(row[7] or 0)

#             if restante <= 0:
#                 break

#             qt_alocar = min(restante, qt_disponivel)
#             if qt_alocar <= 0:
#                 continue

#             cursor.execute("""
#                 INSERT INTO dbo.Stik_WMS_Cancelados_Alocados
#                     (NrRomaneio, CdVpo, CdObj, CdLot, Endereco, Quantidade, CdUsr, Origem, DtAlocacao)
#                 VALUES
#                     (?, ?, ?, ?, ?, ?, ?, ?, GETDATE())
#             """, (
#                 nr_romaneio, cd_vpo, row_cd_obj, row_cd_lot,
#                 endereco, qt_alocar, cd_usr, origem_gravacao
#             ))

#             alocacoes.append({
#                 "RefID": ref_id,
#                 "NrRomaneio": nr_romaneio,
#                 "CdVpo": cd_vpo,
#                 "CdObj": row_cd_obj,
#                 "CdLot": row_cd_lot,
#                 "Quantidade": qt_alocar
#             })

#             restante -= qt_alocar

#         if restante > 0.0001:
#             connection.rollback()
#             return jsonify({
#                 "error": "Falha ao distribuir toda a quantidade."
#             }), 409

#         connection.commit()

#         return jsonify({
#             "success": True,
#             "message": "Alocação realizada com sucesso.",
#             "Fonte": fonte,
#             "Endereco": endereco,
#             "CdObj": cd_obj,
#             "CdLot": cd_lot,
#             "Quantidade": quantidade,
#             "alocacoes": alocacoes
#         }), 201

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


# @wms_cancelados_bp.route('/consulta/wms/alocar_embalagem', methods=['POST'])
# def alocar_embalagem():
#     connection = None
#     try:
#         data = request.get_json() or {}

#         endereco = (data.get('endereco') or '').strip().upper()
#         cod_sku = data.get('cod_sku')
#         detalhe = data.get('detalhe', 0)
#         artigo_payload = (data.get('artigo') or '').strip()
#         quantidade = data.get('quantidade')
#         cd_usr = data.get('cd_usr')
#         origem = (data.get('origem') or 'CANCELADOS').strip().upper()

#         qt_caixa_p = data.get('qt_caixa_p', 0)
#         qt_caixa_g = data.get('qt_caixa_g', 0)
#         qt_enfestado = data.get('qt_enfestado', 0)
#         qt_enfraldado = data.get('qt_enfraldado', 0)

#         if not endereco or cod_sku is None or quantidade is None:
#             return jsonify({
#                 "error": "Campos obrigatórios: endereco, cod_sku, quantidade"
#             }), 400

#         try:
#             cod_sku = int(cod_sku)
#             detalhe = int(detalhe or 0)
#             quantidade = float(str(quantidade).replace(',', '.'))
#             cd_usr = int(cd_usr) if cd_usr not in (None, '', '0', 0) else None
#             qt_caixa_p = int(qt_caixa_p or 0)
#             qt_caixa_g = int(qt_caixa_g or 0)
#             qt_enfestado = int(qt_enfestado or 0)
#             qt_enfraldado = int(qt_enfraldado or 0)
#         except (TypeError, ValueError):
#             return jsonify({"error": "Parâmetros inválidos"}), 400

#         if quantidade <= 0:
#             return jsonify({"error": "Quantidade deve ser maior que zero"}), 400

#         if min(qt_caixa_p, qt_caixa_g, qt_enfestado, qt_enfraldado) < 0:
#             return jsonify({"error": "Quantidades de embalagem não podem ser negativas"}), 400

#         if qt_caixa_p == 0 and qt_caixa_g == 0 and qt_enfestado == 0 and qt_enfraldado == 0:
#             return jsonify({
#                 "success": True,
#                 "message": "Nenhuma embalagem informada. Nada a registrar."
#             }), 200

#         artigo_oficial = _resolver_artigo_oficial_por_sku(cod_sku)
#         artigo_origem = artigo_oficial or artigo_payload
#         artigo_consulta = _extrair_artigo_base(artigo_origem)

#         if not artigo_consulta:
#             return jsonify({
#                 "error": f"Não foi possível resolver o artigo base para o SKU {cod_sku}."
#             }), 404

#         row = _buscar_padrao_embalagem_por_artigo(artigo_consulta)
#         if not row:
#             return jsonify({
#                 "error": f"Padrão de embalagem não encontrado para o SKU {cod_sku} / artigo base '{artigo_consulta}'."
#             }), 404

#         metros_caixa_p = float(row.get('caixa_p') or 0)
#         metros_caixa_g = float(row.get('caixa_g') or 0)
#         metros_enfestado = float(row.get('enfestado') or 0)
#         metros_enfraldado = float(row.get('enfraldado') or 0)

#         metros_embalagens = (
#             (qt_caixa_p * metros_caixa_p) +
#             (qt_caixa_g * metros_caixa_g) +
#             (qt_enfestado * metros_enfestado) +
#             (qt_enfraldado * metros_enfraldado)
#         )

#         if abs(metros_embalagens - quantidade) > 0.0001:
#             return jsonify({
#                 "error": "A metragem calculada das embalagens difere da quantidade enviada.",
#                 "QtInformada": quantidade,
#                 "QtEmbalagensMetro": metros_embalagens
#             }), 409

#         connection = create_connection_tinturaria()
#         if connection is None:
#             return jsonify({
#                 "status": "SQL_ERROR",
#                 "details": "Falha ao conectar ao banco."
#             }), 500

#         cursor = connection.cursor()
#         cursor.execute("SET NOCOUNT ON; SET XACT_ABORT ON;")

#         cursor.execute("""
#             IF EXISTS (
#                 SELECT 1
#                 FROM dbo.Stik_WMS_Alocacao_Embalagem
#                 WHERE Endereco = ?
#                   AND CodSKU = ?
#                   AND ISNULL(Detalhe, 0) = ISNULL(?, 0)
#             )
#             BEGIN
#                 UPDATE dbo.Stik_WMS_Alocacao_Embalagem
#                 SET
#                     QtCaixaP = QtCaixaP + ?,
#                     QtCaixaG = QtCaixaG + ?,
#                     QtEnfestado = QtEnfestado + ?,
#                     QtEnfraldado = QtEnfraldado + ?,
#                     DtAtualizacao = GETDATE()
#                 WHERE Endereco = ?
#                   AND CodSKU = ?
#                   AND ISNULL(Detalhe, 0) = ISNULL(?, 0)
#             END
#             ELSE
#             BEGIN
#                 INSERT INTO dbo.Stik_WMS_Alocacao_Embalagem
#                     (Endereco, CodSKU, Detalhe, QtCaixaP, QtCaixaG, QtEnfestado, QtEnfraldado, DtAtualizacao)
#                 VALUES
#                     (?, ?, ?, ?, ?, ?, ?, GETDATE())
#             END
#         """, (
#             endereco, cod_sku, detalhe,
#             qt_caixa_p, qt_caixa_g, qt_enfestado, qt_enfraldado,
#             endereco, cod_sku, detalhe,
#             endereco, cod_sku, detalhe,
#             qt_caixa_p, qt_caixa_g, qt_enfestado, qt_enfraldado
#         ))

#         cursor.execute("""
#             INSERT INTO dbo.Stik_WMS_Movimento_Embalagem
#                 (EnderecoOrigem, EnderecoDestino, CodSKU, Detalhe, TpMov,
#                  QtCaixaP, QtCaixaG, QtEnfestado, QtEnfraldado,
#                  QtMovidaMetro, CdUsr, Origem, Observacao, DataMovimento)
#             VALUES
#                 (NULL, ?, ?, ?, 1, ?, ?, ?, ?, ?, ?, ?, 'Alocação de embalagem', GETDATE())
#         """, (
#             endereco,
#             cod_sku,
#             detalhe,
#             qt_caixa_p,
#             qt_caixa_g,
#             qt_enfestado,
#             qt_enfraldado,
#             quantidade,
#             cd_usr,
#             origem
#         ))

#         connection.commit()

#         return jsonify({
#             "success": True,
#             "message": "Embalagem alocada com sucesso.",
#             "endereco": endereco,
#             "cod_sku": cod_sku,
#             "detalhe": detalhe,
#             "artigo_base": artigo_consulta,
#             "quantidade": quantidade,
#             "metros_embalagens": metros_embalagens,
#             "origem": origem
#         }), 201

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


import requests
import re
import unicodedata
from flask import Blueprint, jsonify, request
from database.server import create_connection_tinturaria
import datetime
from datetime import timedelta


wms_cancelados_bp = Blueprint('wms_cancelados', __name__)

# ===================================================================
# ROTA: Cancelamento
def _normalizar_texto(valor):
    texto = (valor or '').strip()
    if not texto:
        return ''
    texto = unicodedata.normalize('NFKD', texto)
    texto = ''.join(ch for ch in texto if not unicodedata.combining(ch))
    return ' '.join(texto.split()).strip()


def _extrair_artigo_base(artigo):
    texto = _normalizar_texto(artigo)
    if not texto:
        return ''

    match = re.search(r'^(.+?\bmm)\b', texto, flags=re.IGNORECASE)
    if match:
        return match.group(1).strip()

    return texto.strip()


def _obter_token_node_api():
    urls_login = [
        'https://api.stiktech.com.br/auth/login',
    ]

    payload = {
        'username': 'anderson',
        'password': '142046',
    }

    for url in urls_login:
        try:
            resp = requests.post(
                url,
                json=payload,
                timeout=15,
                headers={'Content-Type': 'application/json'}
            )
            if resp.status_code != 200:
                continue

            body = resp.json() or {}
            token = body.get('accessToken') or body.get('token')
            if token:
                return token
        except Exception:
            continue

    return None


def _resolver_artigo_oficial_por_sku(cod_sku):
    token = _obter_token_node_api()
    if not token:
        return None

    urls_artigos = [
        'https://api.stiktech.com.br/api/artigos',
    ]

    for url in urls_artigos:
        try:
            resp = requests.get(
                url,
                params={'CdObj': cod_sku},
                timeout=15,
                headers={
                    'Content-Type': 'application/json',
                    'Authorization': f'Bearer {token}',
                }
            )
            if resp.status_code != 200:
                continue

            payload = resp.json() or {}
            rows = payload.get('data') or payload.get('rows') or payload.get('result') or []

            if not isinstance(rows, list) or not rows:
                continue

            for row in rows:
                if not isinstance(row, dict):
                    continue

                artigo = str(
                    row.get('artigo')
                    or row.get('Artigo')
                    or row.get('ARTIGO')
                    or row.get('Objeto')
                    or row.get('objeto')
                    or row.get('NmArtigo')
                    or ''
                ).strip()

                if artigo:
                    return artigo
        except Exception:
            continue

    return None


def _buscar_padrao_embalagem_por_artigo(artigo):
    urls_padrao = [
        'https://api.stiktech.com.br/consulta/wms/padrao_caixa',
    ]

    artigo_normalizado = _normalizar_texto(artigo).lower()

    for url in urls_padrao:
        try:
            resp = requests.get(url, timeout=15)
            if resp.status_code != 200:
                continue

            payload = resp.json() or {}
            rows = payload.get('data') or payload.get('rows') or payload.get('result') or []

            if not isinstance(rows, list) or not rows:
                continue

            for row in rows:
                if not isinstance(row, dict):
                    continue

                artigo_row = str(
                    row.get('artigo')
                    or row.get('Artigo')
                    or row.get('ARTIGO')
                    or row.get('Objeto')
                    or row.get('objeto')
                    or row.get('NmArtigo')
                    or ''
                ).strip()

                if not artigo_row:
                    continue

                artigo_row_normalizado = _normalizar_texto(artigo_row).lower()
                if artigo_row_normalizado == artigo_normalizado:
                    return row

            for row in rows:
                if not isinstance(row, dict):
                    continue

                artigo_row = str(
                    row.get('artigo')
                    or row.get('Artigo')
                    or row.get('ARTIGO')
                    or row.get('Objeto')
                    or row.get('objeto')
                    or row.get('NmArtigo')
                    or ''
                ).strip()

                if not artigo_row:
                    continue

                artigo_row_normalizado = _normalizar_texto(artigo_row).lower()
                if artigo_normalizado in artigo_row_normalizado:
                    return row
        except Exception:
            continue

    return None

@wms_cancelados_bp.route('/consulta/wms/cancelados/saldo', methods=['GET'])
def saldo_item_cancelado():
    connection = None
    try:
        cd_obj = request.args.get('CdObj')
        cd_lot = request.args.get('CdLot', 0)
        data_inicial = request.args.get('data_inicial')
        data_final = request.args.get('data_final')

        if cd_obj is None or not data_inicial or not data_final:
            return jsonify({
                "error": "Campos obrigatórios: CdObj, data_inicial, data_final"
            }), 400

        try:
            cd_obj = int(cd_obj)
            cd_lot = int(cd_lot or 0)
        except (TypeError, ValueError):
            return jsonify({"error": "CdObj/CdLot inválidos"}), 400

        connection = create_connection_tinturaria()
        if connection is None:
            return jsonify({
                "status": "SQL_ERROR",
                "details": "Falha ao conectar ao banco."
            }), 500

        cursor = connection.cursor()
        cursor.execute("SET NOCOUNT ON;")

        cursor.execute("""
            WITH Cancelados AS (
                SELECT
                    Fat.NrRomaneio,
                    Fat.CdVpo,
                    Fat.CdObj,
                    ISNULL(Fat.CdLot, 0) AS CdLot,
                    QtCancelada = CASE
                        WHEN ISNULL(Fat.QtFatAtend, 0) > 0 THEN Fat.QtFatAtend
                        ELSE Fat.QtFat
                    END
                FROM dbo.Stik_Pedido_QtdFat Fat WITH (NOLOCK)
                WHERE Fat.TpSitFat = 11
                  AND Fat.CdObj = ?
                  AND ISNULL(Fat.CdLot, 0) = ISNULL(?, 0)
                  AND CONVERT(date, Fat.DtExp) >= CONVERT(date, ?)
                  AND CONVERT(date, Fat.DtExp) <= CONVERT(date, ?)
            ),
            Alocados AS (
                SELECT
                    A.NrRomaneio,
                    A.CdVpo,
                    A.CdObj,
                    ISNULL(A.CdLot, 0) AS CdLot,
                    QtAlocada = SUM(A.Quantidade)
                FROM dbo.Stik_WMS_Cancelados_Alocados A WITH (NOLOCK)
                WHERE A.CdObj = ?
                  AND ISNULL(A.CdLot, 0) = ISNULL(?, 0)
                  AND CONVERT(date, A.DtAlocacao) >= CONVERT(date, ?)
                  AND CONVERT(date, A.DtAlocacao) <= CONVERT(date, ?)
                GROUP BY
                    A.NrRomaneio, A.CdVpo, A.CdObj, A.CdLot
            )
            SELECT
                C.NrRomaneio,
                C.CdVpo,
                C.CdObj,
                C.CdLot,
                C.QtCancelada,
                QtAlocada = ISNULL(A.QtAlocada, 0),
                QtDisponivel = C.QtCancelada - ISNULL(A.QtAlocada, 0)
            FROM Cancelados C
            LEFT JOIN Alocados A
                ON A.NrRomaneio = C.NrRomaneio
               AND A.CdVpo = C.CdVpo
               AND A.CdObj = C.CdObj
               AND ISNULL(A.CdLot, 0) = ISNULL(C.CdLot, 0)
            WHERE (C.QtCancelada - ISNULL(A.QtAlocada, 0)) > 0
            ORDER BY C.NrRomaneio, C.CdVpo
        """, (
            cd_obj, cd_lot, data_inicial, data_final,
            cd_obj, cd_lot, data_inicial, data_final
        ))

        rows = cursor.fetchall()
        colunas = [c[0] for c in cursor.description]
        itens = [dict(zip(colunas, row)) for row in rows]

        qt_cancelada = sum(float(item['QtCancelada'] or 0) for item in itens)
        qt_alocada = sum(float(item['QtAlocada'] or 0) for item in itens)
        qt_disponivel = sum(float(item['QtDisponivel'] or 0) for item in itens)

        return jsonify({
            "CdObj": cd_obj,
            "CdLot": cd_lot,
            "QtCancelada": qt_cancelada,
            "QtAlocada": qt_alocada,
            "QtDisponivel": qt_disponivel,
            "romaneios": itens
        }), 200

    except Exception as e:
        return jsonify({"error": str(e)}), 500
    finally:
        if connection:
            connection.close()

@wms_cancelados_bp.route('/consulta/wms/cancelados/alocar', methods=['POST'])
def alocar_item_cancelado():
    connection = None
    try:
        data = request.get_json() or {}

        endereco = (data.get('Endereco') or '').strip()
        cd_obj = data.get('CdObj')
        cd_lot = data.get('CdLot', 0)
        quantidade = data.get('Quantidade')
        data_inicial = data.get('DataInicial')
        data_final = data.get('DataFinal')
        cd_usr = data.get('CdUsr')
        fonte = (data.get('Fonte') or 'romaneios').strip().lower()

        if not endereco or cd_obj is None or quantidade is None or not data_inicial or not data_final:
            return jsonify({
                "error": "Campos obrigatórios: Endereco, CdObj, Quantidade, DataInicial, DataFinal"
            }), 400

        if fonte not in ('romaneios', 'notas'):
            return jsonify({
                "error": "Fonte inválida. Use 'romaneios' ou 'notas'."
            }), 400

        try:
            cd_obj = int(cd_obj)
            cd_lot = int(cd_lot or 0)
            quantidade = float(str(quantidade).replace(',', '.'))
            cd_usr = int(cd_usr) if cd_usr not in (None, '', '0', 0) else None
            #dt_ini = datetime.strptime(data_inicial, '%Y-%m-%d')
            #dt_fim = datetime.strptime(data_final, '%Y-%m-%d') + timedelta(days=1)
            dt_ini = datetime.datetime.strptime(data_inicial, '%Y-%m-%d')
            dt_fim = datetime.datetime.strptime(data_final, '%Y-%m-%d') + timedelta(days=1)


        except (TypeError, ValueError):
            return jsonify({
                "error": "CdObj/CdLot/Quantidade/CdUsr/DataInicial/DataFinal inválidos"
            }), 400

        if quantidade <= 0:
            return jsonify({"error": "Quantidade deve ser maior que zero"}), 400

        connection = create_connection_tinturaria()
        if connection is None:
            return jsonify({
                "status": "SQL_ERROR",
                "details": "Falha ao conectar ao banco."
            }), 500

        # Força transação explícita: sem isso, se a conexão vier em
        # autocommit, cada INSERT do loop abaixo grava sozinho e o
        # connection.rollback() no fim não desfaz nada (achado em produção:
        # romaneio 132576 ficou com saldo "alocado" numa tentativa que
        # deveria ter falhado por completo). Também é o que faz o
        # UPDLOCK/HOLDLOCK da query abaixo realmente segurar o lock até o
        # fim, evitando duas requisições concorrentes alocarem o mesmo saldo.
        connection.autocommit = False

        cursor = connection.cursor()
        cursor.execute("SET NOCOUNT ON; SET XACT_ABORT ON;")

        if fonte == 'romaneios':
            cursor.execute("""
                WITH Cancelados AS (
                    SELECT
                        RefID = CONCAT('ROM|', Fat.NrRomaneio, '|', Fat.CdVpo),
                        Fat.NrRomaneio,
                        Fat.CdVpo,
                        Fat.CdObj,
                        ISNULL(Fat.CdLot, 0) AS CdLot,
                        QtCancelada = CASE
                            WHEN ISNULL(Fat.QtFatAtend, 0) > 0 THEN Fat.QtFatAtend
                            ELSE Fat.QtFat
                        END
                    FROM dbo.Stik_Pedido_QtdFat Fat WITH (UPDLOCK, HOLDLOCK)
                    WHERE Fat.TpSitFat = 11
                      AND Fat.CdObj = ?
                      AND ISNULL(Fat.CdLot, 0) = ISNULL(?, 0)
                      AND Fat.DtExp >= ?
                      AND Fat.DtExp < ?
                ),
                Alocados AS (
                    SELECT
                        RefID = CONCAT('ROM|', A.NrRomaneio, '|', A.CdVpo),
                        QtAlocada = SUM(A.Quantidade)
                    FROM dbo.Stik_WMS_Cancelados_Alocados A WITH (NOLOCK)
                    WHERE A.CdObj = ?
                      AND ISNULL(A.CdLot, 0) = ISNULL(?, 0)
                      AND A.Origem = 'APP_CANCELADOS_ROMANEIO'
                    GROUP BY A.NrRomaneio, A.CdVpo
                )
                SELECT
                    C.RefID,
                    C.NrRomaneio,
                    C.CdVpo,
                    C.CdObj,
                    C.CdLot,
                    C.QtCancelada,
                    QtAlocada = ISNULL(A.QtAlocada, 0),
                    QtDisponivel = C.QtCancelada - ISNULL(A.QtAlocada, 0)
                FROM Cancelados C
                LEFT JOIN Alocados A
                    ON A.RefID = C.RefID
                WHERE (C.QtCancelada - ISNULL(A.QtAlocada, 0)) > 0
                ORDER BY C.NrRomaneio, C.CdVpo
            """, (
                cd_obj, cd_lot, dt_ini, dt_fim,
                cd_obj, cd_lot
            ))
        else:
            cursor.execute("""
                WITH NotasCanceladas AS (
                    SELECT
                        RefID = CONCAT('NOTA|', Rcd.CdRcd, '|', ISNULL(Rco.CdVpo, 0), '|', Rco.CdObj, '|', ISNULL(Rco.CdLot, 0)),
                        NrRomaneio = 0,
                        CdVpo = ISNULL(Rco.CdVpo, 0),
                        CdObj = Rco.CdObj,
                        CdLot = ISNULL(Rco.CdLot, 0),
                        QtCancelada = SUM(ISNULL(Rco.QtRco, 0))
                    FROM TbRcd Rcd
                    LEFT JOIN TbRco Rco ON Rco.CdRcd = Rcd.CdRcd
                    WHERE Rcd.DtRcdEmi >= ?
                      AND Rcd.DtRcdEmi < ?
                      AND (
                            Rcd.TpRcdSta = 3
                            OR (Rcd.CdTop = 98 AND Rcd.TpRcdSta = 2)
                      )
                      AND Rcd.CdTop IN (97,98,378,391,598)
                      AND Rco.CdObj = ?
                      AND ISNULL(Rco.CdLot, 0) = ISNULL(?, 0)
                    GROUP BY
                        Rcd.CdRcd, Rco.CdVpo, Rco.CdObj, Rco.CdLot
                ),
                Alocados AS (
                    SELECT
                        RefID = CONCAT('NOTA|', ISNULL(A.NrRomaneio, 0), '|', ISNULL(A.CdVpo, 0), '|', A.CdObj, '|', ISNULL(A.CdLot, 0)),
                        QtAlocada = SUM(A.Quantidade)
                    FROM dbo.Stik_WMS_Cancelados_Alocados A WITH (NOLOCK)
                    WHERE A.CdObj = ?
                      AND ISNULL(A.CdLot, 0) = ISNULL(?, 0)
                      AND A.Origem = 'APP_CANCELADOS_NOTA'
                    GROUP BY A.NrRomaneio, A.CdVpo, A.CdObj, A.CdLot
                )
                SELECT
                    N.RefID,
                    N.NrRomaneio,
                    N.CdVpo,
                    N.CdObj,
                    N.CdLot,
                    N.QtCancelada,
                    QtAlocada = ISNULL(A.QtAlocada, 0),
                    QtDisponivel = N.QtCancelada - ISNULL(A.QtAlocada, 0)
                FROM NotasCanceladas N
                LEFT JOIN Alocados A
                    ON A.RefID = N.RefID
                WHERE (N.QtCancelada - ISNULL(A.QtAlocada, 0)) > 0
                ORDER BY N.CdVpo, N.CdObj, N.CdLot
            """, (
                dt_ini, dt_fim, cd_obj, cd_lot,
                cd_obj, cd_lot
            ))

        rows = cursor.fetchall()
        if not rows:
            return jsonify({
                "error": "Nenhum saldo cancelado disponível para alocação."
            }), 409

        saldo_total = sum(float(row[7] or 0) for row in rows)
        if quantidade > saldo_total:
            return jsonify({
                "error": "Quantidade excede o saldo disponível.",
                "QtDisponivel": saldo_total
            }), 409

        cursor.execute("""
            INSERT INTO dbo.stik_WMS_Movimento
                (Endereco, CodSKU, TpMov, QtMovida, Detalhe, DataMovimento)
            VALUES
                (?, ?, 1, ?, ?, GETDATE())
        """, (endereco, cd_obj, quantidade, cd_lot))

        restante = quantidade
        alocacoes = []
        origem_gravacao = 'APP_CANCELADOS_ROMANEIO' if fonte == 'romaneios' else 'APP_CANCELADOS_NOTA'

        for row in rows:
            ref_id = str(row[0] or '')
            nr_romaneio = int(row[1] or 0)
            cd_vpo = int(row[2] or 0)
            row_cd_obj = int(row[3] or 0)
            row_cd_lot = int(row[4] or 0)
            qt_disponivel = float(row[7] or 0)

            if restante <= 0:
                break

            qt_alocar = min(restante, qt_disponivel)
            if qt_alocar <= 0:
                continue

            cursor.execute("""
                INSERT INTO dbo.Stik_WMS_Cancelados_Alocados
                    (NrRomaneio, CdVpo, CdObj, CdLot, Endereco, Quantidade, CdUsr, Origem, DtAlocacao)
                VALUES
                    (?, ?, ?, ?, ?, ?, ?, ?, GETDATE())
            """, (
                nr_romaneio, cd_vpo, row_cd_obj, row_cd_lot,
                endereco, qt_alocar, cd_usr, origem_gravacao
            ))

            alocacoes.append({
                "RefID": ref_id,
                "NrRomaneio": nr_romaneio,
                "CdVpo": cd_vpo,
                "CdObj": row_cd_obj,
                "CdLot": row_cd_lot,
                "Quantidade": qt_alocar
            })

            restante -= qt_alocar

        if restante > 0.0001:
            connection.rollback()
            return jsonify({
                "error": "Falha ao distribuir toda a quantidade."
            }), 409

        connection.commit()

        return jsonify({
            "success": True,
            "message": "Alocação realizada com sucesso.",
            "Fonte": fonte,
            "Endereco": endereco,
            "CdObj": cd_obj,
            "CdLot": cd_lot,
            "Quantidade": quantidade,
            "alocacoes": alocacoes
        }), 201

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


@wms_cancelados_bp.route('/consulta/wms/alocar_embalagem', methods=['POST'])
def alocar_embalagem():
    connection = None
    try:
        data = request.get_json() or {}

        endereco = (data.get('endereco') or '').strip().upper()
        cod_sku = data.get('cod_sku')
        detalhe = data.get('detalhe', 0)
        artigo_payload = (data.get('artigo') or '').strip()
        quantidade = data.get('quantidade')
        cd_usr = data.get('cd_usr')
        origem = (data.get('origem') or 'CANCELADOS').strip().upper()

        qt_caixa_p = data.get('qt_caixa_p', 0)
        qt_caixa_g = data.get('qt_caixa_g', 0)
        qt_enfestado = data.get('qt_enfestado', 0)
        qt_enfraldado = data.get('qt_enfraldado', 0)

        if not endereco or cod_sku is None or quantidade is None:
            return jsonify({
                "error": "Campos obrigatórios: endereco, cod_sku, quantidade"
            }), 400

        try:
            cod_sku = int(cod_sku)
            detalhe = int(detalhe or 0)
            quantidade = float(str(quantidade).replace(',', '.'))
            cd_usr = int(cd_usr) if cd_usr not in (None, '', '0', 0) else None
            qt_caixa_p = int(qt_caixa_p or 0)
            qt_caixa_g = int(qt_caixa_g or 0)
            qt_enfestado = int(qt_enfestado or 0)
            qt_enfraldado = int(qt_enfraldado or 0)
        except (TypeError, ValueError):
            return jsonify({"error": "Parâmetros inválidos"}), 400

        if quantidade <= 0:
            return jsonify({"error": "Quantidade deve ser maior que zero"}), 400

        if min(qt_caixa_p, qt_caixa_g, qt_enfestado, qt_enfraldado) < 0:
            return jsonify({"error": "Quantidades de embalagem não podem ser negativas"}), 400

        if qt_caixa_p == 0 and qt_caixa_g == 0 and qt_enfestado == 0 and qt_enfraldado == 0:
            return jsonify({
                "success": True,
                "message": "Nenhuma embalagem informada. Nada a registrar."
            }), 200

        artigo_oficial = _resolver_artigo_oficial_por_sku(cod_sku)
        artigo_origem = artigo_oficial or artigo_payload
        artigo_consulta = _extrair_artigo_base(artigo_origem)

        if not artigo_consulta:
            return jsonify({
                "error": f"Não foi possível resolver o artigo base para o SKU {cod_sku}."
            }), 404

        row = _buscar_padrao_embalagem_por_artigo(artigo_consulta)
        if not row:
            return jsonify({
                "error": f"Padrão de embalagem não encontrado para o SKU {cod_sku} / artigo base '{artigo_consulta}'."
            }), 404

        metros_caixa_p = float(row.get('caixa_p') or 0)
        metros_caixa_g = float(row.get('caixa_g') or 0)
        metros_enfestado = float(row.get('enfestado') or 0)
        metros_enfraldado = float(row.get('enfraldado') or 0)

        metros_embalagens = (
            (qt_caixa_p * metros_caixa_p) +
            (qt_caixa_g * metros_caixa_g) +
            (qt_enfestado * metros_enfestado) +
            (qt_enfraldado * metros_enfraldado)
        )

        if abs(metros_embalagens - quantidade) > 0.0001:
            return jsonify({
                "error": "A metragem calculada das embalagens difere da quantidade enviada.",
                "QtInformada": quantidade,
                "QtEmbalagensMetro": metros_embalagens
            }), 409

        connection = create_connection_tinturaria()
        if connection is None:
            return jsonify({
                "status": "SQL_ERROR",
                "details": "Falha ao conectar ao banco."
            }), 500

        # Mesma correção do /alocar: sem isso, o UPDATE/INSERT em
        # Stik_WMS_Alocacao_Embalagem e o INSERT em
        # Stik_WMS_Movimento_Embalagem podem ser autocommitados
        # separadamente, deixando os dois fora de sincronia se algo falhar
        # entre um e outro.
        connection.autocommit = False

        cursor = connection.cursor()
        cursor.execute("SET NOCOUNT ON; SET XACT_ABORT ON;")

        cursor.execute("""
            IF EXISTS (
                SELECT 1
                FROM dbo.Stik_WMS_Alocacao_Embalagem
                WHERE Endereco = ?
                  AND CodSKU = ?
                  AND ISNULL(Detalhe, 0) = ISNULL(?, 0)
            )
            BEGIN
                UPDATE dbo.Stik_WMS_Alocacao_Embalagem
                SET
                    QtCaixaP = QtCaixaP + ?,
                    QtCaixaG = QtCaixaG + ?,
                    QtEnfestado = QtEnfestado + ?,
                    QtEnfraldado = QtEnfraldado + ?,
                    DtAtualizacao = GETDATE()
                WHERE Endereco = ?
                  AND CodSKU = ?
                  AND ISNULL(Detalhe, 0) = ISNULL(?, 0)
            END
            ELSE
            BEGIN
                INSERT INTO dbo.Stik_WMS_Alocacao_Embalagem
                    (Endereco, CodSKU, Detalhe, QtCaixaP, QtCaixaG, QtEnfestado, QtEnfraldado, DtAtualizacao)
                VALUES
                    (?, ?, ?, ?, ?, ?, ?, GETDATE())
            END
        """, (
            endereco, cod_sku, detalhe,
            qt_caixa_p, qt_caixa_g, qt_enfestado, qt_enfraldado,
            endereco, cod_sku, detalhe,
            endereco, cod_sku, detalhe,
            qt_caixa_p, qt_caixa_g, qt_enfestado, qt_enfraldado
        ))

        cursor.execute("""
            INSERT INTO dbo.Stik_WMS_Movimento_Embalagem
                (EnderecoOrigem, EnderecoDestino, CodSKU, Detalhe, TpMov,
                 QtCaixaP, QtCaixaG, QtEnfestado, QtEnfraldado,
                 QtMovidaMetro, CdUsr, Origem, Observacao, DataMovimento)
            VALUES
                (NULL, ?, ?, ?, 1, ?, ?, ?, ?, ?, ?, ?, 'Alocação de embalagem', GETDATE())
        """, (
            endereco,
            cod_sku,
            detalhe,
            qt_caixa_p,
            qt_caixa_g,
            qt_enfestado,
            qt_enfraldado,
            quantidade,
            cd_usr,
            origem
        ))

        connection.commit()

        return jsonify({
            "success": True,
            "message": "Embalagem alocada com sucesso.",
            "endereco": endereco,
            "cod_sku": cod_sku,
            "detalhe": detalhe,
            "artigo_base": artigo_consulta,
            "quantidade": quantidade,
            "metros_embalagens": metros_embalagens,
            "origem": origem
        }), 201

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
