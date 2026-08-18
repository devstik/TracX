# from flask import Blueprint, jsonify, request
# from database.server import create_connection_tinturaria

# wms_caixa_bp = Blueprint('wms_caixa', __name__)


# def _row_to_dict(cursor, row):
#     if not row:
#         return None
#     cols = [col[0] for col in cursor.description]
#     return dict(zip(cols, row))


# # ===================================================================
# # ROTA: REGISTRAR/ATUALIZAR CAIXA (POST)
# # Chamada ao alocar um material: grava (ou atualiza a localizacao de)
# # uma caixa individual pelo codigo unico CX impresso na etiqueta.
# # QR da etiqueta: {"CdObj":...,"Detalhe":...,"D":...,"C":"G","O":...,"CX":"..."}
# # ===================================================================
# @wms_caixa_bp.route('/consulta/wms/caixa/registrar', methods=['POST'])
# def registrar_caixa():
#     connection = None
#     try:
#         data = request.get_json() or {}

#         cx = (data.get('CX') or '').strip()
#         cd_obj = data.get('CdObj')
#         detalhe = data.get('Detalhe')
#         tipo_caixa = (data.get('TipoCaixa') or data.get('C') or '').strip().upper()
#         nr_ordem = data.get('NrOrdem') or data.get('O')
#         data_fabricacao = data.get('DataFabricacao') or data.get('D')
#         endereco = (data.get('Endereco') or '').strip().upper()
#         cd_usr = data.get('CdUsr')
#         cd_usr = int(cd_usr) if cd_usr not in (None, '', 0, '0') else None
#         # ALOCACAO (padrão) = primeira entrada da caixa no armazém, não pode
#         # mudar o endereço de uma caixa já disponível em outro lugar.
#         # TRANSFERENCIA = único fluxo autorizado a mover a caixa de endereço.
#         origem_registro = (data.get('Origem') or data.get('origem') or 'ALOCACAO').strip().upper()

#         if not cx or not cd_obj:
#             return jsonify({"error": "Campos obrigatorios: CX, CdObj"}), 400

#         connection = create_connection_tinturaria()
#         if connection is None:
#             return jsonify({"error": "Falha ao conectar ao banco."}), 500

#         cursor = connection.cursor()
#         cursor.execute("SET NOCOUNT ON; SET XACT_ABORT ON;")

#         cursor.execute(
#             "SELECT ID, Endereco, Status FROM dbo.Stik_WMS_Caixa WHERE CX = ?",
#             (cx,),
#         )
#         existente = cursor.fetchone()

#         if existente:
#             endereco_atual = (existente[1] or '').strip().upper()
#             status_atual = (existente[2] or '').strip().upper()

#             if (
#                 status_atual == 'DISPONIVEL'
#                 and endereco_atual
#                 and endereco
#                 and endereco_atual != endereco
#                 and origem_registro != 'TRANSFERENCIA'
#             ):
#                 return jsonify({
#                     "error": f"Caixa {cx} já está alocada no endereço {existente[1]}. Use a tela de Transferência para mover.",
#                     "endereco_atual": existente[1],
#                 }), 409

#             # Status = 'DISPONIVEL' é setado explicitamente aqui porque uma
#             # caixa pode chegar com Status = 'IMPRESSA' (gravada já no
#             # momento da impressão, ver WMS_Etiquetas_QrCode.py) — a
#             # alocação/transferência é o que efetivamente a torna disponível
#             # no armazém. Para caixas que já eram 'DISPONIVEL', é um no-op.
#             cursor.execute(
#                 """
#                 UPDATE dbo.Stik_WMS_Caixa
#                 SET Endereco = ?, CdUsr = ?, DataAlocacao = GETDATE(), Status = 'DISPONIVEL'
#                 WHERE CX = ?
#                 """,
#                 (endereco or None, cd_usr, cx),
#             )
#         else:
#             cursor.execute(
#                 """
#                 INSERT INTO dbo.Stik_WMS_Caixa
#                     (CX, CdObj, Detalhe, TipoCaixa, NrOrdem, DataFabricacao,
#                      Endereco, CdUsr, DataImpressao, DataAlocacao)
#                 VALUES (?, ?, ?, ?, ?, ?, ?, ?, GETDATE(), GETDATE())
#                 """,
#                 (
#                     cx,
#                     int(cd_obj),
#                     int(detalhe) if detalhe not in (None, '') else None,
#                     tipo_caixa or None,
#                     int(nr_ordem) if nr_ordem not in (None, '') else None,
#                     str(data_fabricacao) if data_fabricacao else None,
#                     endereco or None,
#                     cd_usr,
#                 ),
#             )

