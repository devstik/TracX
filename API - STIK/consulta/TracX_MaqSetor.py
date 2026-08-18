from flask import Blueprint, jsonify, request
from database.server import create_connection_tinturaria

tracx_producaoSetorMAQ_bp = Blueprint('tracx_producaoSetorMAQ', __name__)


# ==========================
# LISTAR SETORES
# ==========================
@tracx_producaoSetorMAQ_bp.route('/consulta/setores', methods=['GET'])
def listar_setores():
    connection = None
    try:
        connection = create_connection_tinturaria()
        cursor = connection.cursor()

        sql = """
            SELECT 
                Codigo = ID,
                Nome = NmSetor
            FROM Stik_Setor
            ORDER BY ID
        """

        cursor.execute(sql)
        columns = [column[0] for column in cursor.description]
        results = [dict(zip(columns, row)) for row in cursor.fetchall()]

        return jsonify(results), 200

    except Exception as e:
        return jsonify({"error": str(e)}), 500

    finally:
        if connection:
            connection.close()


# ==========================
# LISTAR MÁQUINAS POR SETOR
# ==========================
@tracx_producaoSetorMAQ_bp.route('/consulta/maquinas', methods=['GET'])
def listar_maquinas_por_setor():
    setor_id = request.args.get("setor")

    if not setor_id:
        return jsonify({"error": "Parâmetro 'setor' é obrigatório"}), 400

    connection = None
    try:
        connection = create_connection_tinturaria()
        cursor = connection.cursor()

        sql = """
            SELECT
                Codigo = ID,
                Nome = NmMaquina
            FROM Stik_Maquina
            WHERE SetorID = ?
            ORDER BY NmMaquina
        """

        cursor.execute(sql, (setor_id,))
        columns = [column[0] for column in cursor.description]
        results = [dict(zip(columns, row)) for row in cursor.fetchall()]

        return jsonify(results), 200

    except Exception as e:
        return jsonify({"error": str(e)}), 500

    finally:
        if connection:
            connection.close()
