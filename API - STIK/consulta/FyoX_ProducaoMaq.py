from flask import Blueprint, jsonify
from database.server import create_connection_tinturaria 

# Define o Blueprint
fyox_producaoMAQ_bp = Blueprint('fyox_producaoMAQ', __name__)

def executar_consulta_por_ids(lista_ids_mae):
    connection = None
    try:
        connection = create_connection_tinturaria() 
        cursor = connection.cursor()
        if not lista_ids_mae:
            return [], 200

        placeholders = ', '.join(['?'] * len(lista_ids_mae))
        sql_select = f"""
            SELECT DISTINCT
                CdObjM = Obj.CdObj,
                NmObjM = Obj.NmObj,
                CdObjMae = MaeM.CdObj
            FROM TbObj Obj
            LEFT JOIN TbObj MaeM ON MaeM.CdObj = Obj.CdObjMae
            WHERE Obj.TpObjCtg = 20
              AND Obj.TpObj = 4
              AND MaeM.CdObj IN ({placeholders})
        """
        cursor.execute(sql_select, lista_ids_mae)
        columns = [column[0] for column in cursor.description]
        results = [dict(zip(columns, row)) for row in cursor.fetchall()]
        return results, 200
    except Exception as e:
        return {"error": str(e)}, 500
    finally:
        if connection:
            connection.close()

# --- Endpoints com o sufixo MAQ para evitar o erro 404 ---

@fyox_producaoMAQ_bp.route('/consulta/urdideiraMAQ', methods=['GET'])
def listar_urdideira():
    return executar_consulta_por_ids([4762])

@fyox_producaoMAQ_bp.route('/consulta/recobrimentoMAQ', methods=['GET'])
def listar_recobrimento():
    return executar_consulta_por_ids([4763])