#         connection.commit()

#         print(f"Caixa {cx} registrada/atualizada: CdObj={cd_obj} Tipo={tipo_caixa} Endereco={endereco}")

#         return jsonify({
#             "success": True,
#             "message": "Caixa atualizada." if existente else "Caixa registrada com sucesso.",
#             "CX": cx,
#             "TipoCaixa": tipo_caixa,
#         }), (200 if existente else 201)

#     except Exception as e:
#         if connection:
#             try:
#                 connection.rollback()
#             except Exception:
#                 pass
#         print(f"Erro ao registrar caixa: {e}")
#         return jsonify({"error": str(e)}), 500

#     finally:
#         if connection:
#             connection.close()


# # ===================================================================
# # ROTA: CONSULTAR CAIXA PELO CODIGO (GET)
# # Permite descobrir CdObj/Detalhe/TipoCaixa/Endereco a partir do CX
# # lido isoladamente (sem o restante do JSON da etiqueta).
# # ===================================================================
# @wms_caixa_bp.route('/consulta/wms/caixa/<cx>', methods=['GET'])
# def consultar_caixa(cx):
#     connection = None
#     try:
#         cx = (cx or '').strip()
#         if not cx:
#             return jsonify({"error": "Codigo CX invalido."}), 400

#         connection = create_connection_tinturaria()
#         if connection is None:
#             return jsonify({"error": "Falha ao conectar ao banco."}), 500

#         cursor = connection.cursor()
#         cursor.execute("SET NOCOUNT ON;")
#         cursor.execute(
#             """
#             SELECT TOP 1
#                 CX, CdObj, Detalhe, TipoCaixa, NrOrdem, DataFabricacao,
#                 Endereco, CdUsr, DataImpressao, DataAlocacao
#             FROM dbo.Stik_WMS_Caixa
#             WHERE CX = ?
#             """,
#             (cx,),
#         )
#         row = _row_to_dict(cursor, cursor.fetchone())

#         if not row:
#             return jsonify({"error": f"Caixa {cx} nao encontrada."}), 404

#         for campo in ('DataImpressao', 'DataAlocacao'):
#             if row.get(campo):
#                 row[campo] = row[campo].isoformat()

#         return jsonify({"success": True, "data": row}), 200

#     except Exception as e:
#         return jsonify({"error": str(e)}), 500

#     finally:
#         if connection:
#             connection.close()


# # ===================================================================
# # ROTA: RESUMO DE CAIXAS DISPONIVEIS POR ENDERECO (GET)
# # Conta quantas caixas DISPONIVEL existem por CdObj+Detalhe+TipoCaixa,
# # para alimentar os campos de embalagem (P/G/ENFE/ENFR) das telas de
# # alocacao — fonte agora e Stik_WMS_Caixa, nao mais o contador agregado.
# # ===================================================================
# @wms_caixa_bp.route('/consulta/wms/caixa/resumo', methods=['GET'])
# def resumo_caixas():
#     connection = None
#     try:
#         endereco = (request.args.get('endereco') or request.args.get('Endereco') or '').strip().upper()

#         connection = create_connection_tinturaria()
#         if connection is None:
#             return jsonify({"error": "Falha ao conectar ao banco."}), 500

#         cursor = connection.cursor()
#         cursor.execute("SET NOCOUNT ON;")

#         sql = """
#             SELECT
#                 C.Endereco,
#                 C.CdObj,
#                 Detalhe = ISNULL(C.Detalhe, 0),
#                 C.TipoCaixa,
#                 Descricao = MAX(Obj.NmObj),
#                 Quantidade = COUNT(*)
#             FROM dbo.Stik_WMS_Caixa C WITH (NOLOCK)
#             LEFT JOIN dbo.TbObj Obj WITH (NOLOCK) ON Obj.CdObj = C.CdObj
#             WHERE C.Status = 'DISPONIVEL'
#         """
#         params = []
#         if endereco:
#             sql += " AND UPPER(LTRIM(RTRIM(C.Endereco))) = ?"
#             params.append(endereco)

