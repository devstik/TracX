from flask import Blueprint, jsonify, request
from database.server import create_connection
from datetime import datetime
# Define o Blueprint, que é a forma de organizar rotas no Flask
embalagem_bp = Blueprint('embalagem', __name__)




@embalagem_bp.route('/consulta/embalagem', methods=['GET', 'POST'])
def gerenciar_embalagem():
    connection = None
    try:
        connection = create_connection()
        cursor = connection.cursor()

        if request.method == 'POST':
            data = request.get_json()

            if not data:
                return jsonify({"error": "Dados JSON não fornecidos ou inválidos"}), 400

            # Extrai os dados do JSON
            Data = data.get('Data')
            Nrordem = data.get('NrOrdem')
            Artigo = data.get('Artigo')
            Cor = data.get('Cor')
            Quantidade = data.get('Quantidade')
            Peso = data.get('Peso')
            Conferente = data.get('Conferente')
            Turno = data.get('Turno')
            Metros = data.get('Metros')
            DataTingimento = data.get('DataTingimento')
            NumCorte = data.get('NumCorte')
            VolumeProg = data.get('VolumeProg')
            Caixa = data.get('Caixa')

            campos_obrigatorios = [
                Data, Nrordem, Artigo, Cor, Quantidade,
                Peso, Conferente, Turno, Metros, VolumeProg
            ]

            if any(campo is None for campo in campos_obrigatorios):
                return jsonify({"error": "Todos os campos obrigatórios devem ser fornecidos"}), 400

            insert_sql = """
                INSERT INTO TbRegEmbalagem
                (
                    Data, NrOrdem, Artigo, Cor, Quantidade, Peso,
                    Conferente, Turno, Metros, DataTingimento,
                    NumCorte, VolumeProg, Caixa
                )
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            """

            cursor.execute(
                insert_sql,
                (
                    Data, Nrordem, Artigo, Cor, Quantidade, Peso,
                    Conferente, Turno, Metros, DataTingimento,
                    NumCorte, VolumeProg, Caixa
                )
            )
            connection.commit()

            return jsonify({"message": "Registro de embalagem criado com sucesso!"}), 201

        cursor.execute('''
            SELECT
                ID = Emb.ID,
                Data = Emb.Data,
                NrOrdem = Emb.NrOrdem,
                Artigo = Emb.Artigo,
                Cor = Emb.Cor,
                Quantidade = Emb.Quantidade,
                Peso = Emb.Peso,
                Conferente = Emb.Conferente,
                Turno = Emb.Turno,
                Metros = Emb.Metros,
                DataTingimento = Emb.DataTingimento,
                NumCorte = Emb.NumCorte,
                VolumeProg = Emb.VolumeProg,
                Caixa = Emb.Caixa
            FROM TbRegEmbalagem Emb (NOLOCK)
            ORDER BY Emb.ID ASC
        ''')

        embalagens = [
            dict(zip([column[0] for column in cursor.description], row))
            for row in cursor.fetchall()
        ]

        return jsonify(embalagens)

    except Exception as e:
        print(f"❌ Erro ao gerenciar embalagem: {e}")
        return jsonify({"error": str(e)}), 500

    finally:
        if connection:
            connection.close()


@embalagem_bp.route('/consulta/embalagem/<int:id>', methods=['PATCH'])
def atualizar_embalagem(id):
    connection = None
    try:
        connection = create_connection()
        cursor = connection.cursor()

        data = request.get_json()

        if not data:
            return jsonify({"error": "Dados JSON não fornecidos ou inválidos"}), 400

        # Campos permitidos para atualização
        campos_permitidos = {
            "Data": "Data",
            "NrOrdem": "NrOrdem",
            "Artigo": "Artigo",
            "Cor": "Cor",
            "Quantidade": "Quantidade",
            "Peso": "Peso",
            "Conferente": "Conferente",
            "Turno": "Turno",
            "Metros": "Metros",
            "DataTingimento": "DataTingimento",
            "NumCorte": "NumCorte",
            "VolumeProg": "VolumeProg",
            "Caixa": "Caixa"
        }

        campos_para_atualizar = []
        valores = []

        for chave_json, coluna_banco in campos_permitidos.items():
            if chave_json in data:
                campos_para_atualizar.append(f"{coluna_banco} = ?")
                valores.append(data[chave_json])

        if not campos_para_atualizar:
            return jsonify({"error": "Nenhum campo válido foi enviado para atualização"}), 400

        # Verifica se o registro existe
        cursor.execute("SELECT 1 FROM TbRegEmbalagem WHERE ID = ?", (id,))
        registro = cursor.fetchone()

        if not registro:
            return jsonify({"error": f"Registro com ID {id} não encontrado"}), 404

        update_sql = f"""
            UPDATE TbRegEmbalagem
            SET {', '.join(campos_para_atualizar)}
            WHERE ID = ?
        """

        valores.append(id)
        cursor.execute(update_sql, tuple(valores))
        connection.commit()

        # Retorna o registro atualizado
        cursor.execute("""
            SELECT
                ID,
                Data,
                NrOrdem,
                Artigo,
                Cor,
                Quantidade,
                Peso,
                Conferente,
                Turno,
                Metros,
                DataTingimento,
                NumCorte,
                VolumeProg,
                Caixa
            FROM TbRegEmbalagem
            WHERE ID = ?
        """, (id,))

        row = cursor.fetchone()
        colunas = [column[0] for column in cursor.description]
        registro_atualizado = dict(zip(colunas, row))

        return jsonify({
            "message": "Registro de embalagem atualizado com sucesso!",
            "data": registro_atualizado
        }), 200

    except Exception as e:
        print(f"❌ Erro ao atualizar embalagem: {e}")
        return jsonify({"error": str(e)}), 500

    finally:
        if connection:
            connection.close()