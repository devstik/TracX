from flask import Blueprint, jsonify, request
# Presume que create_connection_tinturaria está definido em database.server
from database.server import create_connection_tinturaria
import pyodbc # Importa pyodbc, se ainda não estiver importado no arquivo principal

tinturariaDados_bp = Blueprint('tinturariaDados', __name__)

@tinturariaDados_bp.route('/consulta/tinturariaDados', methods=['GET'])
def consultar_tinturaria_dados():
    connection = None
    try:
        connection = create_connection_tinturaria()
        cursor = connection.cursor()

        peso = request.args.get('peso', '0')
        nr_ordem = request.args.get('ordem')

        peso_processado = peso.strip().replace(",", ".")

        try:
            peso_valor = float(peso_processado)
        except ValueError:
            return jsonify({"error": "O parâmetro 'peso' deve ser um número válido."}), 400

        # ✅ MetrosEstimados REMOVIDO do SQL — calculado no Python para evitar divisão por zero
        colunas_select = '''
            P.[ID],
            P.[SkuID],
            P.[SKU],
            P.[NrOrdem],
            CONVERT(varchar, P.[DtPedido], 103) AS DtPedido,
            CONVERT(varchar, P.[DtEntrega], 103) AS DtEntrega,
            CONVERT(varchar, P.[DtLeadtime], 103) AS DtLeadtime,
            COALESCE(P.[Cliente], M.[Cliente]) AS Cliente,
            CASE WHEN E.[PedidoEspecial] = 1 THEN 'Sim' ELSE 'Não' END AS PedidoEspecial,
            P.[Qtd],
            G.[Gramatura] AS Gramatura,
            COALESCE(dbo.fn_MontaCaixasPorFtUap(P.SkuID, P.Qtd), '0') AS Caixa
        '''

        sql_query_base = '''
            FROM Stik_Tinturaria_Programacao P
            LEFT JOIN STIK_OneBeat_OrdensMTA M
                ON P.NrOrdem = M.NrOrdem
            LEFT JOIN TbObj O
                ON O.CdObj = M.CdObj
            LEFT JOIN Stik_PCP_PEDIDOESPECIAL E
                ON E.NrOrdem = P.NrOrdem
            LEFT JOIN TbObj Obj
                ON Obj.CdObj = P.SKUID
            LEFT JOIN Stik_PCP_GRAMATURA G
                ON G.CdObj = Obj.CdObjMae
            LEFT JOIN TbUap Uap (nolock)
                ON Uap.CdObj = Obj.CdObj
            LEFT JOIN TbUnd Und (nolock)
                ON Und.CdUnd = Uap.CdUnd
        '''

        params = []
        where_clause = ''

        if nr_ordem:
            where_clause = ' WHERE P.[NrOrdem] = ? '
            params.append(nr_ordem)

        colunas_group_by = '''
            P.[ID],
            P.[SkuID],
            P.[SKU],
            P.[NrOrdem],
            CONVERT(varchar, P.[DtPedido], 103),
            CONVERT(varchar, P.[DtEntrega], 103),
            CONVERT(varchar, P.[DtLeadtime], 103),
            COALESCE(P.[Cliente], M.[Cliente]),
            E.[PedidoEspecial],
            P.[Qtd],
            G.[Gramatura]
        '''

        sql_query = f'''
            SELECT
                {colunas_select}
            {sql_query_base}
            {where_clause}
            GROUP BY
                {colunas_group_by}
            ORDER BY
                P.[NrOrdem]
        '''

        cursor.execute(sql_query, params)

        registros = []
        for row in cursor.fetchall():
            registro = dict(zip([column[0] for column in cursor.description], row))

            # ✅ Cálculo seguro no Python: sem risco de divisão por zero do SQL Server
            gramatura = registro.get('Gramatura')
            if gramatura and float(gramatura) != 0:
                registro['MetrosEstimados'] = round((peso_valor * 1000.0) / float(gramatura), 4)
            else:
                registro['MetrosEstimados'] = None

            # ✅ Peso injetado diretamente no registro Python
            registro['Peso'] = peso_valor

            registros.append(registro)

        return jsonify(registros)

    except Exception as e:
        print(f"❌ Erro ao consultar tinturaria. Erro: {e}")
        return jsonify({"error": str(e)}), 500

    finally:
        if connection:
            connection.close()

@tinturariaDados_bp.route('/consulta/gramaturaByArtigo', methods=['GET'])
def consultar_gramatura_por_artigo():
    connection = None
    try:
        artigo_nome = request.args.get('artigo_nome')

        if not artigo_nome:
            return jsonify({"error": "Parâmetro 'artigo_nome' não fornecido"}), 400

        connection = create_connection_tinturaria()

        if not connection:
            return jsonify({"error": "Falha ao conectar ao banco de dados"}), 500

        cursor = connection.cursor()

        sql_query = '''
            SELECT TOP 1
                G.[Gramatura]
            FROM TbObj O
            LEFT JOIN Stik_PCP_GRAMATURA G
                ON G.CdObj = O.CdObjMae
            WHERE O.[NmObj] LIKE ? -- AGORA SÓ BUSCA O FINAL DO NOME (EX: %nillo 16 mm)
            AND G.[Gramatura] IS NOT NULL
            ORDER BY O.[CdObj] DESC
        '''

        params = (f'%{artigo_nome.strip()}',)

        cursor.execute(sql_query, params)
        result = cursor.fetchone()

        if result and result[0] is not None:
            return jsonify({"Gramatura": result[0]}), 200
        else:
            return jsonify({"Gramatura": "0.00"}), 200

    except Exception as e:
        print(f"❌ Erro ao consultar gramatura por artigo: {e}")
        return jsonify({"error": str(e)}), 500

    finally:
        if connection:
            connection.close()