#         sql += """
#             GROUP BY C.Endereco, C.CdObj, ISNULL(C.Detalhe, 0), C.TipoCaixa
#             ORDER BY C.Endereco, C.CdObj
#         """

#         cursor.execute(sql, params)
#         columns = [col[0] for col in cursor.description]
#         rows = [dict(zip(columns, row)) for row in cursor.fetchall()]

#         return jsonify({"success": True, "data": rows}), 200

#     except Exception as e:
#         return jsonify({"error": str(e)}), 500

#     finally:
#         if connection:
#             connection.close()


# # ===================================================================
# # ROTA: LISTAR CAIXAS DE UM LOTE DE IMPRESSAO (GET)
# # Dado o LI (gerado/echoado por WMS_Etiquetas_QrCode.py na impressão da
# # caixa), devolve a lista individual (nao agregada) das CX daquele lote —
# # consulta sempre ao vivo no banco, nunca em memoria do app. Usada pela
# # Entrada para ler 1 unica etiqueta do lote e recuperar todas as CX
# # impressas juntas, evitando escanear caixa por caixa.
# # Requer a coluna LI em dbo.Stik_WMS_Caixa (ver api/sql/*.sql). Se a
# # coluna ainda nao existir, devolve lista vazia em vez de erro 500.
# # ===================================================================
# @wms_caixa_bp.route('/consulta/wms/caixa/lote', methods=['GET'])
# def listar_caixas_lote():
#     connection = None
#     try:
#         li = (request.args.get('li') or request.args.get('LI') or '').strip()
#         if not li:
#             return jsonify({"error": "Parametro obrigatorio: li"}), 400

#         status_filtro = (request.args.get('status') or request.args.get('Status') or '').strip().upper()

#         connection = create_connection_tinturaria()
#         if connection is None:
#             return jsonify({"error": "Falha ao conectar ao banco."}), 500

#         cursor = connection.cursor()
#         cursor.execute("SET NOCOUNT ON;")

#         sql = """
#             SELECT
#                 CX, LI, CdObj, Detalhe, TipoCaixa, NrOrdem, DataFabricacao,
#                 Status, Endereco, CdUsr, DataImpressao, DataAlocacao
#             FROM dbo.Stik_WMS_Caixa
#             WHERE LI = ?
#         """
#         params = [li]
#         if status_filtro:
#             sql += " AND Status = ?"
#             params.append(status_filtro)
#         sql += " ORDER BY DataImpressao"

#         try:
#             cursor.execute(sql, params)
#         except Exception:
#             # Coluna LI ainda nao existe (migration nao aplicada) — nao
#             # quebra o chamador, apenas nao ha lote para agrupar ainda.
#             return jsonify({"success": True, "data": [], "aviso": "Coluna LI indisponivel no banco."}), 200

#         columns = [col[0] for col in cursor.description]
#         rows = [dict(zip(columns, row)) for row in cursor.fetchall()]
#         for row in rows:
#             for campo in ('DataImpressao', 'DataAlocacao'):
#                 if row.get(campo):
#                     row[campo] = row[campo].isoformat()

#         return jsonify({"success": True, "data": rows}), 200

#     except Exception as e:
#         return jsonify({"error": str(e)}), 500

#     finally:
#         if connection:
#             connection.close()


# # ===================================================================
# # ROTA: LISTAR CAIXAS DISPONIVEIS POR ENDERECO (GET, nao agregado)
# # Complementa /consulta/wms/caixa/resumo (que so devolve contagem por
# # CdObj+Detalhe+TipoCaixa): aqui devolve a lista individual de CX
# # DISPONIVEL naquele endereco, para permitir a Transferencia e a
# # Separacao Planejada consumirem N caixas de uma leitura so (ex.: leitura
# # da etiqueta de Palete), atribuindo automaticamente as caixas mais
# # antigas primeiro (FIFO por DataAlocacao) sem precisar saber qual CX
# # fisico o operador pegou.
# # ===================================================================
# @wms_caixa_bp.route('/consulta/wms/caixa/lista', methods=['GET'])
# def listar_caixas_endereco():
#     connection = None
#     try:
#         endereco = (request.args.get('endereco') or request.args.get('Endereco') or '').strip().upper()
#         if not endereco:
#             return jsonify({"error": "Parametro obrigatorio: endereco"}), 400

