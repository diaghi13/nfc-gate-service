# Setup Rapido Sistema Tornello

## ⚡ Installazione Express (5 minuti)

### 1. Preparazione SD Card

```bash
# Download Raspberry Pi OS Lite
# Flash con Raspberry Pi Imager
# Abilita SSH e WiFi durante il flash
```

### 2. Installazione Automatica

```bash
ssh pi@<IP_RASPBERRY>

# Download e installazione
git clone <your-repo-url>
cd turnstile-system
sudo ./scripts/install.sh
```

### 3. Configurazione Minima

```bash
sudo nano /home/turnstile/app/.env

# Configura SOLO questi campi obbligatori:
DEVICE_ID=tornello_palestra_001
BACKEND_URL=https://tuo-backend.com
API_KEY=tua-chiave-api
WEBSOCKET_URL=wss://tuo-backend.com/ws
```

### 4. Avvio

```bash
sudo reboot
# Dopo riavvio:
sudo systemctl start turnstile
sudo systemctl enable turnstile
```

## 🔧 Collegamenti Hardware

### GPIO Essenziali

```
Lettore NFC IN:  RST → GPIO 22, SDA → CE0
Lettore NFC OUT: RST → GPIO 24, SDA → CE1 (solo tornello)
Relè:           IN1 → GPIO 18, IN2 → GPIO 19 (solo tornello)
Alimentazione:  3.3V e 5V secondo schema
```

## 🧪 Test Rapido

### Modalità Test (senza hardware)

```bash
/home/turnstile/app/scripts/test_mode.sh test
sudo systemctl restart turnstile
```

### Verifica Funzionamento

```bash
# Status completo
/home/turnstile/app/scripts/test_mode.sh status

# Log in tempo reale
sudo journalctl -u turnstile -f
```

## 📋 Checklist Post-Installazione

- [ ] Sistema si avvia senza errori
- [ ] Configurazione .env completata
- [ ] Test hardware OK (se collegato)
- [ ] Connessione backend funzionante
- [ ] WebSocket connesso
- [ ] Log non mostrano errori critici

## 🆘 Troubleshooting Express

### Servizio non si avvia

```bash
sudo journalctl -u turnstile -n 20
# Controlla errori configurazione in .env
```

### Hardware non funziona

```bash
# Test SPI
ls -la /dev/spidev*
# Se vuoto, abilita SPI in raspi-config e riavvia
```

### Backend non raggiungibile

```bash
# Test connettività
curl -I https://tuo-backend.com
# Verifica API_KEY in .env
```

## 📞 Comandi Utili

```bash
# Riavvia servizio
sudo systemctl restart turnstile

# Log applicazione
tail -f /home/turnstile/logs/turnstile.log

# Modalità debug
nano /home/turnstile/app/.env  # LOG_LEVEL=DEBUG
sudo systemctl restart turnstile

# Switch test/produzione
/home/turnstile/app/scripts/test_mode.sh test
/home/turnstile/app/scripts/test_mode.sh production
```

## 🎯 Configurazioni per Caso d'Uso

### Tornello Palestra

```bash
DEVICE_ID=tornello_palestra_001
DEVICE_TYPE=turnstile
RELAY_OPEN_DURATION=2.0
FALLBACK_MODE_ENABLED=true
```

### Porta Ufficio

```bash
DEVICE_ID=porta_ufficio_001
DEVICE_TYPE=door
RELAY_OPEN_DURATION=5.0
# Rimuovi configurazioni OUT
```

### Solo Test Software

```bash
ENVIRONMENT=test
# Hardware simulato, nessun GPIO necessario
```
