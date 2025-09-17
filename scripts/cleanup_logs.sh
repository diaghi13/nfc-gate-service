#!/bin/bash

# Script di pulizia automatica log e file temporanei

LOG_DIR="/home/turnstile/logs"
DATA_DIR="/home/turnstile/data"
UPDATE_DIR="/home/turnstile/updates"
MAX_LOG_DAYS=30
MAX_OFFLINE_LOGS=5000

# Funzione di logging
log_message() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - CLEANUP - $1" >> "$LOG_DIR/cleanup.log"
}

log_message "Inizio pulizia automatica"

# Pulizia log vecchi
find "$LOG_DIR" -name "*.log.*" -mtime +$MAX_LOG_DAYS -delete 2>/dev/null
log_message "Log più vecchi di $MAX_LOG_DAYS giorni rimossi"

# Pulizia file temporanei aggiornamenti
find "$UPDATE_DIR" -name "*.tmp" -mtime +1 -delete 2>/dev/null
find "$UPDATE_DIR" -name "extracted_*" -type d -mtime +7 -exec rm -rf {} + 2>/dev/null
log_message "File temporanei aggiornamenti puliti"

# Controllo dimensioni log offline
if [ -f "$DATA_DIR/offline_logs.json" ]; then
    LOG_COUNT=$(python3 -c "
import json
try:
    with open('$DATA_DIR/offline_logs.json', 'r') as f:
        data = json.load(f)
        print(len(data) if isinstance(data, list) else 0)
except:
    print(0)
" 2>/dev/null)
    
    if [ "$LOG_COUNT" -gt "$MAX_OFFLINE_LOGS" ]; then
        log_message "WARNING: Troppi log offline ($LOG_COUNT), potrebbero essere necessarie azioni manuali"
    fi
fi

# Pulizia core dump e crash log
find /home/turnstile -name "core.*" -mtime +7 -delete 2>/dev/null
find /tmp -name "turnstile_*" -mtime +1 -delete 2>/dev/null

log_message "Pulizia completata"

# Mantieni solo gli ultimi 10 log di pulizia
tail -n 100 "$LOG_DIR/cleanup.log" > "$LOG_DIR/cleanup.log.tmp" 2>/dev/null
mv "$LOG_DIR/cleanup.log.tmp" "$LOG_DIR/cleanup.log" 2>/dev/null

exit 0