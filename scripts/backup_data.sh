#!/bin/bash

# Script di backup automatico dei dati

BACKUP_DIR="/home/turnstile/backups"
DATA_DIR="/home/turnstile/data"
LOG_DIR="/home/turnstile/logs"
APP_DIR="/home/turnstile/app"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
BACKUP_NAME="data_backup_$TIMESTAMP"

# Funzione di logging
log_message() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - BACKUP - $1" >> "$LOG_DIR/backup.log"
}

log_message "Inizio backup dati"

# Crea directory backup se non esiste
mkdir -p "$BACKUP_DIR/data"

# Backup dati critici
if [ -f "$DATA_DIR/offline_logs.json" ]; then
    cp "$DATA_DIR/offline_logs.json" "$BACKUP_DIR/data/${BACKUP_NAME}_offline_logs.json"
    log_message "Backup offline logs completato"
fi

if [ -f "$DATA_DIR/whitelist.json" ]; then
    cp "$DATA_DIR/whitelist.json" "$BACKUP_DIR/data/${BACKUP_NAME}_whitelist.json"
    log_message "Backup whitelist completato"
fi

if [ -f "$APP_DIR/.env" ]; then
    cp "$APP_DIR/.env" "$BACKUP_DIR/data/${BACKUP_NAME}_env.txt"
    log_message "Backup configurazione completato"
fi

# Backup log recenti (ultimi 7 giorni)
find "$LOG_DIR" -name "*.log" -mtime -7 -exec tar -czf "$BACKUP_DIR/data/${BACKUP_NAME}_recent_logs.tar.gz" {} +
log_message "Backup log recenti completato"

# Rimuovi backup più vecchi di 30 giorni
find "$BACKUP_DIR/data" -name "data_backup_*" -mtime +30 -delete
log_message "Pulizia backup vecchi completata"

# Conta backup rimanenti
BACKUP_COUNT=$(find "$BACKUP_DIR/data" -name "data_backup_*" | wc -l)
log_message "Backup completato. Totale backup: $BACKUP_COUNT"

# Mantieni solo gli ultimi 50 log di backup
tail -n 50 "$LOG_DIR/backup.log" > "$LOG_DIR/backup.log.tmp" 2>/dev/null
mv "$LOG_DIR/backup.log.tmp" "$LOG_DIR/backup.log" 2>/dev/null

exit 0