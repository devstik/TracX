from flask import Blueprint, jsonify, request
from database.server import create_connection

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

            Data = data.get('Data')
            nr_ordem = data.get('NrOrdem')
            artigo = data.get('Artigo')
            cor = data.get('Cor')
            quantidade = data.get('Quantidade')
            qt_peso = data.get('QtPeso')
            conferente = data.get('Conferente')
            turno = data.get('Turno')
            metros = data.get('Metros')

            if not all([Data, nr_ordem, artigo, cor, quantidade, qt_peso, conferente, turno, metros]):
                return jsonify({"error": "Todos os campos obrigatórios devem ser fornecidos"}), 400

            insert_sql = """
                INSERT INTO TbRegistro (Data, NrOrdem, Artigo, Cor, Quantidade, QtPeso, Conferente, Turno, Metros)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
            """
            
            cursor.execute(
                insert_sql,
                Data, nr_ordem, artigo, cor, quantidade, qt_peso, conferente, turno,  metros
            )
            
            connection.commit()
            
           
            print(f"Registro criado: {data}") 

       
        cursor.execute('''
            SELECT
                ID = Emb.ID,
                Data = Emb.Data,
                NrOrdem = Emb.NrOrdem,
                Artigo = Emb.Artigo,
                Cor = Emb.Cor,
                Quantidade = Emb.Quantidade,
                QtPeso = Emb.QtPeso,
                Conferente = Emb.Conferente,
                Turno = Emb.Turno,
                Metros = Emb.Metros
            FROM TbRegistro Emb (nolock)
            WHERE 1=1
            ORDER BY Emb.ID ASC
        ''')
        
        print(cursor) 
        
        embalagens = [dict(zip([column[0] for column in cursor.description], row)) for row in cursor.fetchall()]
        
        return jsonify(embalagens)
        
    except Exception as e:
        print(f"Erro ao gerenciar embalagem: {e}")
        return jsonify({"error": str(e)}), 500
    finally:
        if connection:
            connection.close()