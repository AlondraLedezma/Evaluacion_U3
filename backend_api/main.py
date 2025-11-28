from fastapi import FastAPI, UploadFile, File, Form, HTTPException
from fastapi.staticfiles import StaticFiles 
from fastapi.middleware.cors import CORSMiddleware 
from pydantic import BaseModel
import mysql.connector
from passlib.context import CryptContext
import os
from datetime import datetime

app = FastAPI()

# --- 1. CONFIGURACIÓN CORS ---

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"], 
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# --- 2. CARPETA DE IMÁGENES ---
# Carpeta 'uploads' para almacenar las fotos de entregas
os.makedirs("uploads", exist_ok=True) 
app.mount("/uploads", StaticFiles(directory="uploads"), name="uploads")

# --- 3. SEGURIDAD (HASHING) ---
# Configuración para encriptar contraseñas.
pwd_context = CryptContext(schemes=["argon2"], deprecated="auto")

# --- 4. BASE DE DATOS ---

db_config = {
    'user': 'root',
    'password': '',       
    'host': 'localhost',
    'database': 'paquexpress_db'
}

# --- 5. MODELOS DE DATOS ---
class LoginModel(BaseModel):
    username: str
    password: str

class RegistroModel(BaseModel):
    username: str
    password: str
    nombre_completo: str

# --- 6. ENDPOINTS ---

# A) REGISTRO DE USUARIO (NUEVO)

@app.post("/registro")
def registrar_usuario(user: RegistroModel):
    # Encriptamos la contraseña antes de guardarla
    hashed_password = pwd_context.hash(user.password)
    
    conn = mysql.connector.connect(**db_config)
    cursor = conn.cursor()
    
    try:
        sql = "INSERT INTO usuarios (username, password_hash, nombre_completo) VALUES (%s, %s, %s)"
        val = (user.username, hashed_password, user.nombre_completo)
        cursor.execute(sql, val)
        conn.commit()
        user_id = cursor.lastrowid
        conn.close()
        return {"status": "Usuario registrado exitosamente", "id": user_id}
    except mysql.connector.Error as err:
        conn.close()
        # Si el usuario ya existe, avisamos
        raise HTTPException(status_code=400, detail=f"Error al registrar: {err}")

# B) LOGIN SEGURO
@app.post("/login")
def login(user: LoginModel):
    conn = mysql.connector.connect(**db_config)
    cursor = conn.cursor(dictionary=True)
    
    # Buscamos al usuario por su username
    cursor.execute("SELECT * FROM usuarios WHERE username = %s", (user.username,))
    usuario = cursor.fetchone()
    conn.close()
    
    # Verificamos: 1. Que el usuario exista. 2. Que la contraseña coincida con el hash.
    if not usuario or not pwd_context.verify(user.password, usuario['password_hash']):
        raise HTTPException(status_code=401, detail="Credenciales incorrectas")
    
    return {"status": "ok", "user_id": usuario['id'], "nombre": usuario['nombre_completo']}

# C) OBTENER PAQUETES
@app.get("/paquetes/{agente_id}")
def get_paquetes(agente_id: int):
    conn = mysql.connector.connect(**db_config)
    cursor = conn.cursor(dictionary=True)
    # Trae solo los paquetes pendientes asignados a este agente
    cursor.execute("SELECT * FROM paquetes WHERE agente_asignado_id = %s AND estado = 'pendiente'", (agente_id,))
    paquetes = cursor.fetchall()
    conn.close()
    return paquetes

# D) REGISTRAR ENTREGA (FOTO + GPS)
@app.post("/entregar")
async def entregar_paquete(
    id_paquete: int = Form(...),
    latitud: float = Form(...),
    longitud: float = Form(...),
    foto: UploadFile = File(...)
):
    # Generar nombre único para la foto
    timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
    nombre_foto = f"evidencia_{id_paquete}_{timestamp}.jpg"
    ruta_guardado = f"uploads/{nombre_foto}"
    
    # Guardar archivo en la carpeta
    with open(ruta_guardado, "wb") as buffer:
        buffer.write(await foto.read())
    
    # Actualizar la base de datos
    conn = mysql.connector.connect(**db_config)
    cursor = conn.cursor()
    sql = """UPDATE paquetes SET 
             estado = 'entregado', 
             latitud = %s, 
             longitud = %s, 
             foto_evidencia = %s, 
             fecha_entrega = %s 
             WHERE id = %s"""
    val = (latitud, longitud, nombre_foto, datetime.now(), id_paquete)
    cursor.execute(sql, val)
    conn.commit()
    conn.close()
    
    return {"status": "Entrega registrada exitosamente"}