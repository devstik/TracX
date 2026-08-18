from flask import Blueprint, jsonify, request
from database.server import create_connection_tinturaria 


# Define o Blueprint
wms_listar_alocacoes_bp = Blueprint('wms_listar_alocacoes', __name__)

# @wms_listar_alocacoes_bp.route('/consulta/wms/listar_alocacao', methods=['GET'])
# def listar_alocacoes():
#     """
#     Retorna a lista de materiais alocados na tabela Stik_WMS_Alocacao,
#     incluindo a composição de embalagens registrada em Stik_WMS_Alocacao_Embalagem.
#     """
#     connection = None
#     try:
#         connection = create_connection_tinturaria()
#         cursor = connection.cursor()

#         sql = """
#             SELECT 
#                 A.ID,
#                 A.Endereco,
#                 A.CodSKU,
#                 ISNULL(Obj.NmObj, 'Produto não identificado') AS Produto,
#                 A.QtAlocada,
#                 A.QtMaxima,
#                 A.Detalhe AS CdLot,
#                 ISNULL(Lot.NmLot, '') AS NmLot,
#                 ISNULL(E.QtCaixaP, 0) AS QtCaixaP,
#                 ISNULL(E.QtCaixaG, 0) AS QtCaixaG,
#                 ISNULL(E.QtEnfestado, 0) AS QtEnfestado,
#                 ISNULL(E.QtEnfraldado, 0) AS QtEnfraldado,
#                 FORMAT(A.DataAtualizacao, 'dd/MM/yyyy HH:mm') AS DataAtualizacao
#             FROM dbo.Stik_WMS_Alocacao A
#             LEFT JOIN dbo.Stik_WMS_Alocacao_Embalagem E
#                 ON E.Endereco = A.Endereco
#                AND E.CodSKU = A.CodSKU
#                AND ISNULL(E.Detalhe, 0) = ISNULL(A.Detalhe, 0)
#             LEFT JOIN dbo.TbObj Obj 
#                 ON Obj.CdObj = A.CodSKU
#             LEFT JOIN dbo.TbLot Lot
#                 ON Lot.CdLot = A.Detalhe
#             ORDER BY A.DataAtualizacao DESC
#         """
        
#         cursor.execute(sql)

#         colunas = [column[0] for column in cursor.description]
#         resultados = []
#         for row in cursor.fetchall():
#             resultados.append(dict(zip(colunas, row)))

#         print(f"✅ Consulta de Alocação: {len(resultados)} itens retornados.")
#         return jsonify(resultados)

#     except Exception as e:
#         print(f"❌ Erro ao listar alocações: {e}")
#         return jsonify({"error": str(e)}), 500

#     finally:
#         if connection:
#             connection.close()

@wms_listar_alocacoes_bp.route('/consulta/wms/listar_alocacao', methods=['GET'])
def listar_alocacoes():
    connection = None
    try:
        cod_skus_param = request.args.get('cod_skus', '').strip()
        skus_filtro = [s.strip() for s in cod_skus_param.split(',') if s.strip()] if cod_skus_param else []

        connection = create_connection_tinturaria()
        cursor = connection.cursor()

        sku_filter_sql = ''
        sku_params = []
        if skus_filtro:
            placeholders = ','.join(['?' for _ in skus_filtro])
            sku_filter_sql = f'WHERE A.CodSKU IN ({placeholders})'
            sku_params = skus_filtro

        sql = f"""
            SELECT
                A.ID,
                A.Endereco,
                A.CodSKU,
                ISNULL(Obj.NmObj, 'Produto não identificado') AS Produto,
                A.QtAlocada,
                A.QtMaxima,
                A.Detalhe                                       AS CdLot,
                ISNULL(Lot.NmLot, '')                           AS NmLot,
                ISNULL(E.QtCaixaP, 0)                           AS QtCaixaP,
                ISNULL(E.QtCaixaG, 0)                           AS QtCaixaG,
                ISNULL(E.QtEnfestado, 0)                        AS QtEnfestado,
                ISNULL(E.QtEnfraldado, 0)                       AS QtEnfraldado,
                CONVERT(varchar(16), A.DataAtualizacao, 103)
                    + ' ' +
                CONVERT(varchar(5),  A.DataAtualizacao, 108)    AS DataAtualizacao
            FROM dbo.Stik_WMS_Alocacao A WITH (NOLOCK)
            LEFT JOIN dbo.Stik_WMS_Alocacao_Embalagem E WITH (NOLOCK)
                ON  E.Endereco = A.Endereco
                AND E.CodSKU   = A.CodSKU
                AND COALESCE(E.Detalhe, 0) = COALESCE(A.Detalhe, 0)
            LEFT JOIN dbo.TbObj Obj WITH (NOLOCK)
                ON Obj.CdObj = A.CodSKU
            LEFT JOIN dbo.TbLot Lot WITH (NOLOCK)
                ON Lot.CdLot = A.Detalhe
            {sku_filter_sql}
            ORDER BY A.DataAtualizacao DESC
        """

        cursor.execute(sql, sku_params)

        colunas = [col[0] for col in cursor.description]
        resultados = [dict(zip(colunas, row)) for row in cursor]

        print(f"✅ Alocação: {len(resultados)} itens | skus={skus_filtro or 'todos'}")
        return jsonify(resultados)

    except Exception as e:
        print(f"❌ Erro ao listar alocações: {e}")
        return jsonify({"error": str(e)}), 500

    finally:
        if connection:
            connection.close()