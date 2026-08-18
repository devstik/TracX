from flask import Blueprint, jsonify, request
from database.server import create_connection
from flask_bcrypt import Bcrypt

usuarios_bp = Blueprint('usuarios', __name__)
bcrypt = Bcrypt()

@usuarios_bp.route('/consulta/cadastro', methods=['POST'])
def cadastrar_usuario():
    connection = None
    try:
        print("🟡 Tentando cadastrar novo usuário...")
        connection = create_connection()
        cursor = connection.cursor()
        data = request.get_json()

        if not data or 'usuario' not in data or 'senha' not in data:
            print("🔴 Erro: Dados de usuário ou senha não fornecidos.")
            return jsonify({"error": "Dados de usuário ou senha não fornecidos"}), 400

        usuario = data['usuario']
        senha = data['senha']
        
        # 🔐 Criptografa a senha antes de salvar
        senha_hash = bcrypt.generate_password_hash(senha).decode('utf-8')
        print(f"✅ Senha do usuário '{usuario}' criptografada.")

        # Verifica se o usuário já existe no banco
        print(f"🔎 Verificando se o usuário '{usuario}' já existe no banco...")
        cursor.execute("SELECT 1 FROM Users WHERE usuario = ?", (usuario,))
        if cursor.fetchone():
            print(f"❌ Erro de cadastro: O usuário '{usuario}' já existe.")
            return jsonify({"success": False, "message": "Usuário já existe"}), 409

        insert_sql = """
            INSERT INTO Users (usuario, senha)
            VALUES (?, ?)
        """
        print(f"➕ Inserindo novo usuário '{usuario}' no banco de dados...")
        cursor.execute(insert_sql, (usuario, senha_hash))
        connection.commit()
        print(f"🎉 Usuário '{usuario}' cadastrado e commit realizado.")

        return jsonify({"success": True, "message": "Usuário cadastrado com sucesso"}), 201

    except Exception as e:
        print(f"❌ Erro ao cadastrar usuário: {e}")
        return jsonify({"success": False, "message": str(e)}), 500

    finally:
        if connection:
            connection.close()
            print("🔗 Conexão com o banco de dados fechada.")

@usuarios_bp.route('/consulta/login', methods=['GET'])
def login_usuario():
    connection = None
    try:
        print("🟡 Tentativa de login recebida (GET).")
        connection = create_connection()
        cursor = connection.cursor()

        # Captura parâmetros da URL
        usuario = request.args.get('usuario')
        senha = request.args.get('senha')

        if not usuario or not senha:
            print("🔴 Erro: Parâmetros de login incompletos.")
            return jsonify({"success": False, "message": "Parâmetros 'usuario' e 'senha' são obrigatórios"}), 400

        print(f"🕵️‍♂️ Tentando logar com usuário: '{usuario}' e senha recebida: '{senha}'.")

        cursor.execute("SELECT senha FROM Users WHERE usuario = ?", (usuario,))
        resultado = cursor.fetchone()

        if resultado:
            senha_banco = resultado[0]
            print(f"🔑 Senha recuperada do banco: '{senha_banco}'")

            # Verifica se a senha é hash bcrypt
            if senha_banco.startswith("$2"):
                senha_correta = bcrypt.check_password_hash(senha_banco, senha)
            else:
                # fallback se a senha antiga estiver em texto puro
                senha_correta = senha_banco == senha

            print(f"🔑 Resultado da verificação da senha: {senha_correta}")

            if senha_correta:
                print(f"🎉 Login bem-sucedido para o usuário '{usuario}'.")
                return jsonify({"success": True, "message": "Login bem-sucedido"}), 200
            else:
                print(f"❌ Senha incorreta.")
                return jsonify({"success": False, "message": "Usuário ou senha inválidos"}), 401
        else:
            print(f"❌ Usuário não encontrado.")
            return jsonify({"success": False, "message": "Usuário ou senha inválidos"}), 401

    except Exception as e:
        print(f"❌ Erro no login: {e}")
        return jsonify({"success": False, "message": str(e)}), 500

    finally:
        if connection:
            connection.close()
            print("🔗 Conexão com o banco fechada.")



@usuarios_bp.route('/consulta/usuarios', methods=['GET'])
def listar_usuarios():
    connection = None
    try:
        print("🟡 Requisição GET para listar usuários recebida.")
        connection = create_connection()
        cursor = connection.cursor()

        print("🔎 Consultando todos os usuários no banco de dados...")
        cursor.execute("SELECT usuario FROM Users")
        usuarios = [row[0] for row in cursor.fetchall()]

        print(f"✅ Usuários encontrados: {usuarios}")
        return jsonify(usuarios), 200

    except Exception as e:
        print(f"❌ Erro ao listar usuários: {e}")
        return jsonify({"success": False, "message": str(e)}), 500

    finally:
        if connection:
            connection.close()
            print("🔗 Conexão com o banco de dados fechada.")


@usuarios_bp.route('/consulta/usuarios/<string:usuario>', methods=['DELETE'])
def deletar_usuario(usuario):
    connection = None
    try:
        connection = create_connection()
        cursor = connection.cursor()

        cursor.execute("SELECT 1 FROM Users WHERE usuario = ?", (usuario,))
        if not cursor.fetchone():
            return jsonify({"success": False, "message": "Usuário não encontrado"}), 404

        cursor.execute("DELETE FROM Users WHERE usuario = ?", (usuario,))
        connection.commit()
        return jsonify({"success": True, "message": "Usuário deletado"}), 200

    except Exception as e:
        return jsonify({"success": False, "message": str(e)}), 500

    finally:
        if connection:
            connection.close()

@usuarios_bp.route('/consulta/usuarios/alterar_senha', methods=['PUT'])
def alterar_senha():
    connection = None
    try:
        data = request.get_json()
        usuario = data.get("usuario")
        nova_senha = data.get("nova_senha")

        if not usuario or not nova_senha:
            return jsonify({"success": False, "message": "Usuário ou senha não fornecidos"}), 400

        connection = create_connection()
        cursor = connection.cursor()

        # Criptografa a nova senha
        nova_senha_hash = bcrypt.generate_password_hash(nova_senha).decode('utf-8')

        # Atualiza senha
        cursor.execute("UPDATE Users SET senha = ? WHERE usuario = ?", (nova_senha_hash, usuario))
        connection.commit()

        return jsonify({"success": True, "message": "Senha alterada com sucesso"}), 200

    except Exception as e:
        return jsonify({"success": False, "message": str(e)}), 500

    finally:
        if connection:
            connection.close()

