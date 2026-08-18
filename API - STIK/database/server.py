import pyodbc

def create_connection():
    server = '168.190.30.18'
    database = 'EmbalagemIn'
    username = 'sa'
    password = 'Stik0123'
    
    # Criar a string de conexão
    connection_string = f'DRIVER={{SQL Server}};SERVER={server};DATABASE={database};UID={username};PWD={password}'
    
    # Estabelecer a conexão com o banco de dados
    try:
        conn = pyodbc.connect(connection_string)
        return conn
    except pyodbc.Error as e:
        print(f'Erro ao conectar ao banco de dados: {str(e)}')
        return None
    
def create_connection_ordens():
    server = '168.190.30.18'
    database = 'Db_OneUsers'
    username = 'sa'
    password = 'Stik0123'
    
    # Criar a string de conexão
    connection_string = f'DRIVER={{SQL Server}};SERVER={server};DATABASE={database};UID={username};PWD={password}'
    
    # Estabelecer a conexão com o banco de dados
    try:
        conn = pyodbc.connect(connection_string)
        return conn
    except pyodbc.Error as e:
        print(f'Erro ao conectar ao banco de dados: {str(e)}')
        return None

def create_connection_EAN():
    server = '168.190.30.18'
    database = 'EAN13'
    username = 'sa'
    password = 'Stik0123'
    
    # Criar a string de conexão
    connection_string = f'DRIVER={{SQL Server}};SERVER={server};DATABASE={database};UID={username};PWD={password}'
    
    # Estabelecer a conexão com o banco de dados
    try:
        conn = pyodbc.connect(connection_string)
        return conn
    except pyodbc.Error as e:
        print(f'Erro ao conectar ao banco de dados: {str(e)}')
        return None
    
    
def create_connection_tinturaria():
    server = '54.207.186.54'
    database = 'Stik'
    username = 'ti'
    password = 'Supstk@400'

    connection_string = (
        f"DRIVER={{ODBC Driver 17 for SQL Server}};"
        f"SERVER={server};"
        f"DATABASE={database};"
        f"UID={username};"
        f"PWD={password};"
        "TrustServerCertificate=yes;"
    )

    try:
        conn = pyodbc.connect(connection_string, timeout=5)
        print("✅ Conectado ao banco de dados Stik com sucesso.")
        return conn
    except pyodbc.Error as e:
        print(f"❌ Erro ao conectar ao banco de dados: {e}")
        return None
   