"""
Controller principale del sistema tornello
"""

import asyncio
import logging
from datetime import datetime
from typing import Optional

from .nfc_reader import NFCReaderManager
from .relay_controller import RelayController
from .backend_client import BackendClient
from .websocket_client import WebSocketClient
from .access_logger import AccessLogger
from .updater import AutoUpdater

class TurnstileController:
    def __init__(self, config):
        self.config = config
        self.logger = logging.getLogger(__name__)
        
        # Componenti del sistema
        self.nfc_manager = NFCReaderManager(config)
        self.relay_controller = RelayController(config)
        self.backend_client = BackendClient(config)
        self.websocket_client = WebSocketClient(config, self._handle_websocket_command)
        self.access_logger = AccessLogger(config)
        self.updater = AutoUpdater(config, self.backend_client)
        
        # Stato del sistema
        self.running = False
        self.connection_online = False
        
    async def initialize(self):
        """Inizializza tutti i componenti"""
        self.logger.info("Inizializzazione sistema tornello...")
        
        # Inizializza componenti
        await self.nfc_manager.initialize()
        await self.relay_controller.initialize()
        await self.backend_client.initialize()
        await self.access_logger.initialize()
        await self.updater.initialize()
        
        # Test connessione backend
        self.connection_online = await self.backend_client.test_connection()
        
        if self.connection_online:
            self.logger.info("Connessione backend attiva")
            # Sincronizza dati al startup
            await self._sync_offline_data()
            await self._update_whitelist()
        else:
            self.logger.warning("Backend non raggiungibile, modalità offline")
        
        self.logger.info("Inizializzazione completata")
    
    async def start(self):
        """Avvia il sistema"""
        self.running = True
        self.logger.info("Avvio sistema tornello...")
        
        # Avvia tutti i task asincroni
        tasks = [
            asyncio.create_task(self._nfc_monitoring_loop()),
            asyncio.create_task(self._connection_monitor_loop()),
            asyncio.create_task(self._updater_loop()),
            asyncio.create_task(self.websocket_client.start())
        ]
        
        try:
            await asyncio.gather(*tasks)
        except Exception as e:
            self.logger.error(f"Errore nel loop principale: {e}")
        finally:
            self.running = False
    
    async def stop(self):
        """Arresta il sistema"""
        self.logger.info("Arresto sistema...")
        self.running = False
        
        # Chiudi connessioni
        await self.websocket_client.stop()
        await self.nfc_manager.cleanup()
        await self.relay_controller.cleanup()
        
        # Sincronizza dati offline prima di chiudere
        if self.connection_online:
            await self._sync_offline_data()
        
        self.logger.info("Sistema arrestato")
    
    async def _nfc_monitoring_loop(self):
        """Loop principale di monitoraggio NFC"""
        while self.running:
            try:
                # Leggi card dal lettore di ingresso
                card_id = await self.nfc_manager.read_card('in')
                if card_id:
                    await self._handle_card_read(card_id, 'in')
                
                # Se è un tornello, leggi anche il lettore di uscita
                if self.config.is_turnstile():
                    card_id = await self.nfc_manager.read_card('out')
                    if card_id:
                        await self._handle_card_read(card_id, 'out')
                
                await asyncio.sleep(0.1)  # Evita sovraccarico CPU
                
            except Exception as e:
                self.logger.error(f"Errore nel loop NFC: {e}")
                await asyncio.sleep(1)
    
    async def _handle_card_read(self, card_id: str, direction: str):
        """Gestisce la lettura di una card"""
        self.logger.info(f"Card letta: {card_id[:8]}... direzione: {direction}")
        
        # Verifica autorizzazione
        authorized = await self._check_authorization(card_id, direction)
        
        # Log dell'accesso
        access_log = {
            'device_id': self.config.DEVICE_ID,
            'card_id': card_id,
            'direction': direction,
            'timestamp': datetime.now().isoformat(),
            'authorized': authorized,
            'offline_mode': not self.connection_online
        }
        
        await self.access_logger.log_access(access_log)
        
        # Apri tornello se autorizzato
        if authorized:
            await self._open_turnstile(direction)
            self.logger.info(f"Accesso consentito per card {card_id[:8]}... ({direction})")
        else:
            self.logger.warning(f"Accesso negato per card {card_id[:8]}... ({direction})")
    
    async def _check_authorization(self, card_id: str, direction: str) -> bool:
        """Verifica se la card è autorizzata"""
        try:
            if self.connection_online:
                # Verifica online
                response = await self.backend_client.check_access(card_id, direction)
                return response.get('authorized', False)
            else:
                # Modalità fallback offline
                if self.config.FALLBACK_MODE_ENABLED:
                    whitelist = self.config.get_whitelist()
                    return card_id in whitelist
                return False
        except Exception as e:
            self.logger.error(f"Errore nella verifica autorizzazione: {e}")
            # Fallback su whitelist locale
            if self.config.FALLBACK_MODE_ENABLED:
                whitelist = self.config.get_whitelist()
                return card_id in whitelist
            return False
    
    async def _open_turnstile(self, direction: str):
        """Apre il tornello nella direzione specificata"""
        try:
            if direction == 'in':
                await self.relay_controller.activate_relay(1)
            elif direction == 'out' and self.config.is_turnstile():
                await self.relay_controller.activate_relay(2)
            
        except Exception as e:
            self.logger.error(f"Errore nell'apertura tornello: {e}")
    
    async def _connection_monitor_loop(self):
        """Monitora lo stato della connessione"""
        while self.running:
            try:
                was_online = self.connection_online
                self.connection_online = await self.backend_client.test_connection()
                
                if not was_online and self.connection_online:
                    self.logger.info("Connessione ripristinata")
                    # Sincronizza dati offline
                    await self._sync_offline_data()
                    await self._update_whitelist()
                elif was_online and not self.connection_online:
                    self.logger.warning("Connessione persa")
                
                await asyncio.sleep(30)  # Controlla ogni 30 secondi
                
            except Exception as e:
                self.logger.error(f"Errore nel monitoraggio connessione: {e}")
                await asyncio.sleep(30)
    
    async def _sync_offline_data(self):
        """Sincronizza i dati offline con il backend"""
        try:
            offline_logs = await self.access_logger.get_offline_logs()
            if offline_logs:
                self.logger.info(f"Sincronizzazione {len(offline_logs)} log offline...")
                success = await self.backend_client.sync_offline_logs(offline_logs)
                if success:
                    await self.access_logger.clear_offline_logs()
                    self.logger.info("Sincronizzazione completata")
                
        except Exception as e:
            self.logger.error(f"Errore nella sincronizzazione: {e}")
    
    async def _update_whitelist(self):
        """Aggiorna la whitelist locale"""
        try:
            whitelist = await self.backend_client.get_whitelist()
            if whitelist:
                self.config.update_whitelist(whitelist)
                self.logger.info("Whitelist aggiornata")
        except Exception as e:
            self.logger.error(f"Errore nell'aggiornamento whitelist: {e}")
    
    async def _updater_loop(self):
        """Loop per gli aggiornamenti automatici"""
        while self.running:
            try:
                if self.config.AUTO_UPDATE_ENABLED and self.connection_online:
                    await self.updater.check_and_update()
                
                await asyncio.sleep(self.config.UPDATE_CHECK_INTERVAL)
                
            except Exception as e:
                self.logger.error(f"Errore nel check aggiornamenti: {e}")
                await asyncio.sleep(self.config.UPDATE_CHECK_INTERVAL)
    
    async def _handle_websocket_command(self, command: dict):
        """Gestisce i comandi WebSocket"""
        try:
            if command.get('action') == 'open_turnstile':
                direction = command.get('direction', 'in')
                self.logger.info(f"Apertura manuale tornello via WebSocket: {direction}")
                
                # Log dell'apertura manuale
                access_log = {
                    'device_id': self.config.DEVICE_ID,
                    'card_id': 'MANUAL_OPEN',
                    'direction': direction,
                    'timestamp': datetime.now().isoformat(),
                    'authorized': True,
                    'offline_mode': not self.connection_online
                }
                await self.access_logger.log_access(access_log)
                
                # Apri tornello
                await self._open_turnstile(direction)
                
        except Exception as e:
            self.logger.error(f"Errore nella gestione comando WebSocket: {e}")