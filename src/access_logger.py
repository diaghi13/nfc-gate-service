"""
Gestione dei log di accesso locali e sincronizzazione
"""

import asyncio
import logging
import json
import aiofiles
from typing import List, Dict, Any
from pathlib import Path
from datetime import datetime

class AccessLogger:
    def __init__(self, config):
        self.config = config
        self.logger = logging.getLogger(__name__)
        self.offline_logs_lock = asyncio.Lock()
        
        # File per i log offline
        self.offline_logs_file = self.config.OFFLINE_LOGS_FILE
        
        # Cache in memoria dei log offline
        self._offline_logs_cache: List[Dict[str, Any]] = []
        self._cache_loaded = False
    
    async def initialize(self):
        """Inizializza il logger degli accessi"""
        try:
            # Crea directory se non esiste
            self.offline_logs_file.parent.mkdir(parents=True, exist_ok=True)
            
            # Carica log offline esistenti
            await self._load_offline_logs()
            
            self.logger.info(f"Access logger inizializzato con {len(self._offline_logs_cache)} log offline")
            
        except Exception as e:
            self.logger.error(f"Errore nell'inizializzazione access logger: {e}")
            raise
    
    async def log_access(self, access_data: Dict[str, Any]):
        """Registra un accesso"""
        try:
            # Aggiungi timestamp se mancante
            if 'timestamp' not in access_data:
                access_data['timestamp'] = datetime.now().isoformat()
            
            # Log locale sempre (per debug e backup)
            self.logger.info(
                f"ACCESSO: Card {access_data['card_id'][:8]}... "
                f"Dir: {access_data['direction']} "
                f"Auth: {access_data['authorized']} "
                f"Offline: {access_data.get('offline_mode', False)}"
            )
            
            # Se online, prova a inviare al backend
            if not access_data.get('offline_mode', False):
                from .backend_client import BackendClient
                # Il controller dovrebbe gestire questo
                pass
            else:
                # Salva offline
                await self._save_offline_log(access_data)
            
            # Invia via WebSocket se connesso (per monitoraggio real-time)
            await self._send_realtime_log(access_data)
            
        except Exception as e:
            self.logger.error(f"Errore nel log accesso: {e}")
            # Salva comunque offline in caso di errore
            await self._save_offline_log(access_data)
    
    async def _save_offline_log(self, access_data: Dict[str, Any]):
        """Salva un log offline"""
        async with self.offline_logs_lock:
            try:
                # Aggiungi alla cache
                self._offline_logs_cache.append(access_data)
                
                # Limita il numero di log offline
                if len(self._offline_logs_cache) > self.config.MAX_OFFLINE_LOGS:
                    # Rimuovi i log più vecchi
                    self._offline_logs_cache = self._offline_logs_cache[-self.config.MAX_OFFLINE_LOGS:]
                    self.logger.warning(f"Rimossi log offline più vecchi, mantenuti ultimi {self.config.MAX_OFFLINE_LOGS}")
                
                # Salva su file
                await self._persist_offline_logs()
                
            except Exception as e:
                self.logger.error(f"Errore nel salvataggio log offline: {e}")
    
    async def _load_offline_logs(self):
        """Carica i log offline dal file"""
        try:
            if self.offline_logs_file.exists():
                async with aiofiles.open(self.offline_logs_file, 'r') as f:
                    content = await f.read()
                    if content.strip():
                        self._offline_logs_cache = json.loads(content)
                    else:
                        self._offline_logs_cache = []
            else:
                self._offline_logs_cache = []
            
            self._cache_loaded = True
            self.logger.info(f"Caricati {len(self._offline_logs_cache)} log offline dal file")
            
        except Exception as e:
            self.logger.error(f"Errore nel caricamento log offline: {e}")
            self._offline_logs_cache = []
            self._cache_loaded = True
    
    async def _persist_offline_logs(self):
        """Persiste i log offline su file"""
        try:
            async with aiofiles.open(self.offline_logs_file, 'w') as f:
                await f.write(json.dumps(self._offline_logs_cache, indent=2, ensure_ascii=False))
            
        except Exception as e:
            self.logger.error(f"Errore nel salvataggio file log offline: {e}")
    
    async def get_offline_logs(self) -> List[Dict[str, Any]]:
        """Restituisce tutti i log offline"""
        async with self.offline_logs_lock:
            if not self._cache_loaded:
                await self._load_offline_logs()
            return self._offline_logs_cache.copy()
    
    async def clear_offline_logs(self):
        """Cancella tutti i log offline"""
        async with self.offline_logs_lock:
            try:
                self._offline_logs_cache = []
                await self._persist_offline_logs()
                self.logger.info("Log offline cancellati")
            except Exception as e:
                self.logger.error(f"Errore nella cancellazione log offline: {e}")
    
    async def get_offline_logs_count(self) -> int:
        """Restituisce il numero di log offline"""
        async with self.offline_logs_lock:
            return len(self._offline_logs_cache)
    
    async def _send_realtime_log(self, access_data: Dict[str, Any]):
        """Invia log in tempo reale via WebSocket"""
        try:
            # Questo dovrebbe essere gestito dal controller principale
            # che ha accesso al WebSocket client
            pass
        except Exception as e:
            self.logger.debug(f"Impossibile inviare log real-time: {e}")
    
    async def export_logs(self, start_date: str = None, end_date: str = None) -> List[Dict[str, Any]]:
        """Esporta log per un periodo specifico"""
        try:
            logs = await self.get_offline_logs()
            
            if start_date or end_date:
                filtered_logs = []
                for log in logs:
                    log_date = log.get('timestamp', '')
                    
                    # Filtro per data di inizio
                    if start_date and log_date < start_date:
                        continue
                    
                    # Filtro per data di fine
                    if end_date and log_date > end_date:
                        continue
                    
                    filtered_logs.append(log)
                
                return filtered_logs
            
            return logs
            
        except Exception as e:
            self.logger.error(f"Errore nell'esportazione log: {e}")
            return []
    
    async def get_stats(self) -> Dict[str, Any]:
        """Restituisce statistiche sui log"""
        try:
            logs = await self.get_offline_logs()
            
            stats = {
                'total_logs': len(logs),
                'authorized_count': 0,
                'denied_count': 0,
                'directions': {'in': 0, 'out': 0},
                'cards_unique': set(),
                'oldest_log': None,
                'newest_log': None
            }
            
            if logs:
                # Ordina per timestamp
                sorted_logs = sorted(logs, key=lambda x: x.get('timestamp', ''))
                stats['oldest_log'] = sorted_logs[0].get('timestamp')
                stats['newest_log'] = sorted_logs[-1].get('timestamp')
                
                for log in logs:
                    # Conteggi autorizzazioni
                    if log.get('authorized'):
                        stats['authorized_count'] += 1
                    else:
                        stats['denied_count'] += 1
                    
                    # Conteggi direzioni
                    direction = log.get('direction', 'in')
                    if direction in stats['directions']:
                        stats['directions'][direction] += 1
                    
                    # Card uniche
                    card_id = log.get('card_id')
                    if card_id and card_id != 'MANUAL_OPEN':
                        stats['cards_unique'].add(card_id)
                
                stats['unique_cards_count'] = len(stats['cards_unique'])
                stats['cards_unique'] = list(stats['cards_unique'])
            
            return stats
            
        except Exception as e:
            self.logger.error(f"Errore nel calcolo statistiche: {e}")
            return {}