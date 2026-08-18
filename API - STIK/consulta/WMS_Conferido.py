from flask import Blueprint, jsonify, request
from database.server import create_connection_tinturaria 
import datetime

# Define o Blueprint
wms_conferido_bp = Blueprint('wms_conferido', __name__)

@wms_conferido_bp.route('/consulta/romaneio/conferir', methods=['PUT'])
def conferir_romaneio():
    """
    Endpoint para atualizar o romaneio para Conferido (TpSitFat=4).
    
    Recebe JSON:
    {
        "ID": 12345,          (Obrigatório: ID da linha)
        "QtAtendida": 500,    (Obrigatório: lQtExp)
        "CdUsrConf": 357,     (Obrigatório: lCdUsrConf)
        "TpSitCan": 0,        (Opcional: 0 para normal, 9 para cancelado)
        "TpMotivoCan": 0      (Opcional: 0 se não houver motivo)
    }
    """
    connection = None
    try:
        data = request.get_json()
        if not data:
            return jsonify({"error": "Dados JSON não fornecidos"}), 400

        # Mapeamento das variáveis
        id_registro = data.get('ID')
        qt_atendida = data.get('QtAtendida')
        cd_usr_conf = data.get('CdUsrConf')
        
        # Opcionais (Assume 0 se não enviar)
        tp_sit_can = data.get('TpSitCan', 0)
        tp_motivo_can = data.get('TpMotivoCan', 0)

        # Validação simples
        if not all([id_registro, qt_atendida is not None, cd_usr_conf]):
            return jsonify({"error": "Campos 'ID', 'QtAtendida' e 'CdUsrConf' são obrigatórios"}), 400

        connection = create_connection_tinturaria() 
        cursor = connection.cursor()

        # Update direto
        sql_update = """
            SET NOCOUNT ON;
            UPDATE dbo.Stik_Pedido_QtdFat 
            SET TpSitFat    = 4,             -- Status Conferido
                QtFatAtend  = ?,             -- Quantidade Expedida
                TpSitCan    = ?,             -- Cancelamento (0 ou 9)
                TpMotivoCan = ?,             -- Motivo
                CdUsrConf   = ?,             -- Usuário Conferente
                DtConf      = GETDATE()      -- Data Atual
            WHERE ID = ?;
        """

        cursor.execute(sql_update, (qt_atendida, tp_sit_can, tp_motivo_can, cd_usr_conf, id_registro))
        
        if cursor.rowcount == 0:
             return jsonify({"error": "Nenhum registro encontrado com esse ID."}), 404

        connection.commit()

        print(f"✅ Romaneio Item {id_registro} conferido com sucesso.")
        return jsonify({"message": "Status atualizado para Conferido (4) com sucesso."}), 200

    except Exception as e:
        if connection:
            connection.rollback()
        print(f"❌ Erro ao conferir romaneio: {e}")
        return jsonify({"error": str(e)}), 500

    finally:
        if connection:
            connection.close()
            print("🔌 Conexão com o banco de dados fechada.")