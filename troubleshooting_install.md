# 🔧 Risoluzione Problemi Installazione

## ⚠️ Problemi Comuni e Soluzioni

### 1. "cartella /home/turnstile/app non viene creata"

**Causa**: Script di installazione con errori di path o permessi

**Soluzione**:
```bash
# Fix immediato
sudo mkdir -p /home/turnstile/{app,logs,data,updates,backups,app/src,app/scripts}
sudo chown -R turnstile:turnstile /home/turnstile

# Se utente non esiste
sudo useradd -m -s /bin/bash turnstile
sudo usermod -a -G gpio,spi turnstile
```

### 2. "se l'utente è già presente mi ferma lo script"

**Causa**: Script originale usa `set -e` che ferma su qualsiasi errore

**Soluzione**: Usa il nuovo script semplificato
```bash
# Download script corretto
wget https://raw.githubusercontent.com/your-repo/scripts/simple_install.sh
sudo chmod +x simple_install.sh
sudo ./simple_install.sh
```

### 3. "non viene copiato il file .env.template"

**Cause possibili**:
- File non presente nella directory sorgente
- Percorsi errati nello script
- Permessi insufficienti

**Soluzioni**:
```bash
# Soluzione 1: Crea .env manualmente
sudo nano /home/turnstile/app/.env
# Copia il contenuto dal template sotto

# Soluzione 2: Script di fix
sudo /home/turnstile/app/scripts/fix_installation.sh

# Soluzione 3: Creazione automatica
cat > /home/turnstile/app/.env << 'EOF'
DEVICE_ID=turnstile_001
DEVICE_TYPE=turnstile
ENVIRONMENT=production
BACKEND_URL=https://api.example.com
API_KEY=your_api_key_here
WEBSOCKET_URL=wss://api.example.com/ws
NFC_READER_IN_RST=22
NFC_READER_OUT_RST=24
RELAY_CHANNEL_1=18
RELAY_CHANNEL_2=19
SPI_BUS_IN=0
SPI_DEVICE_IN=0
SPI_BUS_OUT=0
SPI_DEVICE_OUT=1
RELAY_OPEN_DURATION=3.0
NFC_READ_TIMEOUT=5.0
CONNECTION_TIMEOUT=10.0
FALLBACK_MODE_ENABLED=true
MAX_OFFLINE_LOGS=1000
LOG_LEVEL=INFO
LOG_FILE=/home/turnstile/logs/turnstile.log
LOG_MAX_SIZE=10485760
LOG_BACKUP_COUNT=5
AUTO_UPDATE_ENABLED=true
UPDATE_CHECK_INTERVAL=3600
UPDATE_ENDPOINT=https://api.example.com/updates
WHITELIST_FILE=/home/turnstile/data/whitelist.json
OFFLINE_LOGS_FILE=/home/turnstile/data/offline_logs.json
EOF

sudo chown turnstile:turnstile /home/turnstile/app/.env
```

### 4. "Failed at step EXEC spawning check_restart.sh: No such file or directory"

**Causa**: Script check_restart.sh mancante o non eseguibile

**Soluzioni immediate**:

#### Opzione A: Crea script mancante
```bash
sudo mkdir -p /home/turnstile/app/scripts

cat > /home/turnstile/app/scripts/check_restart.sh << 'EOF'
#!/bin/bash
RESTART_FILE="/home/turnstile/data/restart_required"
LOG_FILE="/home/turnstile/logs/service.log"

mkdir -p "$(dirname "$LOG_FILE")"

log_message() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" >> "$LOG_FILE"
}

if [ -f "$RESTART_FILE" ]; then
    log_message "Riavvio richiesto dopo aggiornamento"
    rm "$RESTART_FILE"
    sleep 5
    log_message "Proseguimento con avvio servizio"
fi

exit 0
EOF

sudo chmod +x /home/turnstile/app/scripts/check_restart.sh
sudo chown turnstile:turnstile /home/turnstile/app/scripts/check_restart.sh
```

#### Opzione B: Rimuovi ExecStartPre temporaneamente
```bash
sudo systemctl stop turnstile
sudo cp /etc/systemd/system/turnstile.service /etc/systemd/system/turnstile.service.backup

# Rimuovi la riga ExecStartPre
sudo sed -i '/ExecStartPre=/d' /etc/systemd/system/turnstile.service

sudo systemctl daemon-reload
sudo systemctl start turnstile
```

## 🚀 Installazione Rapida da Zero

Se hai problemi multipli, usa questo approccio:

