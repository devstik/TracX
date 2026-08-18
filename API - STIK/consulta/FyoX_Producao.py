from flask import Blueprint, jsonify
from database.server import create_connection_tinturaria 

# Define o Blueprint
fyox_producao_bp = Blueprint('fyox_producao', __name__)

def executar_consulta_objeto(cd_arvore):
    """Função auxiliar para executar a query SQL padronizada"""
    connection = None
    try:
        connection = create_connection_tinturaria() 
        cursor = connection.cursor()

        sql_select = """
            SELECT
                CdObj = Obj.CdObj,
                NmObj = Obj.NmObj,
                NmObjMae = ObjMae.NmObj
            FROM TbObj Obj
            LEFT JOIN TbArvObj ArvObj ON ArvObj.CdObjFil = Obj.CdObj 
            LEFT JOIN TbCao Cao
                 JOIN TbTca Tca ON Tca.CdTca = Cao.CdTca
                               AND Tca.FlTcaDef = 1
                               ON Cao.CdObj = Obj.CdObj
            LEFT JOIN TbObj ObjMae ON ObjMae.CdObj = Obj.CdObjMae
            WHERE
                ArvObj.CdObj = ?
                AND Obj.TpObj = 4
        """

        cursor.execute(sql_select, (cd_arvore,))
        
        columns = [column[0] for column in cursor.description]
        results = [dict(zip(columns, row)) for row in cursor.fetchall()]
        
        return results, 200

    except Exception as e:
        print(f"❌ Erro na consulta (CdObj {cd_arvore}): {e}")
        return {"error": str(e)}, 500
    finally:
        if connection:
            connection.close()

# --- Endpoints ---

@fyox_producao_bp.route('/consulta/urdideira', methods=['GET'])
def listar_urdideira():
    results, status_code = executar_consulta_objeto(4214)
    return jsonify(results), status_code

@fyox_producao_bp.route('/consulta/recobrimento', methods=['GET'])
def listar_recobrimento():
    results, status_code = executar_consulta_objeto(4763)
    return jsonify(results), status_code