#         cd_obj = request.args.get('cd_obj') or request.args.get('CdObj')
#         detalhe = request.args.get('detalhe') or request.args.get('Detalhe')
#         tipo_caixa = (request.args.get('tipo_caixa') or request.args.get('TipoCaixa') or '').strip().upper()

#         connection = create_connection_tinturaria()
#         if connection is None:
#             return jsonify({"error": "Falha ao conectar ao banco."}), 500

#         cursor = connection.cursor()
#         cursor.execute("SET NOCOUNT ON;")

#         sql = """
#             SELECT
#                 CX, LI, CdObj, Detalhe, TipoCaixa, NrOrdem, DataFabricacao,
#                 Status, Endereco, CdUsr, DataImpressao, DataAlocacao
#             FROM dbo.Stik_WMS_Caixa WITH (NOLOCK)
#             WHERE Status = 'DISPONIVEL'
#               AND UPPER(LTRIM(RTRIM(Endereco))) = ?
#         """
#         params = [endereco]
#         if cd_obj not in (None, ''):
#             sql += " AND CdObj = ?"
#             params.append(int(cd_obj))
#         if detalhe not in (None, ''):
#             sql += " AND ISNULL(Detalhe, 0) = ISNULL(?, 0)"
#             params.append(int(detalhe))
#         if tipo_caixa:
#             sql += " AND TipoCaixa = ?"
#             params.append(tipo_caixa)

#         # FIFO: caixa alocada ha mais tempo primeiro — mesma logica que a
#         # Separacao Planejada ja usa para priorizar giro de estoque.
#         sql += " ORDER BY DataAlocacao ASC"

#         cursor.execute(sql, params)
#         columns = [col[0] for col in cursor.description]
#         rows = [dict(zip(columns, row)) for row in cursor.fetchall()]
#         for row in rows:
#             for campo in ('DataImpressao', 'DataAlocacao'):
#                 if row.get(campo):
#                     row[campo] = row[campo].isoformat()

#         return jsonify({"success": True, "data": rows}), 200

#     except Exception as e:
#         return jsonify({"error": str(e)}), 500

#     finally:
#         if connection:
#             connection.close()

from flask import Blueprint, jsonify, request
from database.server import create_connection_tinturaria

wms_caixa_bp = Blueprint('wms_caixa', __name__)


def _row_to_dict(cursor, row):
    if not row:
        return None
    cols = [col[0] for col in cursor.description]
    return dict(zip(cols, row))


