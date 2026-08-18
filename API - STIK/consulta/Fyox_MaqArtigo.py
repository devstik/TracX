from flask import Blueprint, jsonify, request
from database.server import create_connection_tinturaria 

fyox_MaqArtigo_bp = Blueprint('fyox_MaqArtigo', __name__)

def executar_consulta_objeto(cd_arvore):
    """Executa consulta SQL para listar artigos por máquina dentro de um setor"""
    connection = None
    try:
        connection = create_connection_tinturaria()
        cursor = connection.cursor()

        sql_select = """
            DECLARE @Setor INT = ?

            SELECT
                MaquinaID = ObjM.NmObj,
                CdObj = ObjA.CdObj,
                ArtigoID = ObjA.NmObj,
                A.MetragemPorHora,
                A.FatorMetrosPorPonto,
                Ativo = A.Ativo,
                NrBocas = A.NrBocas,
                FtMeta = ISNULL(A.FtMeta, 0)
            FROM Stik_PCP_ARTIGOSDAMAQUINA A
            LEFT JOIN TbObj ObjM ON ObjM.CdObj = A.MaquinaID
            LEFT JOIN TbObj ObjA ON ObjA.CdObj = A.ArtigoID
            WHERE ObjM.CdObjMae = @Setor
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


# --- Endpoints já existentes ---

@fyox_MaqArtigo_bp.route('/consulta/urdideiraArtigoMaq', methods=['GET'])
def listar_urdideira():
    """Endpoint específico para Urdideira (CdObj 4213)"""
    results, status_code = executar_consulta_objeto(4762)
    return jsonify(results), status_code


@fyox_MaqArtigo_bp.route('/consulta/recobrimentoArtigoMaq', methods=['GET'])
def listar_recobrimento():
    """Endpoint específico para Recobrimento (CdObj 4214)"""
    results, status_code = executar_consulta_objeto(4763)
    return jsonify(results), status_code


# ==========================
# POST - INSERIR USUÁRIO
# ==========================
@fyox_MaqArtigo_bp.route('/usuarios', methods=['POST'])
def inserir_usuario():
    connection = None
    try:
        data_json = request.get_json()

        nm_usr = data_json.get('NmUsr') if data_json else None

        if not nm_usr:
            return jsonify({
                "status": 400,
                "message": "O campo 'NmUsr' é obrigatório."
            }), 400

        connection = create_connection_tinturaria()
        cursor = connection.cursor()

        sql_insert = """
            INSERT INTO Stik_Recobrideira_Usuarios (NmUsr)
            VALUES (?)
        """

        cursor.execute(sql_insert, (nm_usr,))
        connection.commit()

        return jsonify({
            "status": 201,
            "message": "Usuário inserido com sucesso."
        }), 201

    except Exception as e:
        return jsonify({
            "status": 500,
            "error": str(e)
        }), 500

    finally:
        if connection:
            connection.close()


# ==========================
# GET - CONSULTAR TODOS
# ==========================
@fyox_MaqArtigo_bp.route('/usuarios', methods=['GET'])
def listar_usuarios():
    connection = None
    try:
        connection = create_connection_tinturaria()
        cursor = connection.cursor()

        sql_select = """
            SELECT
                Id,
                NmUsr
            FROM Stik_Recobrideira_Usuarios
            ORDER BY Id
        """

        cursor.execute(sql_select)

        columns = [column[0] for column in cursor.description]
        results = [dict(zip(columns, row)) for row in cursor.fetchall()]

        return jsonify({
            "status": 200,
            "data": results
        }), 200

    except Exception as e:
        return jsonify({
            "status": 500,
            "error": str(e)
        }), 500

    finally:
        if connection:
            connection.close()


# ==========================
# GET - CONSULTAR POR ID
# ==========================
@fyox_MaqArtigo_bp.route('/usuarios/<int:id>', methods=['GET'])
def consultar_usuario_por_id(id):
    connection = None
    try:
        connection = create_connection_tinturaria()
        cursor = connection.cursor()

        sql_select = """
            SELECT
                Id,
                NmUsr
            FROM Stik_Recobrideira_Usuarios
            WHERE Id = ?
        """

        cursor.execute(sql_select, (id,))
        row = cursor.fetchone()

        if not row:
            return jsonify({
                "status": 404,
                "message": "Usuário não encontrado."
            }), 404

        result = {
            "Id": row[0],
            "NmUsr": row[1]
        }

        return jsonify({
            "status": 200,
            "data": result
        }), 200

    except Exception as e:
        return jsonify({
            "status": 500,
            "error": str(e)
        }), 500

    finally:
        if connection:
            connection.close()


# ==========================
# DELETE - DELETAR POR ID
# ==========================
@fyox_MaqArtigo_bp.route('/usuarios/<int:id>', methods=['DELETE'])
def deletar_usuario(id):
    connection = None
    try:
        connection = create_connection_tinturaria()
        cursor = connection.cursor()

        sql_verifica = "SELECT Id FROM Stik_Recobrideira_Usuarios WHERE Id = ?"
        cursor.execute(sql_verifica, (id,))
        row = cursor.fetchone()

        if not row:
            return jsonify({
                "status": 404,
                "message": "Usuário não encontrado."
            }), 404

        sql_delete = "DELETE FROM Stik_Recobrideira_Usuarios WHERE Id = ?"
        cursor.execute(sql_delete, (id,))
        connection.commit()

        return jsonify({
            "status": 200,
            "message": "Usuário deletado com sucesso."
        }), 200

    except Exception as e:
        return jsonify({
            "status": 500,
            "error": str(e)
        }), 500

    finally:
        if connection:
            connection.close()