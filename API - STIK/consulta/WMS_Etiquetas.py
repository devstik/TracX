from flask import Blueprint, send_file, request, jsonify, render_template
import qrcode
from PIL import Image, ImageDraw, ImageFont
import io
from database.server import create_connection_tinturaria 

wms_etiquetas_bp = Blueprint('wms_etiquetas', __name__)

def mm_to_px(mm, dpi=300):
    return int((mm * dpi) / 25.4)

# ==============================================================================
# ROTA 1: GERADOR DE ETIQUETA (102x72mm - CENTRALIZADO)
# ==============================================================================
@wms_etiquetas_bp.route('/consulta/wms/gerar_etiqueta', methods=['GET'])
def gerar_etiqueta():
    try:
        endereco = request.args.get('endereco')
        if not endereco:
            return jsonify({"error": "Parâmetro 'endereco' é obrigatório"}), 400

        # --- 1. CONFIGURAÇÕES DA ETIQUETA ---
        DPI = 300
        LARGURA_MM = 102
        ALTURA_MM = 72
        MARGEM_SEGURANCA_MM = 3 # Margem mínima nas bordas para não cortar
        GAP_TEXTO_MM = 2        # Espaço entre o QR Code e o Texto

        # Conversão para Pixels
        img_w = mm_to_px(LARGURA_MM, DPI)
        img_h = mm_to_px(ALTURA_MM, DPI)
        margin = mm_to_px(MARGEM_SEGURANCA_MM, DPI)
        gap = mm_to_px(GAP_TEXTO_MM, DPI)

        # Configura Fonte
        font_size = mm_to_px(9, DPI) # Fonte de ~9mm de altura
        try:
            font = ImageFont.truetype("arialbd.ttf", font_size)
        except IOError:
            try:
                font = ImageFont.truetype("arial.ttf", font_size)
            except IOError:
                font = ImageFont.load_default()

        # Calcula tamanho do texto primeiro para saber quanto sobra pro QR Code
        # Cria uma imagem temporária só para medir o texto
        dummy_draw = ImageDraw.Draw(Image.new('RGB', (1, 1)))
        bbox = dummy_draw.textbbox((0, 0), endereco, font=font)
        text_w = bbox[2] - bbox[0]
        text_h = bbox[3] - bbox[1]

        # --- 2. CÁLCULO DO TAMANHO MÁXIMO DO QR CODE ---
        # Altura disponível = Altura Total - Margens - Texto - Gap
        available_h = img_h - (margin * 2) - text_h - gap
        available_w = img_w - (margin * 2)
        
        # O QR é quadrado, então o tamanho é o menor valor entre altura e largura disponíveis
        qr_size = min(available_h, available_w)

        # --- 3. GERAR IMAGEM ---
        final_img = Image.new('RGB', (img_w, img_h), 'white')
        
        # Gerar QR Code
        qr = qrcode.QRCode(version=1, error_correction=qrcode.constants.ERROR_CORRECT_M, box_size=10, border=0)
        qr.add_data(endereco)
        qr.make(fit=True)
        qr_img = qr.make_image(fill_color="black", back_color="white")
        qr_img = qr_img.resize((qr_size, qr_size), Image.Resampling.LANCZOS)

        # --- 4. CÁLCULO DE POSIÇÃO (CENTRALIZAÇÃO VERTICAL E HORIZONTAL) ---
        # Altura total do conteúdo (Bloco QR + Bloco Texto)
        conteudo_total_h = qr_size + gap + text_h
        
        # Posição Y inicial (para centralizar verticalmente na etiqueta)
        start_y = (img_h - conteudo_total_h) // 2
        
        # Posição X do QR Code (Centralizado horizontalmente)
        qr_x = (img_w - qr_size) // 2
        qr_y = start_y

        # Posição X do Texto (Centralizado horizontalmente)
        text_x = (img_w - text_w) // 2
        text_y = qr_y + qr_size + gap

        # --- 5. COLAGEM ---
        final_img.paste(qr_img, (qr_x, qr_y))
        
        draw = ImageDraw.Draw(final_img)
        draw.text((text_x, text_y), endereco, font=font, fill="black")

        # --- 6. RETORNO ---
        img_io = io.BytesIO()
        final_img.save(img_io, 'PNG')
        img_io.seek(0)

        return send_file(img_io, mimetype='image/png')

    except Exception as e:
        return jsonify({"error": str(e)}), 500

# ==============================================================================
# ROTA 2: LISTAR (Mantida)
# ==============================================================================
@wms_etiquetas_bp.route('/consulta/wms/listar_etiquetas', methods=['GET'])
def listar_etiquetas():
    connection = None
    try:
        connection = create_connection_tinturaria()
        cursor = connection.cursor()
        
        sql = """
            SELECT Endereco 
            FROM dbo.Stik_WMS_Endereco
            WHERE UPPER(TRIM(TipoArea)) = 'PA'
            ORDER BY 
                CAST(REPLACE(Piso, 'L', '') AS INT),
                CAST(REPLACE(Rua, 'R', '') AS INT),
                CAST(REPLACE(Modulo, 'P', '') AS INT)
        """
        cursor.execute(sql)
        enderecos = [row[0] for row in cursor.fetchall()]
        return jsonify(enderecos)
    except Exception as e:
        return jsonify({"error": str(e)}), 500
    finally:
        if connection:
            connection.close()

# ==============================================================================
# ROTA 3: HTML
# ==============================================================================
@wms_etiquetas_bp.route('/consulta/wms/imprimir_etiqueta')
def pagina_impressao():
    return render_template('etiquetas.html')