# ===================================================================
# ROTA: REGISTRAR/ATUALIZAR CAIXA (POST)
# Chamada ao alocar um material: grava (ou atualiza a localizacao de)
# uma caixa individual pelo codigo unico CX impresso na etiqueta.
# QR da etiqueta: {"CdObj":...,"Detalhe":...,"D":...,"C":"G","O":...,"CX":"..."}
# ===================================================================
@wms_caixa_bp.route('/consulta/wms/caixa/registrar', methods=['POST'])
def registrar_caixa():
    connection = None
    try:
        data = request.get_json() or {}

        cx = (data.get('CX') or '').strip()
        cd_obj = data.get('CdObj')
        detalhe = data.get('Detalhe')
        tipo_caixa = (data.get('TipoCaixa') or data.get('C') or '').strip().upper()
        nr_ordem = data.get('NrOrdem') or data.get('O')
        data_fabricacao = data.get('DataFabricacao') or data.get('D')
        endereco = (data.get('Endereco') or '').strip().upper()
        # Endereço de origem esperado (informado pela tela de Transferência):
        # confirma que a caixa recebida está mesmo lá antes de mover, evitando
        # mover uma caixa física diferente por um CX obsoleto no cliente.
        endereco_origem = (data.get('EnderecoOrigem') or '').strip().upper()
        cd_usr = data.get('CdUsr')
        cd_usr = int(cd_usr) if cd_usr not in (None, '', 0, '0') else None
        # ALOCACAO (padrão) = primeira entrada da caixa no armazém, não pode
        # mudar o endereço de uma caixa já disponível em outro lugar.
        # TRANSFERENCIA = único fluxo autorizado a mover a caixa de endereço.
        origem_registro = (data.get('Origem') or data.get('origem') or 'ALOCACAO').strip().upper()

        if not cx or not cd_obj:
            return jsonify({"error": "Campos obrigatorios: CX, CdObj"}), 400

        connection = create_connection_tinturaria()
        if connection is None:
            return jsonify({"error": "Falha ao conectar ao banco."}), 500

        cursor = connection.cursor()
        cursor.execute("SET NOCOUNT ON; SET XACT_ABORT ON;")

        cursor.execute(
            "SELECT ID, Endereco, Status FROM dbo.Stik_WMS_Caixa WHERE CX = ?",
            (cx,),
        )
        existente = cursor.fetchone()

        if existente:
            endereco_atual = (existente[1] or '').strip().upper()
            status_atual = (existente[2] or '').strip().upper()

            if (
                status_atual == 'DISPONIVEL'
                and endereco_atual
                and endereco
                and endereco_atual != endereco
                and origem_registro != 'TRANSFERENCIA'
            ):
                return jsonify({
                    "error": f"Caixa {cx} já está alocada no endereço {existente[1]}. Use a tela de Transferência para mover.",
                    "endereco_atual": existente[1],
                }), 409

            # Transferência precisa confirmar que a caixa está mesmo na
            # origem informada — sem isso, o cliente pode reenviar um CX
            # obsoleto (de outra leitura/outro palete) e mover a caixa
            # física errada silenciosamente. Best-effort: só valida quando
            # EnderecoOrigem foi informado (retrocompatível com chamadores
            # antigos que ainda não enviam esse campo).
            if (
                origem_registro == 'TRANSFERENCIA'
                and endereco_origem
                and endereco_atual != endereco_origem
            ):
                return jsonify({
                    "error": f"Caixa {cx} não está no endereço de origem informado ({endereco_origem}). Endereço atual: {existente[1] or 'N/D'}.",
                    "endereco_atual": existente[1],
                }), 409

            # Status = 'DISPONIVEL' é setado explicitamente aqui porque uma
            # caixa pode chegar com Status = 'IMPRESSA' (gravada já no
            # momento da impressão, ver WMS_Etiquetas_QrCode.py) — a
            # alocação/transferência é o que efetivamente a torna disponível
            # no armazém. Para caixas que já eram 'DISPONIVEL', é um no-op.
            cursor.execute(
                """
                UPDATE dbo.Stik_WMS_Caixa
                SET Endereco = ?, CdUsr = ?, DataAlocacao = GETDATE(), Status = 'DISPONIVEL'
                WHERE CX = ?
                """,
                (endereco or None, cd_usr, cx),
            )
        else:
            cursor.execute(
                """
                INSERT INTO dbo.Stik_WMS_Caixa
                    (CX, CdObj, Detalhe, TipoCaixa, NrOrdem, DataFabricacao,
                     Endereco, CdUsr, DataImpressao, DataAlocacao)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, GETDATE(), GETDATE())
                """,
                (
                    cx,
                    int(cd_obj),
                    int(detalhe) if detalhe not in (None, '') else None,
                    tipo_caixa or None,
                    int(nr_ordem) if nr_ordem not in (None, '') else None,
                    str(data_fabricacao) if data_fabricacao else None,
                    endereco or None,
                    cd_usr,
                ),
            )

        connection.commit()

        print(f"Caixa {cx} registrada/atualizada: CdObj={cd_obj} Tipo={tipo_caixa} Endereco={endereco}")

        return jsonify({
            "success": True,
            "message": "Caixa atualizada." if existente else "Caixa registrada com sucesso.",
            "CX": cx,
            "TipoCaixa": tipo_caixa,
        }), (200 if existente else 201)

    except Exception as e:
        if connection:
            try:
                connection.rollback()
            except Exception:
                pass
        print(f"Erro ao registrar caixa: {e}")
        return jsonify({"error": str(e)}), 500

    finally:
        if connection:
            connection.close()


