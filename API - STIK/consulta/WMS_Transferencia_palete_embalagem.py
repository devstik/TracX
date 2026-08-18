import requests
import re
from flask import Blueprint, jsonify, request
from database.server import create_connection_tinturaria 
import datetime 

wms_transferencia_embalagem_bp = Blueprint('transferencia_embalagem', __name__)


@wms_transferencia_embalagem_bp.route('/consulta/wms/transferir_palete_embalagem', methods=['POST'])
def transferir_palete_embalagem():
    connection = None
    try:
        data = request.get_json() or {}

        endereco_origem = (data.get('endereco_origem') or '').strip().upper()
        endereco_destino = (data.get('endereco_destino') or '').strip().upper()
        cod_sku = data.get('cod_sku')
        detalhe = data.get('detalhe', 0)
        artigo = (data.get('artigo') or '').strip()
        quantidade = data.get('quantidade')
        cd_usr = data.get('cd_usr')

        qt_caixa_p = data.get('qt_caixa_p', 0)
        qt_caixa_g = data.get('qt_caixa_g', 0)
        qt_enfestado = data.get('qt_enfestado', 0)
        qt_enfraldado = data.get('qt_enfraldado', 0)

        if not endereco_origem or not endereco_destino or cod_sku is None or quantidade is None or not artigo:
            return jsonify({
                "error": "Campos obrigatórios: endereco_origem, endereco_destino, cod_sku, artigo, quantidade"
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

        if endereco_origem == endereco_destino:
            return jsonify({"error": "Origem e destino não podem ser iguais."}), 400

        if min(qt_caixa_p, qt_caixa_g, qt_enfestado, qt_enfraldado) < 0:
            return jsonify({"error": "Quantidades de embalagem não podem ser negativas"}), 400

        if qt_caixa_p == 0 and qt_caixa_g == 0 and qt_enfestado == 0 and qt_enfraldado == 0:
            return jsonify({
                "success": True,
                "message": "Nenhuma embalagem informada. Nada a registrar."
            }), 200

        connection = create_connection_tinturaria()
        if connection is None:
            return jsonify({
                "status": "SQL_ERROR",
                "details": "Falha ao conectar ao banco."
            }), 500

        cursor = connection.cursor()
        cursor.execute("SET NOCOUNT ON; SET XACT_ABORT ON;")

        row = None
        origem_padrao = None
        erro_endpoint = None

        try:
            resp = requests.get(
                'https://api.stiktech.com.br/consulta/wms/stik_padrao_caixa',
                params={'artigo': artigo},
                timeout=10
            )

            if resp.status_code == 200:
                try:
                    payload_padrao = resp.json() or {}

                    rows = (
                        payload_padrao.get('data')
                        or payload_padrao.get('rows')
                        or payload_padrao.get('result')
                        or []
                    )

                    if rows:
                        row = rows[0] or {}
                        origem_padrao = "ENDPOINT"
                    else:
                        erro_endpoint = f"Endpoint não retornou padrão para o artigo '{artigo}'."

                except Exception as e:
                    erro_endpoint = f"Erro ao interpretar JSON do endpoint: {str(e)}"

            else:
                erro_endpoint = f"Endpoint retornou HTTP {resp.status_code}"

        except Exception as e:
            erro_endpoint = f"Falha ao consultar endpoint: {str(e)}"

        if not row:
            cursor.execute("""
                SELECT TOP 1
                    artigo,
                    caixa_p,
                    enfestado,
                    enfraldado,
                    caixa_g,
                    disco
                FROM dbo.Stik_PadraoCaixa WITH (NOLOCK)
                WHERE UPPER(LTRIM(RTRIM(artigo))) = UPPER(LTRIM(RTRIM(?)))
            """, (artigo,))

            row_sql = cursor.fetchone()

            if row_sql:
                row = {
                    "artigo": row_sql[0],
                    "caixa_p": row_sql[1],
                    "enfestado": row_sql[2],
                    "enfraldado": row_sql[3],
                    "caixa_g": row_sql[4],
                    "disco": row_sql[5]
                }
                origem_padrao = "BANCO"

        if not row:
            return jsonify({
                "error": f"Padrão de embalagem não encontrado para o artigo '{artigo}'.",
                "erro_endpoint": erro_endpoint,
                "fallback_sql": "SELECT * FROM dbo.Stik_PadraoCaixa"
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

        if metros_embalagens > quantidade + 0.0001:
            return jsonify({
                "error": "A metragem das embalagens excede a quantidade transferida.",
                "QtTransferida": quantidade,
                "QtEmbalagensMetro": metros_embalagens,
                "origem_padrao": origem_padrao
            }), 409

        cursor.execute("""
            WITH Base AS (
                SELECT
                    QtInicial = ISNULL(SUM(ISNULL(A.QtAlocada, 0)), 0)
                FROM dbo.Stik_WMS_Alocacao A WITH (NOLOCK)
                WHERE UPPER(LTRIM(RTRIM(A.Endereco))) = ?
                AND A.CodSKU = ?
                AND ISNULL(A.Detalhe, 0) = ISNULL(?, 0)
            ),
            Mov AS (
                SELECT
                    QtEntrada = ISNULL(SUM(CASE WHEN M.TpMov = 1 THEN ISNULL(M.QtMovida, 0) ELSE 0 END), 0),
                    QtSaida = ISNULL(SUM(CASE WHEN M.TpMov = 2 THEN ISNULL(M.QtMovida, 0) ELSE 0 END), 0),
                    QtRetorno = ISNULL(SUM(CASE WHEN M.TpMov = 3 THEN ISNULL(M.QtMovida, 0) ELSE 0 END), 0)
                FROM dbo.Stik_WMS_Movimento M WITH (NOLOCK)
                WHERE UPPER(LTRIM(RTRIM(M.Endereco))) = ?
                AND M.CodSKU = ?
                AND ISNULL(M.Detalhe, 0) = ISNULL(?, 0)
            )
            SELECT
                QtSaldoFinal =
                    ISNULL((SELECT QtInicial FROM Base), 0)
                    + ISNULL((SELECT QtEntrada FROM Mov), 0)
                    + ISNULL((SELECT QtRetorno FROM Mov), 0)
                    - ISNULL((SELECT QtSaida FROM Mov), 0)
        """, (
            endereco_origem, cod_sku, detalhe,
            endereco_origem, cod_sku, detalhe
        ))

        row_saldo = cursor.fetchone()
        saldo_item_origem = float((row_saldo[0] if row_saldo else 0) or 0)

        if saldo_item_origem <= 0:
            return jsonify({
                "error": "Item sem saldo disponível no palete de origem.",
                "QtSaldoOrigem": saldo_item_origem
            }), 409

        cursor.execute("""
            SELECT
                ISNULL(QtCaixaP, 0),
                ISNULL(QtCaixaG, 0),
                ISNULL(QtEnfestado, 0),
                ISNULL(QtEnfraldado, 0)
            FROM dbo.Stik_WMS_Alocacao_Embalagem WITH (UPDLOCK, HOLDLOCK)
            WHERE UPPER(LTRIM(RTRIM(Endereco))) = ?
              AND CodSKU = ?
              AND ISNULL(Detalhe, 0) = ISNULL(?, 0)
        """, (endereco_origem, cod_sku, detalhe))

        row_emb_origem = cursor.fetchone()

        saldo_caixa_p = int((row_emb_origem[0] if row_emb_origem else 0) or 0)
        saldo_caixa_g = int((row_emb_origem[1] if row_emb_origem else 0) or 0)
        saldo_enfestado = int((row_emb_origem[2] if row_emb_origem else 0) or 0)
        saldo_enfraldado = int((row_emb_origem[3] if row_emb_origem else 0) or 0)

        novo_saldo_origem_p = max(saldo_caixa_p - qt_caixa_p, 0)
        novo_saldo_origem_g = max(saldo_caixa_g - qt_caixa_g, 0)
        novo_saldo_origem_enfestado = max(saldo_enfestado - qt_enfestado, 0)
        novo_saldo_origem_enfraldado = max(saldo_enfraldado - qt_enfraldado, 0)

        if row_emb_origem:
            cursor.execute("""
                UPDATE dbo.Stik_WMS_Alocacao_Embalagem
                SET
                    QtCaixaP = ?,
                    QtCaixaG = ?,
                    QtEnfestado = ?,
                    QtEnfraldado = ?,
                    DtAtualizacao = GETDATE()
                WHERE UPPER(LTRIM(RTRIM(Endereco))) = ?
                  AND CodSKU = ?
                  AND ISNULL(Detalhe, 0) = ISNULL(?, 0)
            """, (
                novo_saldo_origem_p,
                novo_saldo_origem_g,
                novo_saldo_origem_enfestado,
                novo_saldo_origem_enfraldado,
                endereco_origem,
                cod_sku,
                detalhe
            ))

            cursor.execute("""
                DELETE FROM dbo.Stik_WMS_Alocacao_Embalagem
                WHERE UPPER(LTRIM(RTRIM(Endereco))) = ?
                  AND CodSKU = ?
                  AND ISNULL(Detalhe, 0) = ISNULL(?, 0)
                  AND ISNULL(QtCaixaP, 0) = 0
                  AND ISNULL(QtCaixaG, 0) = 0
                  AND ISNULL(QtEnfestado, 0) = 0
                  AND ISNULL(QtEnfraldado, 0) = 0
            """, (
                endereco_origem,
                cod_sku,
                detalhe
            ))

        cursor.execute("""
            IF EXISTS (
                SELECT 1
                FROM dbo.Stik_WMS_Alocacao_Embalagem
                WHERE UPPER(LTRIM(RTRIM(Endereco))) = ?
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
                WHERE UPPER(LTRIM(RTRIM(Endereco))) = ?
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
            endereco_destino, cod_sku, detalhe,
            qt_caixa_p, qt_caixa_g, qt_enfestado, qt_enfraldado,
            endereco_destino, cod_sku, detalhe,
            endereco_destino, cod_sku, detalhe,
            qt_caixa_p, qt_caixa_g, qt_enfestado, qt_enfraldado
        ))

        cursor.execute("""
            INSERT INTO dbo.Stik_WMS_Movimento_Embalagem
                (EnderecoOrigem, EnderecoDestino, CodSKU, Detalhe, TpMov,
                 QtCaixaP, QtCaixaG, QtEnfestado, QtEnfraldado,
                 QtMovidaMetro, CdUsr, Origem, Observacao, DataMovimento)
            VALUES
                (?, NULL, ?, ?, 2, ?, ?, ?, ?, ?, ?, 'TRANSFERENCIA', 'Saída de embalagem', GETDATE())
        """, (
            endereco_origem,
            cod_sku,
            detalhe,
            qt_caixa_p,
            qt_caixa_g,
            qt_enfestado,
            qt_enfraldado,
            quantidade,
            cd_usr
        ))

        cursor.execute("""
            INSERT INTO dbo.Stik_WMS_Movimento_Embalagem
                (EnderecoOrigem, EnderecoDestino, CodSKU, Detalhe, TpMov,
                 QtCaixaP, QtCaixaG, QtEnfestado, QtEnfraldado,
                 QtMovidaMetro, CdUsr, Origem, Observacao, DataMovimento)
            VALUES
                (NULL, ?, ?, ?, 1, ?, ?, ?, ?, ?, ?, 'TRANSFERENCIA', 'Entrada de embalagem', GETDATE())
        """, (
            endereco_destino,
            cod_sku,
            detalhe,
            qt_caixa_p,
            qt_caixa_g,
            qt_enfestado,
            qt_enfraldado,
            quantidade,
            cd_usr
        ))

        connection.commit()

        return jsonify({
            "success": True,
            "message": "Embalagens da transferência registradas com sucesso.",
            "endereco_origem": endereco_origem,
            "endereco_destino": endereco_destino,
            "cod_sku": cod_sku,
            "detalhe": detalhe,
            "quantidade": quantidade,
            "metros_embalagens": metros_embalagens,
            "QtSaldoOrigem": saldo_item_origem,
            "origem_padrao": origem_padrao
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

@wms_transferencia_embalagem_bp.route('/consulta/wms/alocar_embalagem', methods=['POST'])
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

# @wms_transferencia_embalagem_bp.route('/consulta/wms/saida_embalagem', methods=['POST'])
# def saida_embalagem():
#     connection = None
#     try:
#         data = request.get_json() or {}
#         endereco = (data.get('endereco') or '').strip().upper()
#         cod_sku = int(data.get('cod_sku'))
#         detalhe = int(data.get('detalhe') or 0)
#         artigo = (data.get('artigo') or '').strip()
#         qt_p = int(data.get('qt_caixa_p') or 0)
#         qt_g = int(data.get('qt_caixa_g') or 0)
#         qt_enfe = int(data.get('qt_enfestado') or 0)
#         qt_enfr = int(data.get('qt_enfraldado') or 0)
#         cd_usr = data.get('cd_usr')
#         cd_usr = int(cd_usr) if cd_usr not in (None, '', 0, '0') else None

#         if not endereco or cod_sku <= 0:
#             return jsonify({"error": "Campos obrigatórios: endereco, cod_sku"}), 400
#         if min(qt_p, qt_g, qt_enfe, qt_enfr) < 0:
#             return jsonify({"error": "Quantidades inválidas"}), 400
#         if qt_p + qt_g + qt_enfe + qt_enfr <= 0:
#             return jsonify({"error": "Nenhuma embalagem para sair"}), 400

#         connection = create_connection_tinturaria()
#         cursor = connection.cursor()
#         cursor.execute("SET NOCOUNT ON; SET XACT_ABORT ON;")

#         # saldo atual
#         cursor.execute("""
#             SELECT
#                 QtCaixaP = ISNULL(QtCaixaP,0),
#                 QtCaixaG = ISNULL(QtCaixaG,0),
#                 QtEnfestado = ISNULL(QtEnfestado,0),
#                 QtEnfraldado = ISNULL(QtEnfraldado,0)
#             FROM dbo.Stik_WMS_Alocacao_Embalagem WITH (UPDLOCK, HOLDLOCK)
#             WHERE UPPER(LTRIM(RTRIM(Endereco))) = ?
#               AND CodSKU = ?
#               AND ISNULL(Detalhe,0) = ISNULL(?,0)
#         """, (endereco, cod_sku, detalhe))
#         row = cursor.fetchone()
#         saldo_p, saldo_g, saldo_enfe, saldo_enfr = (
#             int(row[0] if row else 0),
#             int(row[1] if row else 0),
#             int(row[2] if row else 0),
#             int(row[3] if row else 0),
#         )

#         print(
#         f"[SAIDA_EMBALAGEM] end={endereco} sku={cod_sku} detalhe={detalhe} "
#         f"req P={qt_p} G={qt_g} ENFE={qt_enfe} ENFR={qt_enfr} | "
#         f"saldo P={saldo_p} G={saldo_g} ENFE={saldo_enfe} ENFR={saldo_enfr} | "
#         f"row_exists={'SIM' if row else 'NAO'}"
# )


#         def falta(nec, disp): return nec > disp
#         if (falta(qt_p, saldo_p) or falta(qt_g, saldo_g) or
#             falta(qt_enfe, saldo_enfe) or falta(qt_enfr, saldo_enfr)):
#             return jsonify({"error": "Embalagem insuficiente no palete."}), 409

#         novo_p = saldo_p - qt_p
#         novo_g = saldo_g - qt_g
#         novo_enfe = saldo_enfe - qt_enfe
#         novo_enfr = saldo_enfr - qt_enfr

#         # atualiza saldo
#         if row:
#             cursor.execute("""
#                 UPDATE dbo.Stik_WMS_Alocacao_Embalagem
#                 SET QtCaixaP = ?, QtCaixaG = ?, QtEnfestado = ?, QtEnfraldado = ?, DtAtualizacao = GETDATE()
#                 WHERE UPPER(LTRIM(RTRIM(Endereco))) = ?
#                   AND CodSKU = ?
#                   AND ISNULL(Detalhe,0) = ISNULL(?,0)
#             """, (novo_p, novo_g, novo_enfe, novo_enfr, endereco, cod_sku, detalhe))
#         else:
#             cursor.execute("""
#                 INSERT INTO dbo.Stik_WMS_Alocacao_Embalagem
#                     (Endereco, CodSKU, Detalhe, QtCaixaP, QtCaixaG, QtEnfestado, QtEnfraldado, DtAtualizacao)
#                 VALUES (?, ?, ?, ?, ?, ?, ?, GETDATE())
#             """, (endereco, cod_sku, detalhe, novo_p, novo_g, novo_enfe, novo_enfr))

#         # limpa linha zerada
#         cursor.execute("""
#             DELETE FROM dbo.Stik_WMS_Alocacao_Embalagem
#             WHERE UPPER(LTRIM(RTRIM(Endereco))) = ?
#               AND CodSKU = ?
#               AND ISNULL(Detalhe,0) = ISNULL(?,0)
#               AND ISNULL(QtCaixaP,0)=0 AND ISNULL(QtCaixaG,0)=0
#               AND ISNULL(QtEnfestado,0)=0 AND ISNULL(QtEnfraldado,0)=0
#         """, (endereco, cod_sku, detalhe))

#         # movimento TpMov = 2 (saída)
#         cursor.execute("""
#             INSERT INTO dbo.Stik_WMS_Movimento_Embalagem
#                 (EnderecoOrigem, EnderecoDestino, CodSKU, Detalhe, TpMov,
#                  QtCaixaP, QtCaixaG, QtEnfestado, QtEnfraldado,
#                  QtMovidaMetro, CdUsr, Origem, Observacao, DataMovimento)
#             VALUES
#                 (?, NULL, ?, ?, 2, ?, ?, ?, ?, 0, ?, 'SEPARACAO', 'Saída de embalagem (separação)', GETDATE())
#         """, (
#             endereco, cod_sku, detalhe,
#             qt_p, qt_g, qt_enfe, qt_enfr,
#             cd_usr
#         ))

#         connection.commit()
#         return jsonify({"success": True}), 200

#     except Exception as e:
#         if connection:
#             try: connection.rollback()
#             except Exception: pass
#         return jsonify({"error": str(e)}), 500
#     finally:
#         if connection:
#             connection.close()

@wms_transferencia_embalagem_bp.route('/consulta/wms/saida_embalagem', methods=['POST'])
def saida_embalagem():
    connection = None
    try:
        data = request.get_json() or {}

        endereco = (data.get('endereco') or '').strip().upper()
        cod_sku = int(data.get('cod_sku'))
        detalhe = int(data.get('detalhe') or 0)
        artigo = (data.get('artigo') or '').strip()
        qt_p = int(data.get('qt_caixa_p') or 0)
        qt_g = int(data.get('qt_caixa_g') or 0)
        qt_enfe = int(data.get('qt_enfestado') or 0)
        qt_enfr = int(data.get('qt_enfraldado') or 0)
        cd_usr = data.get('cd_usr')
        cd_usr = int(cd_usr) if cd_usr not in (None, '', 0, '0') else None

        if not endereco or cod_sku <= 0:
            return jsonify({"error": "Campos obrigatórios: endereco, cod_sku"}), 400
        if min(qt_p, qt_g, qt_enfe, qt_enfr) < 0:
            return jsonify({"error": "Quantidades inválidas"}), 400
        if qt_p + qt_g + qt_enfe + qt_enfr <= 0:
            return jsonify({"error": "Nenhuma embalagem para sair"}), 400

        connection = create_connection_tinturaria()
        if connection is None:
            return jsonify({"error": "Falha ao conectar ao banco."}), 500

        cursor = connection.cursor()
        cursor.execute("SET NOCOUNT ON; SET XACT_ABORT ON;")

        cursor.execute("""
            SELECT
                QtCaixaP = ISNULL(QtCaixaP,0),
                QtCaixaG = ISNULL(QtCaixaG,0),
                QtEnfestado = ISNULL(QtEnfestado,0),
                QtEnfraldado = ISNULL(QtEnfraldado,0)
            FROM dbo.Stik_WMS_Alocacao_Embalagem WITH (UPDLOCK, HOLDLOCK)
            WHERE UPPER(LTRIM(RTRIM(Endereco))) = ?
              AND CodSKU = ?
              AND ISNULL(Detalhe,0) = ISNULL(?,0)
        """, (endereco, cod_sku, detalhe))
        row = cursor.fetchone()

        if not row:
            cursor.execute("""
                ;WITH UltimoAjuste AS (
                    SELECT TOP 1
                        M.QtCaixaP,
                        M.QtCaixaG,
                        M.QtEnfestado,
                        M.QtEnfraldado,
                        M.DataMovimento
                    FROM dbo.Stik_WMS_Movimento_Embalagem M WITH (NOLOCK)
                    WHERE UPPER(LTRIM(RTRIM(ISNULL(M.EnderecoOrigem, '')))) = ?
                      AND M.CodSKU = ?
                      AND ISNULL(M.Detalhe,0) = ISNULL(?,0)
                      AND M.TpMov = 4
                    ORDER BY M.DataMovimento DESC, M.ID DESC
                ),
                MovPosterior AS (
                    SELECT
                        QtCaixaP = ISNULL(SUM(
                            CASE
                                WHEN UPPER(LTRIM(RTRIM(ISNULL(M.EnderecoDestino, '')))) = ? THEN ISNULL(M.QtCaixaP,0)
                                WHEN UPPER(LTRIM(RTRIM(ISNULL(M.EnderecoOrigem, '')))) = ? THEN -ISNULL(M.QtCaixaP,0)
                                ELSE 0
                            END
                        ), 0),
                        QtCaixaG = ISNULL(SUM(
                            CASE
                                WHEN UPPER(LTRIM(RTRIM(ISNULL(M.EnderecoDestino, '')))) = ? THEN ISNULL(M.QtCaixaG,0)
                                WHEN UPPER(LTRIM(RTRIM(ISNULL(M.EnderecoOrigem, '')))) = ? THEN -ISNULL(M.QtCaixaG,0)
                                ELSE 0
                            END
                        ), 0),
                        QtEnfestado = ISNULL(SUM(
                            CASE
                                WHEN UPPER(LTRIM(RTRIM(ISNULL(M.EnderecoDestino, '')))) = ? THEN ISNULL(M.QtEnfestado,0)
                                WHEN UPPER(LTRIM(RTRIM(ISNULL(M.EnderecoOrigem, '')))) = ? THEN -ISNULL(M.QtEnfestado,0)
                                ELSE 0
                            END
                        ), 0),
                        QtEnfraldado = ISNULL(SUM(
                            CASE
                                WHEN UPPER(LTRIM(RTRIM(ISNULL(M.EnderecoDestino, '')))) = ? THEN ISNULL(M.QtEnfraldado,0)
                                WHEN UPPER(LTRIM(RTRIM(ISNULL(M.EnderecoOrigem, '')))) = ? THEN -ISNULL(M.QtEnfraldado,0)
                                ELSE 0
                            END
                        ), 0)
                    FROM dbo.Stik_WMS_Movimento_Embalagem M WITH (NOLOCK)
                    CROSS JOIN UltimoAjuste UA
                    WHERE M.CodSKU = ?
                      AND ISNULL(M.Detalhe,0) = ISNULL(?,0)
                      AND M.TpMov <> 4
                      AND M.DataMovimento > UA.DataMovimento
                      AND (
                            UPPER(LTRIM(RTRIM(ISNULL(M.EnderecoDestino, '')))) = ?
                         OR UPPER(LTRIM(RTRIM(ISNULL(M.EnderecoOrigem, '')))) = ?
                      )
                )
                SELECT TOP 1
                    QtCaixaP = CASE WHEN UA.QtCaixaP + MP.QtCaixaP < 0 THEN 0 ELSE UA.QtCaixaP + MP.QtCaixaP END,
                    QtCaixaG = CASE WHEN UA.QtCaixaG + MP.QtCaixaG < 0 THEN 0 ELSE UA.QtCaixaG + MP.QtCaixaG END,
                    QtEnfestado = CASE WHEN UA.QtEnfestado + MP.QtEnfestado < 0 THEN 0 ELSE UA.QtEnfestado + MP.QtEnfestado END,
                    QtEnfraldado = CASE WHEN UA.QtEnfraldado + MP.QtEnfraldado < 0 THEN 0 ELSE UA.QtEnfraldado + MP.QtEnfraldado END
                FROM UltimoAjuste UA
                CROSS JOIN MovPosterior MP
            """, (
                endereco, cod_sku, detalhe,
                endereco, endereco,
                endereco, endereco,
                endereco, endereco,
                endereco, endereco,
                cod_sku, detalhe,
                endereco, endereco
            ))
            row_rebuild = cursor.fetchone()

            if row_rebuild:
                saldo_p = int(row_rebuild[0] or 0)
                saldo_g = int(row_rebuild[1] or 0)
                saldo_enfe = int(row_rebuild[2] or 0)
                saldo_enfr = int(row_rebuild[3] or 0)

                if saldo_p > 0 or saldo_g > 0 or saldo_enfe > 0 or saldo_enfr > 0:
                    cursor.execute("""
                        INSERT INTO dbo.Stik_WMS_Alocacao_Embalagem
                            (Endereco, CodSKU, Detalhe, QtCaixaP, QtCaixaG, QtEnfestado, QtEnfraldado, DtAtualizacao)
                        VALUES (?, ?, ?, ?, ?, ?, ?, GETDATE())
                    """, (
                        endereco, cod_sku, detalhe,
                        saldo_p, saldo_g, saldo_enfe, saldo_enfr
                    ))
                    row = (saldo_p, saldo_g, saldo_enfe, saldo_enfr)

        saldo_p, saldo_g, saldo_enfe, saldo_enfr = (
            int(row[0] if row else 0),
            int(row[1] if row else 0),
            int(row[2] if row else 0),
            int(row[3] if row else 0),
        )

        print(
            f"[SAIDA_EMBALAGEM] end={endereco} sku={cod_sku} detalhe={detalhe} "
            f"req P={qt_p} G={qt_g} ENFE={qt_enfe} ENFR={qt_enfr} | "
            f"saldo P={saldo_p} G={saldo_g} ENFE={saldo_enfe} ENFR={saldo_enfr} | "
            f"row_exists={'SIM' if row else 'NAO'}"
        )

        def falta(nec, disp):
            return nec > disp

        if (falta(qt_p, saldo_p) or falta(qt_g, saldo_g) or
            falta(qt_enfe, saldo_enfe) or falta(qt_enfr, saldo_enfr)):
            return jsonify({"error": "Embalagem insuficiente no palete."}), 409

        novo_p = saldo_p - qt_p
        novo_g = saldo_g - qt_g
        novo_enfe = saldo_enfe - qt_enfe
        novo_enfr = saldo_enfr - qt_enfr

        cursor.execute("""
            UPDATE dbo.Stik_WMS_Alocacao_Embalagem
            SET QtCaixaP = ?, QtCaixaG = ?, QtEnfestado = ?, QtEnfraldado = ?, DtAtualizacao = GETDATE()
            WHERE UPPER(LTRIM(RTRIM(Endereco))) = ?
              AND CodSKU = ?
              AND ISNULL(Detalhe,0) = ISNULL(?,0)
        """, (
            novo_p, novo_g, novo_enfe, novo_enfr,
            endereco, cod_sku, detalhe
        ))

        cursor.execute("""
            DELETE FROM dbo.Stik_WMS_Alocacao_Embalagem
            WHERE UPPER(LTRIM(RTRIM(Endereco))) = ?
              AND CodSKU = ?
              AND ISNULL(Detalhe,0) = ISNULL(?,0)
              AND ISNULL(QtCaixaP,0)=0
              AND ISNULL(QtCaixaG,0)=0
              AND ISNULL(QtEnfestado,0)=0
              AND ISNULL(QtEnfraldado,0)=0
        """, (endereco, cod_sku, detalhe))

        cursor.execute("""
            INSERT INTO dbo.Stik_WMS_Movimento_Embalagem
                (EnderecoOrigem, EnderecoDestino, CodSKU, Detalhe, TpMov,
                 QtCaixaP, QtCaixaG, QtEnfestado, QtEnfraldado,
                 QtMovidaMetro, CdUsr, Origem, Observacao, DataMovimento)
            VALUES
                (?, NULL, ?, ?, 2, ?, ?, ?, ?, 0, ?, 'SEPARACAO', 'Saída de embalagem (separação)', GETDATE())
        """, (
            endereco, cod_sku, detalhe,
            qt_p, qt_g, qt_enfe, qt_enfr,
            cd_usr
        ))

        connection.commit()
        return jsonify({"success": True}), 200

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