### Metodo 1: Script Semplificato Completo
```bash
# Download e esecuzione
curl -fsSL https://raw.githubusercontent.com/your-repo/scripts/simple_install.sh | sudo bash
```

### Metodo 2: Installazione Manuale Passo-Passo
```bash
# 1. Aggiorna sistema
sudo apt update && sudo apt upgrade -y

# 2. Installa dipendenze
sudo apt install -y python3 python3-pip python3-venv python3-dev git curl

# 3. Crea utente
sudo useradd -m -s /bin/bash turnstile || true
sudo usermod -a -G gpio,spi turnstile

# 4. Crea struttura
sudo mkdir -p /home/turnstile/{app,logs,data,updates,backups,app/scripts,app/src}
sudo chown -R turnstile:turnstile /home/turnstile

# 5. Virtual environment
sudo -u turnstile python3 -m venv /home/turnstile/venv
sudo -u turnstile /home/turnstile/venv/bin/pip install --upgrade pip

# 6. Dipendenze Python
sudo -u turnstile /home/turnstile/venv/bin/pip install RPi.GPIO mfrc522 spidev aiohttp aiofiles websockets python-dotenv

# 7. File base (vedi script sopra per .env e main.py)

# 8. Servizio systemd (vedi script sopra)

# 9. Abilita SPI
echo "dtparam=spi=on" | sudo tee -a /boot/config.txt

# 10. Avvia
sudo systemctl daemon-reload
sudo systemctl enable turnstile
```

## 🔍 Verifica Post-Installazione

### Check List Rapida
```bash
# 1. Utente esiste
id turnstile

# 2. Directory esistono
ls -la /home/turnstile/

# 3. Virtual env funziona
sudo -u turnstile /home/turnstile/venv/bin/python --version

# 4. File configurazione esiste
ls -la /home/turnstile/app/.env

# 5. Script eseguibili
ls -la /home/turnstile/app/scripts/

# 6. Servizio configurato
sudo systemctl status turnstile

# 7. SPI abilitato
ls -la /dev/spidev*
```

### Test Funzionamento
```bash
# Test manuale dell'applicazione
cd /home/turnstile/app
sudo -u turnstile /home/turnstile/venv/bin/python main.py
# Ctrl+C per fermare

# Test servizio
sudo systemctl start turnstile
sudo systemctl status turnstile
sudo journalctl -u turnstile -f
```

## 🔧 Script di Emergenza

### Auto-Fix Completo
```bash
#!/bin/bash
# Script di riparazione automatica

# Crea struttura completa
sudo mkdir -p /home/turnstile/{app,logs,data,updates,backups,app/scripts,app/src}
sudo useradd -m -s /bin/bash turnstile 2>/dev/null || true
sudo usermod -a -G gpio,spi turnstile
sudo chown -R turnstile:turnstile /home/turnstile

# Virtual environment
if [ ! -d "/home/turnstile/venv" ]; then
    sudo -u turnstile python3 -m venv /home/turnstile/venv
    sudo -u turnstile /home/turnstile/venv/bin/pip install --upgrade pip
fi

# File .env base
if [ ! -f "/home/turnstile/app/.env" ]; then
    # Crea .env (vedi template sopra)
fi

# main.py base  
if [ ! -f "/home/turnstile/app/main.py" ]; then
    # Crea main.py base (vedi template sopra)
fi

# Script check_restart.sh
if [ ! -f "/home/turnstile/app/scripts/check_restart.sh" ]; then
    # Crea script (vedi template sopra)
fi

# Servizio systemd
if [ ! -f "/etc/systemd/system/turnstile.service" ]; then
    # Crea servizio (vedi template sopra)
fi

# Permessi finali
sudo chown -R turnstile:turnstile /home/turnstile
sudo chmod +x /home/turnstile/app/main.py
sudo chmod +x /home/turnstile/app/scripts/*.sh

# Ricarica e abilita
sudo systemctl daemon-reload
sudo systemctl enable turnstile

echo "Riparazione completata!"
```

## 📞 Supporto Rapido

### Log Utili
```bash
# Log installazione
sudo journalctl -u turnstile -n 50

# Log sistema
sudo dmesg | tail -20

# Spazio disco
df -h

# Permessi
ls -la /home/turnstile/app/
```

### Comandi di Diagnostica
```bash
# Status generale
sudo systemctl status turnstile

# Test manuale
cd /home/turnstile/app && sudo -u turnstile /home/turnstile/venv/bin/python main.py

# Test hardware
python3 -c "import RPi.GPIO; print('GPIO OK')"
ls /dev/spidev*
```