from flask import Blueprint, request, jsonify
import qrcode
from datetime import datetime
from PIL import Image, ImageDraw, ImageFont
from zpl import Label
import uuid
import sqlite3
import os

wms_separacao_bp = Blueprint('wms_separacao', __name__)

# Configuração do Banco de Dados SQLite
DB_PATH = 'fila_impressao.db'

def get_db_connection():
    """Cria uma conexão com o banco de dados e configura para retornar dicionários."""
    conn = sqlite3.connect(DB_PATH)
    conn.row_factory = sqlite3.Row
    return conn

def init_db():
    with get_db_connection() as conn:
        conn.execute('''
            CREATE TABLE IF NOT EXISTS fila_impressao (
                id TEXT PRIMARY KEY,
                endereco TEXT,
                zpl TEXT,
                status TEXT DEFAULT 'PENDENTE', -- NOVO: Para controlar o fluxo
                criado_em TIMESTAMP DEFAULT CURRENT_TIMESTAMP
            )
        ''')
        conn.commit()

# Inicializa o banco ao carregar o blueprint
init_db()

def _gerar_imagem_separacao_fiel(romaneio, pedido, cliente, separador_nome):
    try:
        LARGURA, ALTURA = 800, 560
        img = Image.new('L', (LARGURA, ALTURA), 255)
        draw = ImageDraw.Draw(img)

        margem_esquerda = 60
        margem_direita = 20
        QR_SIZE = 130
        QR_X = LARGURA - QR_SIZE - margem_direita  # 650

        try:
            font_bold = ImageFont.truetype("arialbd.ttf", 48)
            font_reg = ImageFont.truetype("arial.ttf", 36)
        except:
            font_bold = ImageFont.load_default()
            font_reg = ImageFont.load_default()

        data_atual = datetime.now().strftime('%d/%m/%Y')
        qr_data = f"romaneio:{romaneio};pedido:{pedido}"

        # --- Título ---
        draw.text((margem_esquerda, 20), "Etiqueta de Separacao", font=font_bold, fill=0)

        # --- QR Code ---
        qr = qrcode.QRCode(version=1, box_size=10, border=0)
        qr.add_data(qr_data)
        qr.make(fit=True)
        qr_img = qr.make_image().convert('L')
        qr_img = qr_img.resize((QR_SIZE, QR_SIZE), Image.Resampling.NEAREST)
        img.paste(qr_img, (QR_X, 20))

        # --- Função auxiliar: trunca texto para caber em max_px ---
        def truncar(texto, font, max_px):
            while len(texto) > 0:
                w = draw.textlength(texto, font=font)
                if w <= max_px:
                    return texto
                texto = texto[:-1]
            return texto

        y_cursor = 120
        espacamento = 50

        # Largura disponível levando em conta o QR nas primeiras linhas
        def largura_disponivel(y, altura_linha=40):
            # Se a linha sobrepõe a área vertical do QR (y=20 até y=20+QR_SIZE)
            if y < (20 + QR_SIZE) and (y + altura_linha) > 20:
                return QR_X - margem_esquerda - 10  # ~580px
            return LARGURA - margem_esquerda - margem_direita  # ~720px

        # Data
        draw.text((margem_esquerda, y_cursor),
                  f"Data: {data_atual}", font=font_reg, fill=0)
        y_cursor += espacamento

        # Romaneio
        draw.text((margem_esquerda, y_cursor),
                  f"Romaneio: {romaneio}", font=font_reg, fill=0)
        y_cursor += espacamento

        # Pedido
        draw.text((margem_esquerda, y_cursor),
                  f"Pedido: {pedido}", font=font_reg, fill=0)
        y_cursor += espacamento

        # Cliente — duas linhas se necessário
        cliente_str = str(cliente)
        prefixo = "Cliente: "
        linha1_max = largura_disponivel(y_cursor)
        linha1_texto = truncar(prefixo + cliente_str, font_reg, linha1_max)
        draw.text((margem_esquerda, y_cursor), linha1_texto, font=font_reg, fill=0)

        restante = cliente_str[len(linha1_texto) - len(prefixo):]
        if restante:
            y_cursor += espacamento
            linha2_max = largura_disponivel(y_cursor)
            linha2_texto = truncar(restante, font_reg, linha2_max)
            draw.text((margem_esquerda, y_cursor), linha2_texto, font=font_reg, fill=0)

        y_cursor += espacamento

        # Rodapé — separador truncado para caber na linha inteira
        linha_rodape_max = largura_disponivel(y_cursor)
        sufixo = f" | {data_atual}"
        # Reserva espaço para o sufixo e trunca só o nome
        sufixo_px = draw.textlength(sufixo, font=font_reg)
        prefixo_sep = "Separador: "
        prefixo_px = draw.textlength(prefixo_sep, font=font_reg)
        nome_max_px = linha_rodape_max - prefixo_px - sufixo_px
        nome_truncado = truncar(str(separador_nome), font_reg, nome_max_px)
        texto_rodape = f"{prefixo_sep}{nome_truncado}{sufixo}"
        draw.text((margem_esquerda, y_cursor), texto_rodape, font=font_reg, fill=0)

        return img.point(lambda x: 0 if x < 128 else 255, '1')

    except Exception as e:
        print(f"Erro ao gerar imagem: {e}")
        raise

