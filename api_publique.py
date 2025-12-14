import json
import os
from flask import Flask, request, jsonify
import database # On importe notre gestionnaire BDD

app = Flask(__name__)
CONFIG_FILE = 'config.json'

# Initialisation de la BDD au démarrage
database.init_db()

def get_orders_config():
    if not os.path.exists(CONFIG_FILE): return {}
    try:
        with open(CONFIG_FILE, 'r') as f: return json.load(f)
    except: return {}

# --- ROUTE 1 : RECRUTEMENT (Premier appel seulement) ---
@app.route('/api/register', methods=['POST'])
def register():
    # L'ESP32 appelle ça la toute première fois
    client_ip = request.remote_addr
    token = database.register_soldier(client_ip)
    print(f"[+] NOUVEAU SOLDAT ENRÔLÉ : IP {client_ip} -> TOKEN {token}")
    return jsonify({"status": "registered", "token": token})

# --- ROUTE 2 : HEARTBEAT & ORDRES (Appelé chaque minute) ---
@app.route('/api/heartbeat', methods=['POST'])
def heartbeat():
    data = request.json
    token = data.get('token')
    
    if not token:
        return jsonify({"error": "No token provided"}), 401

    # Vérification du mot de passe (Token) dans la BDD
    client_ip = request.remote_addr
    is_valid = database.update_heartbeat(token, client_ip)

    if not is_valid:
        print(f"[-] INTRUS REJETÉ (Token invalide) : {client_ip}")
        return jsonify({"error": "Invalid Token. Reset your memory."}), 403

    # Si tout est bon, on renvoie les ordres
    orders = get_orders_config()
    return jsonify({
        "status": "connected", 
        "orders": orders
    })

if __name__ == '__main__':
    print("--- API DE CONTROLE (PORT 5820) ---")
    app.run(host='0.0.0.0', port=5820)