from flask import Blueprint, jsonify, request
from database.server import create_connection

tinturaria_bp = Blueprint('tinturaria', __name__)

@tinturaria_bp.route('/consulta/tinturaria', methods=['GET', 'POST'])
def gerenciar_tinturaria():
    connection = None
    try:
        connection = create_connection()
        cursor = connection.cursor()

        if request.method == 'POST':
            data = request.get_json()

            if not data:
                return jsonify({"error": "Dados JSON não fornecidos ou inválidos"}), 400

            # Mapeia para os novos nomes de colunas do banco de dados
            dataCorte = data.get('dataCorte')
            nomeMaterial = data.get('nomeMaterial')
            larguraCrua = data.get('larguraCrua')
            elasticidadeCrua = data.get('elasticidadeCrua')
            nMaquina = data.get('nMaquina')
            loteElastico = data.get('loteElastico')
            conferente = data.get('conferente')
            turno = data.get('turno')

            campos_obrigatorios = [dataCorte, nomeMaterial, larguraCrua, elasticidadeCrua, nMaquina, loteElastico, conferente, turno]

            if any(campo is None for campo in campos_obrigatorios):
                return jsonify({"error": "Todos os campos obrigatórios devem ser fornecidos"}), 400

            insert_sql = """
                INSERT INTO TbRegTinturaria (dataCorte, nomeMaterial, larguraCrua, elasticidadeCrua, nMaquina, loteElastico, conferente, turno)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?)
            """

            cursor.execute(
                insert_sql,
                (dataCorte, nomeMaterial, larguraCrua, elasticidadeCrua, nMaquina, loteElastico, conferente, turno)
            )
            connection.commit()

            print(f"✅ Registro criado com sucesso: {data}")
            return jsonify({"message": "Registro criado com sucesso!"}), 201

        cursor.execute('''
            SELECT
                ID = Emb.ID,
                dataCorte = Emb.dataCorte,
                nomeMaterial = Emb.nomeMaterial,
                larguraCrua = Emb.larguraCrua,
                elasticidadeCrua = Emb.elasticidadeCrua,
                nMaquina = Emb.nMaquina,
                loteElastico = Emb.loteElastico,
                conferente = Emb.conferente,
                turno = Emb.turno
            FROM TbRegTinturaria Emb (nolock)
            ORDER BY Emb.ID ASC
        ''')

        registros = [dict(zip([column[0] for column in cursor.description], row)) for row in cursor.fetchall()]
        return jsonify(registros)

    except Exception as e:
        print(f"❌ Erro ao gerenciar tinturaria: {e}")
        return jsonify({"error": str(e)}), 500

    finally:
        if connection:
            connection.close()