@wms_separacao_bp.route('/consulta/wms/imprimir_separacao_api', methods=['POST'])
def imprimir_separacao_api():
    try:
        data = request.get_json()
        
        
        img_pil = _gerar_imagem_separacao_fiel(
            data.get('romaneio', ''),
            data.get('pedido', ''),
            data.get('cliente', ''),
            data.get('separador', '---')
        )
        
        label = Label(width=102, height=72, dpmm=8)
        label.write_graphic(img_pil, width=102, height=72)
        
        item_id = str(uuid.uuid4())[:8]
        zpl_str = label.dumpZPL()
        endereco = f"SEP {data.get('pedido')}"

        # Inserção no Banco de Dados
        with get_db_connection() as conn:
            conn.execute(
                "INSERT INTO fila_impressao (id, endereco, zpl) VALUES (?, ?, ?)",
                (item_id, endereco, zpl_str)
            )
            conn.commit()
        
        print(f"✅ Item {item_id} persistido no banco.")
        return jsonify({"status": "ok", "id": item_id})
    except Exception as e:
        print(f"❌ Erro na API: {str(e)}")
        return jsonify({"error": str(e)}), 500

@wms_separacao_bp.route('/consulta/wms/buscar_impressao', methods=['GET'])
def buscar_impressao():
    try:
        with get_db_connection() as conn:
            cursor = conn.cursor()
            cursor.execute("SELECT id, endereco, zpl FROM fila_impressao ORDER BY criado_em ASC LIMIT 1")
            row = cursor.fetchone()
            if row:
                return jsonify({"id": row['id'], "endereco": row['endereco'], "zpl": row['zpl']})
        return jsonify(None), 204
    except Exception as e:
        return jsonify({"error": str(e)}), 500

@wms_separacao_bp.route('/consulta/wms/confirmar_impressao/<item_id>', methods=['DELETE'])
def confirmar_impressao(item_id):
    try:
        with get_db_connection() as conn:
            conn.execute("DELETE FROM fila_impressao WHERE id = ?", (item_id,))
            conn.commit()
        return jsonify({"status": "ok", "message": "Item removido após sucesso"}), 200
    except Exception as e:
        return jsonify({"error": str(e)}), 500

@wms_separacao_bp.route('/consulta/wms/limpar_fila_emergencia', methods=['POST'])
def limpar_fila_emergencia():
    try:
        with get_db_connection() as conn:
            conn.execute("DELETE FROM fila_impressao")
            conn.commit()
        return jsonify({"status": "Fila limpa com sucesso no banco de dados"})
    except Exception as e:
        return jsonify({"error": str(e)}), 500