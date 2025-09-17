"""
Client WebSocket per controllo remoto
"""

import asyncio
import logging
import json
import ssl
from typing import Callable, Dict, Any
import websockets
from websockets.exceptions import ConnectionClosedError, ConnectionClosedOK

class WebSocketClient:
    def __init__(self, config, command_handler: Callable):
        self.config = config
        self.command_handler = command_handler
        self.logger = logging.getLogger(__name__)
        
        self.websocket = None
        self.running = False
        self.reconnect_interval = 5  # secondi
        self.max_reconnect_attempts = 5
        self.current_reconnect_attempts = 0
    
    async def start(self):
        """Avvia il client WebSocket con reconnessione automatica"""
        self.running = True
        
        while self.running:
            try:
                await self._connect_and_listen()
            except Exception as e:
                self.logger.error(f"Errore WebSocket: {e}")
                
                if self.running:
                    self.current_reconnect_attempts += 1
                    if self.current_reconnect_attempts <= self.max_reconnect_attempts:
                        self.logger.info(f"Tentativo di riconnessione {self.current_reconnect_attempts}/{self.max_reconnect_attempts} in {self.reconnect_interval}s")
                        await asyncio.sleep(self.reconnect_interval)
                    else:
                        self.logger.error("Massimo numero di tentativi di riconnessione raggiunto")
                        break
    
    async def _connect_and_listen(self):
        """Connette e ascolta messaggi WebSocket"""
        try:
            # Prepara URL con parametri di autenticazione
            url = f"{self.config.WEBSOCKET_URL}?device_id={self.config.DEVICE_ID}&api_key={self.config.API_KEY}"
            
            # Configurazione SSL se necessario
            ssl_context = None
            if self.config.WEBSOCKET_URL.startswith('wss://'):
                ssl_context = ssl.create_default_context()
            
            self.logger.info("Connessione al WebSocket...")
            
            async with websockets.connect(
                url, 
                ssl=ssl_context,
                ping_interval=30,
                ping_timeout=10
            ) as websocket:
                self.websocket = websocket
                self.current_reconnect_attempts = 0  # Reset counter on successful connection
                self.logger.info("WebSocket connesso")
                
                # Invia messaggio di registrazione
                await self._send_registration()
                
                # Loop di ascolto messaggi
                async for message in websocket:
                    try:
                        await self._handle_message(message)
                    except Exception as e:
                        self.logger.error(f"Errore nella gestione messaggio WebSocket: {e}")
                        
        except ConnectionClosedError as e:
            self.logger.warning(f"Connessione WebSocket chiusa: {e}")
        except ConnectionClosedOK:
            self.logger.info("Connessione WebSocket chiusa normalmente")
        except Exception as e:
            self.logger.error(f"Errore connessione WebSocket: {e}")
            raise
    
    async def _send_registration(self):
        """Invia messaggio di registrazione dispositivo"""
        registration_msg = {
            'type': 'device_registration',
            'device_id': self.config.DEVICE_ID,
            'device_type': self.config.DEVICE_TYPE,
            'capabilities': self._get_device_capabilities()
        }
        
        await self._send_message(registration_msg)
        self.logger.info("Registrazione dispositivo inviata")
    
    def _get_device_capabilities(self) -> Dict[str, Any]:
        """Restituisce le capacità del dispositivo"""
        capabilities = {
            'manual_open': True,
            'directions': ['in']
        }
        
        if self.config.is_turnstile():
            capabilities['directions'].append('out')
        
        return capabilities
    
    async def _handle_message(self, message: str):
        """Gestisce un messaggio ricevuto"""
        try:
            data = json.loads(message)
            message_type = data.get('type')
            
            self.logger.debug(f"Messaggio WebSocket ricevuto: {message_type}")
            
            if message_type == 'command':
                # Gestisci comando
                await self._handle_command(data)
            elif message_type == 'ping':
                # Rispondi al ping
                await self._send_pong(data)
            elif message_type == 'config_update':
                # Gestisci aggiornamento configurazione
                await self._handle_config_update(data)
            else:
                self.logger.warning(f"Tipo messaggio sconosciuto: {message_type}")
        
        except json.JSONDecodeError as e:
            self.logger.error(f"Errore parsing JSON: {e}")
        except Exception as e:
            self.logger.error(f"Errore gestione messaggio: {e}")
    
    async def _handle_command(self, data: Dict[str, Any]):
        """Gestisce un comando ricevuto"""
        try:
            command = data.get('command', {})
            command_id = data.get('command_id')
            
            self.logger.info(f"Comando ricevuto: {command.get('action')} (ID: {command_id})")
            
            # Esegui comando tramite handler
            result = await self.command_handler(command)
            
            # Invia conferma
            response = {
                'type': 'command_response',
                'command_id': command_id,
                'status': 'success' if result is not False else 'error',
                'device_id': self.config.DEVICE_ID
            }
            
            await self._send_message(response)
            
        except Exception as e:
            self.logger.error(f"Errore nell'esecuzione comando: {e}")
            
            # Invia errore
            if 'command_id' in data:
                error_response = {
                    'type': 'command_response',
                    'command_id': data['command_id'],
                    'status': 'error',
                    'error': str(e),
                    'device_id': self.config.DEVICE_ID
                }
                await self._send_message(error_response)
    
    async def _send_pong(self, ping_data: Dict[str, Any]):
        """Invia risposta a ping"""
        pong_msg = {
            'type': 'pong',
            'ping_id': ping_data.get('ping_id'),
            'device_id': self.config.DEVICE_ID
        }
        await self._send_message(pong_msg)
    
    async def _handle_config_update(self, data: Dict[str, Any]):
        """Gestisce aggiornamento configurazione"""
        try:
            new_config = data.get('config', {})
            self.logger.info(f"Aggiornamento configurazione ricevuto: {list(new_config.keys())}")
            
            # TODO: Implementa aggiornamento configurazione runtime se necessario
            # Per ora invia solo conferma
            
            response = {
                'type': 'config_update_response',
                'status': 'acknowledged',
                'device_id': self.config.DEVICE_ID
            }
            await self._send_message(response)
            
        except Exception as e:
            self.logger.error(f"Errore aggiornamento configurazione: {e}")
    
    async def _send_message(self, message: Dict[str, Any]):
        """Invia un messaggio WebSocket"""
        try:
            if self.websocket and not self.websocket.closed:
                message_json = json.dumps(message)
                await self.websocket.send(message_json)
                self.logger.debug(f"Messaggio inviato: {message.get('type')}")
        except Exception as e:
            self.logger.error(f"Errore invio messaggio WebSocket: {e}")
    
    async def send_status_update(self, status: Dict[str, Any]):
        """Invia aggiornamento stato dispositivo"""
        status_msg = {
            'type': 'status_update',
            'device_id': self.config.DEVICE_ID,
            'status': status,
            'timestamp': status.get('timestamp')
        }
        await self._send_message(status_msg)
    
    async def send_access_log(self, access_data: Dict[str, Any]):
        """Invia log di accesso in tempo reale"""
        log_msg = {
            'type': 'access_log',
            'device_id': self.config.DEVICE_ID,
            'access_data': access_data
        }
        await self._send_message(log_msg)
    
    async def stop(self):
        """Ferma il client WebSocket"""
        self.running = False
        
        if self.websocket and not self.websocket.closed:
            try:
                await self.websocket.close()
                self.logger.info("WebSocket disconnesso")
            except Exception as e:
                self.logger.error(f"Errore nella disconnessione WebSocket: {e}")
    
    def is_connected(self) -> bool:
        """Verifica se WebSocket è connesso"""
        return self.websocket is not None and not self.websocket.closed