# ===================================================================
# ROTA: CONSULTAR CAIXA PELO CODIGO (GET)
# Permite descobrir CdObj/Detalhe/TipoCaixa/Endereco a partir do CX
# lido isoladamente (sem o restante do JSON da etiqueta).
# ===================================================================
@wms_caixa_bp.route('/consulta/wms/caixa/<cx>', methods=['GET'])
def consultar_caixa(cx):
    connection = None
    try:
        cx = (cx or '').strip()
        if not cx:
            return jsonify({"error": "Codigo CX invalido."}), 400

        connection = create_connection_tinturaria()
        if connection is None:
            return jsonify({"error": "Falha ao conectar ao banco."}), 500

        cursor = connection.cursor()
        cursor.execute("SET NOCOUNT ON;")
        cursor.execute(
            """
            SELECT TOP 1
                CX, CdObj, Detalhe, TipoCaixa, NrOrdem, DataFabricacao,
                Endereco, CdUsr, DataImpressao, DataAlocacao
            FROM dbo.Stik_WMS_Caixa
            WHERE CX = ?
            """,
            (cx,),
        )
        row = _row_to_dict(cursor, cursor.fetchone())

        if not row:
            return jsonify({"error": f"Caixa {cx} nao encontrada."}), 404

        for campo in ('DataImpressao', 'DataAlocacao'):
            if row.get(campo):
                row[campo] = row[campo].isoformat()

        return jsonify({"success": True, "data": row}), 200

    except Exception as e:
        return jsonify({"error": str(e)}), 500

    finally:
        if connection:
            connection.close()


# ===================================================================
# ROTA: RESUMO DE CAIXAS DISPONIVEIS POR ENDERECO (GET)
# Conta quantas caixas DISPONIVEL existem por CdObj+Detalhe+TipoCaixa,
# para alimentar os campos de embalagem (P/G/ENFE/ENFR) das telas de
# alocacao — fonte agora e Stik_WMS_Caixa, nao mais o contador agregado.
# ===================================================================
@wms_caixa_bp.route('/consulta/wms/caixa/resumo', methods=['GET'])
def resumo_caixas():
    connection = None
    try:
        endereco = (request.args.get('endereco') or request.args.get('Endereco') or '').strip().upper()

        connection = create_connection_tinturaria()
        if connection is None:
            return jsonify({"error": "Falha ao conectar ao banco."}), 500

        cursor = connection.cursor()
        cursor.execute("SET NOCOUNT ON;")

        sql = """
            SELECT
                C.Endereco,
                C.CdObj,
                Detalhe = ISNULL(C.Detalhe, 0),
                C.TipoCaixa,
                Descricao = MAX(Obj.NmObj),
                Quantidade = COUNT(*)
            FROM dbo.Stik_WMS_Caixa C WITH (NOLOCK)
            LEFT JOIN dbo.TbObj Obj WITH (NOLOCK) ON Obj.CdObj = C.CdObj
            WHERE C.Status = 'DISPONIVEL'
        """
        params = []
        if endereco:
            sql += " AND UPPER(LTRIM(RTRIM(C.Endereco))) = ?"
            params.append(endereco)

        sql += """
            GROUP BY C.Endereco, C.CdObj, ISNULL(C.Detalhe, 0), C.TipoCaixa
            ORDER BY C.Endereco, C.CdObj
        """

        cursor.execute(sql, params)
        columns = [col[0] for col in cursor.description]
        rows = [dict(zip(columns, row)) for row in cursor.fetchall()]

        return jsonify({"success": True, "data": rows}), 200

    except Exception as e:
        return jsonify({"error": str(e)}), 500

    finally:
        if connection:
            connection.close()