@tinturariaDados_bp.route('/consulta/allArtigos', methods=['GET'])
def consultar_todos_artigos():
    """Retorna TODOS os artigos disponíveis do banco com suas gramaturas."""
    connection = None
    try:
        connection = create_connection_tinturaria()

        if not connection:
            return jsonify({"error": "Falha ao conectar ao banco de dados"}), 500

        cursor = connection.cursor()

        sql_query = '''
            SELECT
                O.NmObj,
                G.Gramatura
            FROM TbObj O
            LEFT JOIN Stik_PCP_GRAMATURA G
                ON G.CdObj = O.CdObjMae
            WHERE G.Gramatura IS NOT NULL
            ORDER BY O.CdObj DESC
        '''

        cursor.execute(sql_query)
        results = cursor.fetchall()

        artigos = []
        for row in results:
            artigos.append({
                "Artigo": row[0],
                "Gramatura": row[1]
            })

        return jsonify(artigos), 200

    except Exception as e:
        print(f"❌ Erro ao consultar todos os artigos: {e}")
        return jsonify({"error": str(e)}), 500

    finally:
        if connection:
            connection.close()


# --- Blueprint para Consulta de Operador ---
tinturariaOperador_bp = Blueprint('tinturariaOperador', __name__)

@tinturariaOperador_bp.route('/consulta/operador', methods=['GET'])
def consultar_operador():
    connection = None
    try:
        matricula = request.args.get('matricula')

        if matricula:
            try:
                matricula_int = int(matricula)
                matricula = str(matricula_int)
            except ValueError:
                return jsonify({"Operador": "Matrícula inválida ou não numérica"}), 400

        connection = create_connection_tinturaria()

        if not connection:
            return jsonify({"error": "Falha ao conectar ao banco de dados"}), 500

        cursor = connection.cursor()

        sql_query = '''
            SELECT
                Matricula,
                Operador,
                Apelido
            FROM dbo.Stik_Tinturaria_Operador (NOLOCK)
        '''

        params = ()

        if matricula:
            sql_query += ' WHERE Matricula = ?'
            params = (matricula,)

        cursor.execute(sql_query, params)


        if matricula:
            result = cursor.fetchone()

            if result:
                operador_info = {
                    "Matricula": result[0],
                    "Operador": result[1],
                    "Apelido": result[2]
                }
                return jsonify(operador_info), 200
            else:
                return jsonify({"Operador": "Operador não encontrado"}), 404

        else:
            registros = [
                dict(zip([column[0] for column in cursor.description], row))
                for row in cursor.fetchall()
            ]
            return jsonify(registros), 200

    except Exception as e:
        print(f"❌ Erro ao consultar operador: {e}")
        return jsonify({"error": str(e)}), 500

    finally:
        if connection:
            connection.close()

# --- Nova Rota para Salvar Peso, Ordem e Data ---
@tinturariaDados_bp.route('/salvar/pesoOrdem', methods=['POST'])
def salvar_peso_ordem():
    connection = None
    try:
        # Tenta pegar dados via JSON (padrão) ou via Form/Args
        data = request.get_json() or request.args or request.form
        
        ordem = data.get('Nrordem')
        peso = data.get('peso')
        data_registro = data.get('data') # Formato esperado: YYYY-MM-DD

        # Validação básica
        if not ordem or not peso:
            return jsonify({"error": "Parâmetros 'ordem' e 'peso' são obrigatórios."}), 400

        # Tratamento do Peso (trocar vírgula por ponto)
        try:
            peso = str(peso).replace(',', '.')
            peso_float = float(peso)
        except ValueError:
            return jsonify({"error": "Peso inválido."}), 400

        # Tratamento da Data (Se não vier, usa a data de hoje)
        if not data_registro:
            data_registro = datetime.now().strftime('%Y-%m-%d')

        connection = create_connection_tinturaria()
        cursor = connection.cursor()

        # Query de Inserção (Alinhada com sua Tabela SQL)
        sql_insert = '''
            INSERT INTO Stik_OrdensMTAPeso (Data, NrOrdem, Peso)
            VALUES (?, ?, ?)
        '''
        
        # ⚠️ CORREÇÃO AQUI: A ordem das variáveis deve bater com a ordem do INSERT acima
        # INSERT (Data, NrOrdem, Peso) -> values (data_registro, ordem, peso_float)
        cursor.execute(sql_insert, (data_registro, ordem, peso_float))
        
        connection.commit() 

        return jsonify({"message": "Registro salvo com sucesso!", "ordem": ordem, "peso": peso_float}), 201

    except Exception as e:
        print(f"❌ Erro ao salvar peso/ordem: {e}")
        if connection:
            connection.rollback()
        return jsonify({"error": str(e)}), 500

    finally:
        if connection:
            connection.close()