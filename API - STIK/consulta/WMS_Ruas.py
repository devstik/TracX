from flask import Blueprint, jsonify
from database.server import create_connection_tinturaria 
import datetime  

wms_ruas_bp = Blueprint('wms_ruas', __name__)

@wms_ruas_bp.route('/consulta/wms/ruas', methods=['GET'])
def get_wms_ruas():
    """
    Endpoint para consultar a configuração de ruas do WMS.
    """
    connection = None
    try:
        
        connection = create_connection_tinturaria() 
        cursor = connection.cursor()

        sql_query = """
            SET NOCOUNT ON;
            SELECT * FROM dbo.Stik_WMS_RuaConfig;
        """
        
        cursor.execute(sql_query)
        registros = [dict(zip([column[0] for column in cursor.description], row)) for row in cursor.fetchall()]
        
        print(f"✅ Consulta WMS Ruas executada. {len(registros)} linhas retornadas.")
        return jsonify(registros)

    except Exception as e:
        print(f"❌ Erro ao consultar WMS Ruas: {e}")
        return jsonify({"error": str(e)}), 500

    finally:
        if connection:
            connection.close()
            print("🔌 Conexão com o banco de dados fechada.")