# ===================================================================
# ROTA: LISTAR CAIXAS DE UM LOTE DE IMPRESSAO (GET)
# Dado o LI (gerado/echoado por WMS_Etiquetas_QrCode.py na impressão da
# caixa), devolve a lista individual (nao agregada) das CX daquele lote —
# consulta sempre ao vivo no banco, nunca em memoria do app. Usada pela
# Entrada para ler 1 unica etiqueta do lote e recuperar todas as CX
# impressas juntas, evitando escanear caixa por caixa.
# Requer a coluna LI em dbo.Stik_WMS_Caixa (ver api/sql/*.sql). Se a
# coluna ainda nao existir, devolve lista vazia em vez de erro 500.
# ===================================================================
@wms_caixa_bp.route('/consulta/wms/caixa/lote', methods=['GET'])
def listar_caixas_lote():
    connection = None
    try:
        li = (request.args.get('li') or request.args.get('LI') or '').strip()
        if not li:
            return jsonify({"error": "Parametro obrigatorio: li"}), 400

        status_filtro = (request.args.get('status') or request.args.get('Status') or '').strip().upper()

        connection = create_connection_tinturaria()
        if connection is None:
            return jsonify({"error": "Falha ao conectar ao banco."}), 500

        cursor = connection.cursor()
        cursor.execute("SET NOCOUNT ON;")

        sql = """
            SELECT
                CX, LI, CdObj, Detalhe, TipoCaixa, NrOrdem, DataFabricacao,
                Status, Endereco, CdUsr, DataImpressao, DataAlocacao
            FROM dbo.Stik_WMS_Caixa
            WHERE LI = ?
        """
        params = [li]
        if status_filtro:
            sql += " AND Status = ?"
            params.append(status_filtro)
        sql += " ORDER BY DataImpressao"

        try:
            cursor.execute(sql, params)
        except Exception:
            # Coluna LI ainda nao existe (migration nao aplicada) — nao
            # quebra o chamador, apenas nao ha lote para agrupar ainda.
            return jsonify({"success": True, "data": [], "aviso": "Coluna LI indisponivel no banco."}), 200

        columns = [col[0] for col in cursor.description]
        rows = [dict(zip(columns, row)) for row in cursor.fetchall()]
        for row in rows:
            for campo in ('DataImpressao', 'DataAlocacao'):
                if row.get(campo):
                    row[campo] = row[campo].isoformat()

        return jsonify({"success": True, "data": rows}), 200

    except Exception as e:
        return jsonify({"error": str(e)}), 500

    finally:
        if connection:
            connection.close()


# ===================================================================
# ROTA: LISTAR CAIXAS DISPONIVEIS POR ENDERECO (GET, nao agregado)
# Complementa /consulta/wms/caixa/resumo (que so devolve contagem por
# CdObj+Detalhe+TipoCaixa): aqui devolve a lista individual de CX
# DISPONIVEL naquele endereco, para permitir a Transferencia e a
# Separacao Planejada consumirem N caixas de uma leitura so (ex.: leitura
# da etiqueta de Palete), atribuindo automaticamente as caixas mais
# antigas primeiro (FIFO por DataAlocacao) sem precisar saber qual CX
# fisico o operador pegou.
# ===================================================================
@wms_caixa_bp.route('/consulta/wms/caixa/lista', methods=['GET'])
def listar_caixas_endereco():
    connection = None
    try:
        endereco = (request.args.get('endereco') or request.args.get('Endereco') or '').strip().upper()
        if not endereco:
            return jsonify({"error": "Parametro obrigatorio: endereco"}), 400

        cd_obj = request.args.get('cd_obj') or request.args.get('CdObj')
        detalhe = request.args.get('detalhe') or request.args.get('Detalhe')
        tipo_caixa = (request.args.get('tipo_caixa') or request.args.get('TipoCaixa') or '').strip().upper()

        connection = create_connection_tinturaria()
        if connection is None:
            return jsonify({"error": "Falha ao conectar ao banco."}), 500

        cursor = connection.cursor()
        cursor.execute("SET NOCOUNT ON;")

        sql = """
            SELECT
                CX, LI, CdObj, Detalhe, TipoCaixa, NrOrdem, DataFabricacao,
                Status, Endereco, CdUsr, DataImpressao, DataAlocacao
            FROM dbo.Stik_WMS_Caixa WITH (NOLOCK)
            WHERE Status = 'DISPONIVEL'
              AND UPPER(LTRIM(RTRIM(Endereco))) = ?
        """
        params = [endereco]
        if cd_obj not in (None, ''):
            sql += " AND CdObj = ?"
            params.append(int(cd_obj))
        if detalhe not in (None, ''):
            sql += " AND ISNULL(Detalhe, 0) = ISNULL(?, 0)"
            params.append(int(detalhe))
        if tipo_caixa:
            sql += " AND TipoCaixa = ?"
            params.append(tipo_caixa)

        # FIFO: caixa alocada ha mais tempo primeiro — mesma logica que a
        # Separacao Planejada ja usa para priorizar giro de estoque.
        sql += " ORDER BY DataAlocacao ASC"

        cursor.execute(sql, params)
        columns = [col[0] for col in cursor.description]
        rows = [dict(zip(columns, row)) for row in cursor.fetchall()]
        for row in rows:
            for campo in ('DataImpressao', 'DataAlocacao'):
                if row.get(campo):
                    row[campo] = row[campo].isoformat()

        return jsonify({"success": True, "data": rows}), 200

    except Exception as e:
        return jsonify({"error": str(e)}), 500

    finally:
        if connection:
            connection.close()
