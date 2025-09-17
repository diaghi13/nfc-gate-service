# 🚪 Sistema di Controllo Tornello/Porta NFC - Raspberry Pi 4

## 📖 Indice
- [Panoramica](#panoramica)
- [Requisiti Hardware](#requisiti-hardware) 
- [Schema Collegamenti](#schema-collegamenti)
- [Installazione](#installazione)
- [Configurazione](#configurazione)
- [Endpoint Backend](#endpoint-backend)
- [Utilizzo](#utilizzo)
- [Troubleshooting](#troubleshooting)
- [API Reference](#api-reference)

---

## 🎯 Panoramica

Sistema completo per il controllo di accessi tramite card/braccialetti NFC su Raspberry Pi 4B. Supporta sia tornelli bidirezionali che porte di accesso monodirezionali.

### ✨ Caratteristiche Principali

- **Doppia modalità**: Tornello bidirezionale o porta singola
- **Resilienza offline**: Funziona anche senza connessione internet
- **Aggiornamenti automatici**: Sistema di update via backend
- **Controllo remoto**: WebSocket per apertura manuale via app
- **Logging completo**: Tutti gli accessi registrati e sincronizzati
- **Modalità test**: Sviluppo e debug senza hardware

### 🏗️ Architettura
```
┌─────────────────┐    ┌──────────────┐    ┌─────────────────┐
│   Lettore NFC   │────│ Raspberry Pi │────│  Backend API    │
│   (RC522)       │    │      4B      │    │   + WebSocket   │
└─────────────────┘    └──────────────┘    └─────────────────┘
                              │
                       ┌──────────────┐
                       │   Relè 2CH   │
                       │   (5V)       │  
                       └──────────────┘
```

---

## 🔧 Requisiti Hardware

### 💻 Componenti Base
- **Raspberry Pi 4B** (minimo 2GB RAM, consigliati 4GB)
- **MicroSD Card** (minimo 32GB, Classe 10+)
- **Alimentatore ufficiale** Raspberry Pi 4 (5V 3A)
- **Case con dissipatori** (per funzionamento 24/7)

### 🔌 Componenti Elettronici

#### Per Tornello Bidirezionale
| Componente | Quantità | Note |
|------------|----------|------|
| Lettori NFC RC522 | 2 | Uno per ingresso, uno per uscita |
| Modulo Relè 2 canali | 1 | 5V, con optoisolamento |
| Cavi jumper M-F | 20+ | Per collegamenti |
| Breadboard/PCB | 1 | Per connessioni stabili |

#### Per Porta (Solo Ingresso)
| Componente | Quantità | Note |
|------------|----------|------|
| Lettore NFC RC522 | 1 | Solo ingresso |
| Modulo Relè 1 canale | 1 | 5V, con optoisolamento |
| Cavi jumper M-F | 10+ | Per collegamenti |

### 📋 Lista Acquisti Consigliata
- [Raspberry Pi 4B 4GB](link) - €75
- [RC522 NFC Reader](link) - €8 caduno
- [Modulo Relè 2CH](link) - €12
- [Kit Cavi Jumper](link) - €8
- [MicroSD 32GB](link) - €15
- **Totale stimato**: ~€140 (tornello) / ~€110 (porta)

---

## 🔗 Schema Collegamenti

### 📍 GPIO Raspberry Pi 4B - Pinout
```
     3V3  (1) (2)  5V
   GPIO2  (3) (4)  5V
   GPIO3  (5) (6)  GND
   GPIO4  (7) (8)  GPIO14
     GND  (9) (10) GPIO15
  GPIO17 (11) (12) GPIO18  ← Relè CH1
  GPIO27 (13) (14) GND
  GPIO22 (15) (16) GPIO23  ← NFC IN RST
     3V3 (17) (18) GPIO24  ← NFC OUT RST
  GPIO10 (19) (20) GND
   GPIO9 (21) (22) GPIO25
  GPIO11 (23) (24) GPIO8   ← NFC IN SDA
     GND (25) (26) GPIO7   ← NFC OUT SDA
   GPIO0 (27) (28) GPIO1
   GPIO5 (29) (30) GND
   GPIO6 (31) (32) GPIO12
  GPIO13 (33) (34) GND
  GPIO19 (35) (36) GPIO16  ← Relè CH2
  GPIO26 (37) (38) GPIO20
     GND (39) (40) GPIO21
```

### 🔌 Lettore NFC RC522 - Ingresso
| RC522 Pin | Raspberry Pi Pin | GPIO | Note |
|-----------|------------------|------|------|
| VCC       | Pin 1            | 3.3V | Alimentazione |
| RST       | Pin 15           | GPIO22 | Reset |
| GND       | Pin 6            | GND | Ground |
| MISO      | Pin 21           | GPIO9 | SPI MISO |
| MOSI      | Pin 19           | GPIO10 | SPI MOSI |
| SCK       | Pin 23           | GPIO11 | SPI Clock |
| SDA       | Pin 24           | GPIO8 | SPI CE0 |

### 🔌 Lettore NFC RC522 - Uscita (Solo Tornello)
### 🔌 Lettore NFC RC522 - Uscita (Solo Tornello)
| RC522 Pin | Raspberry Pi Pin | GPIO | Note |
|-----------|------------------|------|------|
| VCC       | Pin 17           | 3.3V | Alimentazione |
| RST       | Pin 18           | GPIO24 | Reset |
| GND       | Pin 20           | GND | Ground |
| MISO      | Pin 21           | GPIO9 | SPI MISO |
| MOSI      | Pin 19           | GPIO10 | SPI MOSI |
| SCK       | Pin 23           | GPIO11 | SPI Clock |
| SDA       | Pin 26           | GPIO7 | SPI CE1 |

### ⚡ Modulo Relè
| Relè Pin | Raspberry Pi Pin | GPIO | Note |
|----------|------------------|------|------|
| VCC      | Pin 2            | 5V | Alimentazione |
| GND      | Pin 14           | GND | Ground |
| IN1      | Pin 12           | GPIO18 | Controllo Canale 1 (Ingresso) |
| IN2      | Pin 35           | GPIO19 | Controllo Canale 2 (Uscita - Solo Tornello) |

### 🔍 Schema Fisico
```
┌─────────────────┐
│  Raspberry Pi   │
│       4B        │
│                 │
│ ┌─────────────┐ │
│ │     SPI     │ │──┐    ┌─────────────┐
│ │   CE0/CE1   │ │  └────│ RC522 (IN)  │
│ └─────────────┘ │       │ RST: GPIO22 │
│                 │       └─────────────┘
│ ┌─────────────┐ │
│ │    GPIO     │ │──┐    ┌─────────────┐
│ │   18/19     │ │  └────│  Relè 2CH   │
│ └─────────────┘ │       │   5V/GND    │
└─────────────────┘       └─────────────┘
        │
        │ (Solo Tornello)
        │
┌─────────────────┐
│   RC522 (OUT)   │
│  RST: GPIO24    │
│   CE1: GPIO7    │
└─────────────────┘
```

---

## 🚀 Installazione

### 📥 Metodo 1: Installazione Automatica (Consigliato)

#### Preparazione SD Card
1. **Scarica** [Raspberry Pi OS Lite](https://rpi.org/downloads)
2. **Flash** con [Raspberry Pi Imager](https://rpi.org/imager)
3. **Configura SSH**: Durante il flash, abilita SSH e WiFi
4. **Inserisci** la SD nel Raspberry Pi e accendi

#### Installazione Sistema
```bash
# 1. Connessione SSH
ssh pi@<IP_RASPBERRY>

# 2. Download progetto
git clone https://github.com/your-username/nfc-gate-service.git
cd nfc-gate-service

# 3. Esecuzione installazione
sudo chmod +x scripts/simple_install.sh
sudo ./scripts/simple_install.sh
```

### 📥 Metodo 2: Installazione Manuale

Se hai problemi con lo script automatico:

```bash
# 1. Aggiorna sistema
sudo apt update && sudo apt upgrade -y

# 2. Installa dipendenze
sudo apt install -y python3 python3-pip python3-venv python3-dev git curl build-essential

# 3. Configura SPI
echo "dtparam=spi=on" | sudo tee -a /boot/config.txt

# 4. Crea utente e struttura
sudo useradd -m -s /bin/bash turnstile || true
sudo usermod -a -G gpio,spi turnstile
sudo mkdir -p /home/turnstile/{app,logs,data,updates,backups,app/scripts}
sudo chown -R turnstile:turnstile /home/turnstile

# 5. Virtual environment
sudo -u turnstile python3 -m venv /home/turnstile/venv
sudo -u turnstile /home/turnstile/venv/bin/pip install --upgrade pip

# 6. Installa dipendenze Python
sudo -u turnstile /home/turnstile/venv/bin/pip install \
    RPi.GPIO==0.7.1 \
    mfrc522==0.0.7 \
    spidev==3.5 \
    aiohttp==3.8.6 \
    aiofiles==23.2.1 \
    websockets==12.0 \
    python-dotenv==1.0.0

# 7. Copia file progetto
sudo cp -r . /home/turnstile/app/
sudo chown -R turnstile:turnstile /home/turnstile/app

# 8. Configura servizio systemd
sudo cp /home/turnstile/app/scripts/turnstile.service /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable turnstile

# 9. Riavvia per applicare SPI
sudo reboot
```

### 🔧 Post-Installazione

Dopo il riavvio:

```bash
# 1. Verifica installazione
/home/turnstile/app/scripts/test_mode.sh status

# 2. Configura .env (vedi sezione configurazione)
sudo nano /home/turnstile/app/.env

# 3. Avvia servizio
sudo systemctl start turnstile

# 4. Verifica funzionamento
sudo systemctl status turnstile
sudo journalctl -u turnstile -f
```

---

## ⚙️ Configurazione

### 📝 File .env Principale

Il file `/home/turnstile/app/.env` contiene tutte le configurazioni:

```bash
# ===============================
# IDENTIFICAZIONE DISPOSITIVO
# ===============================
DEVICE_ID=turnstile_001              # ID univoco dispositivo
DEVICE_TYPE=turnstile                # turnstile o door
ENVIRONMENT=production               # production o test

# ===============================
# CONFIGURAZIONE BACKEND
# ===============================
BACKEND_URL=https://api.example.com         # URL del tuo backend
API_KEY=your_secret_api_key_here            # Chiave API per autenticazione
WEBSOCKET_URL=wss://api.example.com/ws      # WebSocket per controllo remoto

# ===============================
# HARDWARE - LETTORI NFC
# ===============================
NFC_READER_IN_RST=22                # Pin RST lettore ingresso
NFC_READER_OUT_RST=24               # Pin RST lettore uscita (solo tornello)

# ===============================
# HARDWARE - RELÈ
# ===============================
RELAY_CHANNEL_1=18                  # GPIO controllo relè canale 1 (ingresso)
RELAY_CHANNEL_2=19                  # GPIO controllo relè canale 2 (uscita, solo tornello)

# ===============================
# CONFIGURAZIONE SPI
# ===============================
SPI_BUS_IN=0                        # Bus SPI lettore ingresso
SPI_DEVICE_IN=0                     # Device SPI lettore ingresso (CE0)
SPI_BUS_OUT=0                       # Bus SPI lettore uscita (solo tornello)
SPI_DEVICE_OUT=1                    # Device SPI lettore uscita (CE1, solo tornello)

# ===============================
# CONFIGURAZIONE TIMING
# ===============================
RELAY_OPEN_DURATION=3.0             # Durata apertura relè (secondi)
NFC_READ_TIMEOUT=5.0                # Timeout lettura NFC (secondi)
CONNECTION_TIMEOUT=10.0             # Timeout connessioni HTTP (secondi)

# ===============================
# MODALITÀ OFFLINE
# ===============================
FALLBACK_MODE_ENABLED=true          # Abilita modalità offline
MAX_OFFLINE_LOGS=1000               # Massimo numero log offline

# ===============================
# CONFIGURAZIONE LOGGING
# ===============================
LOG_LEVEL=INFO                      # DEBUG, INFO, WARNING, ERROR
LOG_FILE=/home/turnstile/logs/turnstile.log
LOG_MAX_SIZE=10485760               # 10MB
LOG_BACKUP_COUNT=5                  # Numero file di backup

# ===============================
# AGGIORNAMENTI AUTOMATICI
# ===============================
AUTO_UPDATE_ENABLED=true            # Abilita aggiornamenti automatici
UPDATE_CHECK_INTERVAL=3600          # Intervallo controllo (secondi)
UPDATE_ENDPOINT=https://api.example.com/updates

# ===============================
# FILE LOCALI
# ===============================
WHITELIST_FILE=/home/turnstile/data/whitelist.json
OFFLINE_LOGS_FILE=/home/turnstile/data/offline_logs.json
```

### 🎛️ Configurazioni per Caso d'Uso

#### Tornello Palestra/Centro Sportivo
```bash
DEVICE_ID=tornello_palestra_001
DEVICE_TYPE=turnstile
RELAY_OPEN_DURATION=2.0              # Apertura rapida
FALLBACK_MODE_ENABLED=true           # Importante per continuità
MAX_OFFLINE_LOGS=2000                # Molti accessi
LOG_LEVEL=INFO
```

#### Porta Ufficio/Azienda
```bash
DEVICE_ID=porta_ufficio_principale
DEVICE_TYPE=door
RELAY_OPEN_DURATION=5.0              # Apertura più lunga
FALLBACK_MODE_ENABLED=true
AUTO_UPDATE_ENABLED=false           # Controllo manuale aggiornamenti
LOG_LEVEL=WARNING                   # Solo eventi importanti
```

#### Configurazione Test/Sviluppo
```bash
DEVICE_ID=test_device_001
DEVICE_TYPE=turnstile
ENVIRONMENT=test                    # Hardware simulato
LOG_LEVEL=DEBUG                     # Log dettagliati
AUTO_UPDATE_ENABLED=false
```

---

## 🌐 Endpoint Backend

Il sistema richiede un backend che implementi i seguenti endpoint:

### 🔍 Endpoint Essenziali

#### 1. Health Check
```http
GET /health
```
**Scopo**: Verifica stato backend  
**Response**: `200 OK`

#### 2. Verifica Accesso ⭐ **CRITICO**
```http
POST /access/check
Content-Type: application/json
Authorization: Bearer {API_KEY}
X-Device-ID: {DEVICE_ID}
X-Device-Type: turnstile|door

{
  "device_id": "turnstile_001",
  "card_id": "123456789",
  "direction": "in|out",
  "timestamp": "2025-01-15T10:30:00Z"
}
```

**Response**:
```json
{
  "authorized": true,
  "user_name": "Mario Rossi",
  "subscription_valid": true,
  "subscription_expires": "2025-12-31T23:59:59Z",
  "reason": "active_subscription|whitelist|expired|not_found|blocked",
  "access_level": "standard|premium|admin"
}
```

#### 3. Log Accesso
```http
POST /access/log
Content-Type: application/json
Authorization: Bearer {API_KEY}

{
  "device_id": "turnstile_001",
  "card_id": "123456789",
  "direction": "in",
  "timestamp": "2025-01-15T10:30:00Z",
  "authorized": true,
  "offline_mode": false,
  "user_name": "Mario Rossi"
}
```

#### 4. Sincronizzazione Log Offline ⭐ **IMPORTANTE**
```http
POST /access/sync
Content-Type: application/json
Authorization: Bearer {API_KEY}

{
  "device_id": "turnstile_001",
  "sync_timestamp": "2025-01-15T11:00:00Z",
  "logs": [
    {
      "device_id": "turnstile_001",
      "card_id": "123456789",
      "direction": "in",
      "timestamp": "2025-01-15T09:15:00Z",
      "authorized": true,
      "offline_mode": true
    }
  ]
}
```

#### 5. Whitelist Dispositivo
```http
GET /devices/{device_id}/whitelist
Authorization: Bearer {API_KEY}
```

**Response**:
```json
{
  "device_id": "turnstile_001",
  "whitelist": [
    "123456789",
    "987654321"
  ],
  "last_updated": "2025-01-15T08:00:00Z"
}
```

### 🔄 Endpoint Aggiornamenti

#### 6. Controllo Aggiornamenti
```http
POST /updates/check
Content-Type: application/json
Authorization: Bearer {API_KEY}

{
  "device_id": "turnstile_001",
  "current_version": "1.0.0",
  "device_type": "turnstile"
}
```

### 🌐 WebSocket per Controllo Remoto

#### Connessione
```
wss://api.example.com/ws?device_id={DEVICE_ID}&api_key={API_KEY}
```

#### Comandi Backend → Dispositivo
```json
{
  "type": "command",
  "command_id": "cmd_123",
  "command": {
    "action": "open_turnstile",
    "direction": "in|out"
  }
}
```

#### Messaggi Dispositivo → Backend
```json
{
  "type": "device_registration",
  "device_id": "turnstile_001",
  "device_type": "turnstile",
  "capabilities": {
    "manual_open": true,
    "directions": ["in", "out"]
  }
}
```

### 🔐 Autenticazione

**Headers richiesti**:
```http
Authorization: Bearer {API_KEY}
X-Device-ID: {DEVICE_ID}
X-Device-Type: turnstile|door
Content-Type: application/json
```

---

## 🎮 Utilizzo

### 🚀 Comandi Base

#### Gestione Servizio
```bash
# Stato servizio
sudo systemctl status turnstile

# Avvio/Stop
sudo systemctl start turnstile
sudo systemctl stop turnstile
sudo systemctl restart turnstile

# Log in tempo reale
sudo journalctl -u turnstile -f
```

#### Modalità Test/Produzione
```bash
# Attiva modalità test (hardware simulato)
/home/turnstile/app/scripts/test_mode.sh test

# Torna in modalità produzione
/home/turnstile/app/scripts/test_mode.sh production

# Status completo sistema
/home/turnstile/app/scripts/test_mode.sh status
```

### 📊 Monitoraggio

#### Status Sistema
```bash
# Status generale
/home/turnstile/app/scripts/test_mode.sh status

# Log applicazione
tail -f /home/turnstile/logs/turnstile.log

# Spazio disco
df -h /home/turnstile

# Processi
ps aux | grep python
```

#### Diagnostica Hardware
```bash
# Test GPIO
python3 -c "import RPi.GPIO as GPIO; GPIO.setmode(GPIO.BCM); print('GPIO OK'); GPIO.cleanup()"

# Verifica SPI
ls -la /dev/spidev*

# Test connettività
ping -c 3 8.8.8.8
curl -I https://your-backend.com/health
```

### 🔧 Manutenzione

#### Backup Manuale
```bash
# Backup configurazione
sudo cp /home/turnstile/app/.env /home/turnstile/backups/
sudo cp /home/turnstile/data/*.json /home/turnstile/backups/

# Backup log
sudo tar -czf /home/turnstile/backups/logs_$(date +%Y%m%d).tar.gz /home/turnstile/logs/
```

#### Pulizia Sistema
```bash
# Pulizia automatica
sudo /home/turnstile/app/scripts/cleanup_logs.sh

# Pulizia manuale log
sudo journalctl --vacuum-time=7d
```

---

## 🚨 Troubleshooting

### ❗ Problemi Comuni

#### 1. Servizio Non Si Avvia
```bash
# Verifica log errori
sudo journalctl -u turnstile -n 50

# Test manuale
cd /home/turnstile/app
sudo -u turnstile /home/turnstile/venv/bin/python main.py

# Verifica permessi
ls -la /home/turnstile/app/
ls -la /home/turnstile/app/scripts/
```

**Soluzioni**:
- Controlla configurazione `.env`
- Verifica che tutti i file esistano
- Controlla permessi utente `turnstile`

#### 2. Lettori NFC Non Funzionano
```bash
# Verifica SPI abilitato
lsmod | grep spi
ls -la /dev/spidev*

# Se vuoto, riavvia dopo aver verificato
grep "dtparam=spi=on" /boot/config.txt

# Test GPIO
python3 -c "
import RPi.GPIO as GPIO
GPIO.setmode(GPIO.BCM)
GPIO.setup(22, GPIO.OUT)
GPIO.output(22, GPIO.HIGH)
print('GPIO 22 OK')
GPIO.cleanup()
"
```

#### 3. Backend Non Raggiungibile
```bash
# Test connessione
curl -v https://your-backend.com/health

# Verifica DNS
nslookup your-backend.com

# Test API
curl -X POST https://your-backend.com/access/check \
  -H "Authorization: Bearer your_api_key" \
  -H "Content-Type: application/json" \
  -d '{"device_id":"test","card_id":"123","direction":"in","timestamp":"2025-01-15T10:00:00Z"}'
```

#### 4. Relè Non Funziona
```bash
# Test manuale GPIO
echo "18" | sudo tee /sys/class/gpio/export
echo "out" | sudo tee /sys/class/gpio/gpio18/direction
echo "1" | sudo tee /sys/class/gpio/gpio18/value
sleep 2
echo "0" | sudo tee /sys/class/gpio/gpio18/value
echo "18" | sudo tee /sys/class/gpio/unexport
```

#### 5. Problemi di Memoria/Performance
```bash
# Verifica risorse
free -h
df -h
top

# Log grandi
find /home/turnstile/logs -name "*.log" -size +100M -ls

# Pulizia
sudo systemctl stop turnstile
sudo rm /home/turnstile/logs/*.log.*
sudo systemctl start turnstile
```

### 🔧 Script di Riparazione

#### Fix Automatico
```bash
# Script di riparazione completa
sudo /home/turnstile/app/scripts/fix_installation.sh

# Se non esiste, crealo:
curl -fsSL https://raw.githubusercontent.com/your-repo/scripts/fix_installation.sh | sudo bash
```

#### Reset Completo (Mantiene configurazione)
```bash
# Backup configurazione
sudo cp /home/turnstile/app/.env /tmp/

# Riinstallazione
sudo rm -rf /home/turnstile/app/*
sudo /path/to/simple_install.sh

# Ripristino configurazione
sudo cp /tmp/.env /home/turnstile/app/
sudo systemctl restart turnstile
```

---

## 📚 API Reference

### 🏷️ Configurazione Dispositivo

#### Tipi di Dispositivo
- `turnstile`: Tornello bidirezionale (2 lettori NFC, 2 relè)
- `door`: Porta monodirezionale (1 lettore NFC, 1 relè)

#### Modalità Ambiente
- `production`: Hardware reale, connessioni backend
- `test`: Hardware simulato, ideale per sviluppo

#### Direzioni Accesso
- `in`: Ingresso/Entrata
- `out`: Uscita (solo per tornelli)

### 🔌 GPIO Configuration

#### Pin Configurabili
| Configurazione | Default | Range | Note |
|----------------|---------|--------|------|
| NFC_READER_IN_RST | 22 | 2-27 | Evita pin SPI |
| NFC_READER_OUT_RST | 24 | 2-27 | Solo tornello |
| RELAY_CHANNEL_1 | 18 | 2-27 | Ingresso |
| RELAY_CHANNEL_2 | 19 | 2-27 | Uscita (tornello) |

#### Pin SPI (Fissi)
- **MISO**: GPIO9 (Pin 21)
- **MOSI**: GPIO10 (Pin 19) 
- **SCK**: GPIO11 (Pin 23)
- **CE0**: GPIO8 (Pin 24) - Lettore Ingresso
- **CE1**: GPIO7 (Pin 26) - Lettore Uscita

### 📊 Codici di Stato

#### HTTP Status Codes
- `200`: Successo
- `201`: Creato con successo
- `400`: Richiesta non valida
- `401`: Autenticazione fallita
- `403`: Accesso negato
- `404`: Risorsa non trovata
- `500`: Errore server

#### Access Reasons
- `active_subscription`: Abbonamento attivo
- `whitelist`: Presente in whitelist
- `expired`: Abbonamento scaduto
- `not_found`: Card non trovata
- `blocked`: Utente bloccato

---

## 📞 Supporto

### 🐛 Segnalazione Bug
Per segnalare problemi, includi sempre:

1. **Versione sistema**: `cat /home/turnstile/app/VERSION`
2. **Configurazione hardware**: Tornello/Porta
3. **Log errori**: `sudo journalctl -u turnstile -n 100`
4. **File configurazione**: `/home/turnstile/app/.env` (rimuovi API_KEY)
5. **Status sistema**: `/home/turnstile/app/scripts/test_mode.sh status`

### 📋 Checklist Pre-Supporto

Prima di richiedere supporto, verifica:

- [ ] Sistema aggiornato: `sudo apt update && sudo apt upgrade`
- [ ] SPI abilitato: `ls /dev/spidev*`
- [ ] Servizio attivo: `sudo systemctl status turnstile`
- [ ] Connettività: `ping 8.8.8.8`
- [ ] Backend raggiungibile: `curl https://your-backend.com/health`
- [ ] File configurazione valido: `cat /home/turnstile/app/.env`
- [ ] Permessi corretti: `ls -la /home/turnstile/`

### 🔗 Risorse Utili

- [Raspberry Pi GPIO Pinout](https://pinout.xyz/)
- [RC522 NFC Documentation](https://www.nxp.com/docs/en/data-sheet/MFRC522.pdf)
- [SPI Configuration Guide](https://www.raspberrypi.org/documentation/hardware/raspberrypi/spi/)

---

## 📝 Changelog

### v1.0.0 (2025-01-15)
- ✅ Release iniziale
- ✅ Supporto tornello bidirezionale e porta
- ✅ Modalità offline con sincronizzazione
- ✅ WebSocket per controllo remoto
- ✅ Aggiornamenti automatici
- ✅ Sistema di logging completo
- ✅ Modalità test per sviluppo

---

## 📄 Licenza

Questo progetto è distribuito sotto licenza MIT. Vedi file `LICENSE` per dettagli.

---

## 🤝 Contributi

I contributi sono benvenuti! Per favore:

1. Fork del progetto
2. Crea branch per feature (`git checkout -b feature/AmazingFeature`)
3. Commit modifiche (`git commit -m 'Add some AmazingFeature'`)
4. Push del branch (`git push origin feature/AmazingFeature`)
5. Apri Pull Request

---

**🎯 Sistema testato su Raspberry Pi 4B con Raspberry Pi OS Lite**