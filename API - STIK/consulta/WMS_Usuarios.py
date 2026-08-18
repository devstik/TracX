from flask import Blueprint, jsonify
from database.server import create_connection_tinturaria 
import datetime

wms_usuarios_bp = Blueprint('wms_usuarios', __name__)

@wms_usuarios_bp.route('/consulta/wms/usuario', methods=['GET'])
def get_wms_usuarios():
    """
    Endpoint para consultar os usuários do WMS/sistema (TbUsr),
    com o grupo e permissões detalhadas.
    """
    connection = None
    try:
        connection = create_connection_tinturaria() 
        cursor = connection.cursor()

        sql_query = """
            SET NOCOUNT ON;

            -- Estoquistas
            DECLARE @Estoquistas TABLE (CdUsr INT PRIMARY KEY);
            INSERT INTO @Estoquistas (CdUsr) VALUES (347), (367), (168), (114), (138);

            -- Conferentes
            DECLARE @Conferentes TABLE (CdUsr INT PRIMARY KEY);
            INSERT INTO @Conferentes (CdUsr) VALUES (327), (349), (329), (333);

            -- Separação
            DECLARE @Separacao TABLE (CdUsr INT PRIMARY KEY);
            INSERT INTO @Separacao (CdUsr) VALUES (373), (294), (333), (372), (358), (138);

            -- Conferente Recebimento
            DECLARE @ConferenteRecebimento TABLE (CdUsr INT PRIMARY KEY);
            INSERT INTO @ConferenteRecebimento (CdUsr) VALUES (183), (150), (510);

            -- Líderes
            DECLARE @Lideres TABLE (CdUsr INT PRIMARY KEY);
            INSERT INTO @Lideres (CdUsr) VALUES
            (328), (325), (400), (207), (323),
            (322), (421), (58), (376), (226);

            -- Admins
            DECLARE @AdminUsrs TABLE (CdUsr INT PRIMARY KEY);
            INSERT INTO @AdminUsrs (CdUsr) VALUES
            (97), (258), (313), (343), (350), (375),
            (329), (334), (461), (327), (504), (476);

            SELECT 
                Usr.CdUsr,
                Usr.NmUsr,
                Grupo = CASE
                    WHEN Est.CdUsr IS NOT NULL THEN 'Estoquista'
                    WHEN Conf.CdUsr IS NOT NULL THEN 'Conferente'
                    WHEN Sep.CdUsr IS NOT NULL THEN 'Separacao'
                    WHEN ConfRec.CdUsr IS NOT NULL THEN 'ConferenteRecebimento'
                    WHEN Lid.CdUsr IS NOT NULL THEN 'Lider'
                    WHEN Adm.CdUsr IS NOT NULL THEN 'Admin'
                    ELSE 'Sem Grupo'
                END,
                Permissoes = CASE
                    WHEN Est.CdUsr IS NOT NULL THEN
                        '/romaneios,/imprimir-etiqueta,/alocar-palete,/alocar-cancelados,/ajuste-embalagem-palete,/transferir,/movimentar,/estoque,/relatorios,/inventario,/ociosidade, /separacao, /auditoria-palete'
                    
                    WHEN Conf.CdUsr IS NOT NULL THEN
                        '/romaneios,/imprimir-etiqueta,/conferencia,/separacao,/transferir,/estoque,/relatorios,/inventario, /auditoria-palete'
                    
                    WHEN Sep.CdUsr IS NOT NULL THEN
                        '/romaneios,/imprimir-etiqueta,/separacao,/alocar-palete,/alocar-cancelados,/ajuste-embalagem-palete,/transferir,/movimentar,/estoque,/relatorios,/auditoria-palete'
                    
                    WHEN ConfRec.CdUsr IS NOT NULL THEN
                        '/romaneios,/imprimir-etiqueta,/entrada,/alocar-palete,/alocar-cancelados,/ajuste-embalagem-palete,/movimentar,/estoque,/relatorios,/separacao'
                    
                    WHEN Lid.CdUsr IS NOT NULL THEN
                        '/auditoria-palete,/imprimir-etiqueta,/romaneios,/separacao,/conferencia,/entrada,/alocar-palete,/alocar-cancelados,/ajuste-embalagem-palete,/transferir,/movimentar,/estoque,/relatorios,/inventario,/ociosidade,/imprimir-etiqueta'
                    
                    WHEN Adm.CdUsr IS NOT NULL THEN
                        'ALL'
                    
                    ELSE ''
                END
            FROM dbo.TbUsr AS Usr
            LEFT JOIN @Estoquistas AS Est ON Usr.CdUsr = Est.CdUsr
            LEFT JOIN @Conferentes AS Conf ON Usr.CdUsr = Conf.CdUsr
            LEFT JOIN @Separacao AS Sep ON Usr.CdUsr = Sep.CdUsr
            LEFT JOIN @ConferenteRecebimento AS ConfRec ON Usr.CdUsr = ConfRec.CdUsr
            LEFT JOIN @Lideres AS Lid ON Usr.CdUsr = Lid.CdUsr
            LEFT JOIN @AdminUsrs AS Adm ON Usr.CdUsr = Adm.CdUsr
            WHERE
                Est.CdUsr IS NOT NULL
                OR Conf.CdUsr IS NOT NULL
                OR Sep.CdUsr IS NOT NULL
                OR ConfRec.CdUsr IS NOT NULL
                OR Lid.CdUsr IS NOT NULL
                OR Adm.CdUsr IS NOT NULL
            ORDER BY Usr.NmUsr;
        """
        
        cursor.execute(sql_query)
        registros = [dict(zip([column[0] for column in cursor.description], row)) for row in cursor.fetchall()]
        
        print(f"✅ Consulta WMS Usuários executada. {len(registros)} linhas retornadas.")
        return jsonify(registros)

    except Exception as e:
        print(f"❌ Erro ao consultar WMS Usuários: {e}")
        return jsonify({"error": str(e)}), 500

    finally:
        if connection:
            connection.close()