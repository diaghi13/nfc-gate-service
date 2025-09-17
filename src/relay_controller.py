"""
Controller per relè a 2 canali
"""

import asyncio
import logging
import RPi.GPIO as GPIO
from typing import Dict

class RelayController:
    def __init__(self, config):
        self.config = config
        self.logger = logging.getLogger(__name__)
        
        # Mappa dei canali relè
        self.relay_pins = {
            1: self.config.RELAY_CHANNEL_1,
            2: self.config.RELAY_CHANNEL_2 if self.config.is_turnstile() else None
        }
        
        # Rimuovi canali None per dispositivi porta
        self.relay_pins = {k: v for k, v in self.relay_pins.items() if v is not None}
        
        self.relay_states: Dict[int, bool] = {}
        self._relay_tasks: Dict[int, asyncio.Task] = {}
    
    async def initialize(self):
        """Inizializza i relè"""
        try:
            if not self.config.is_test_mode():
                GPIO.setmode(GPIO.BCM)
                
                for channel, pin in self.relay_pins.items():
                    GPIO.setup(pin, GPIO.OUT)
                    GPIO.output(pin, GPIO.LOW)  # Relè spento (stato di riposo)
                    self.relay_states[channel] = False
                    
                    self.logger.info(f"Relè canale {channel} inizializzato (pin {pin})")
            else:
                # In modalità test, simula l'inizializzazione
                for channel in self.relay_pins.keys():
                    self.relay_states[channel] = False
                    self.logger.info(f"Relè canale {channel} simulato (modalità test)")
            
            self.logger.info(f"Controller relè inizializzato con {len(self.relay_pins)} canali")
            
        except Exception as e:
            self.logger.error(f"Errore nell'inizializzazione relè: {e}")
            raise
    
    async def activate_relay(self, channel: int, duration: float = None):
        """Attiva un relè per la durata specificata"""
        if channel not in self.relay_pins:
            self.logger.error(f"Canale relè {channel} non valido")
            return False
        
        if duration is None:
            duration = self.config.RELAY_OPEN_DURATION
        
        try:
            # Cancella eventuali task precedenti per questo canale
            if channel in self._relay_tasks and not self._relay_tasks[channel].done():
                self._relay_tasks[channel].cancel()
            
            # Crea nuovo task per il controllo temporizzato
            self._relay_tasks[channel] = asyncio.create_task(
                self._timed_relay_activation(channel, duration)
            )
            
            await self._relay_tasks[channel]
            return True
            
        except Exception as e:
            self.logger.error(f"Errore nell'attivazione relè {channel}: {e}")
            return False
    
    async def _timed_relay_activation(self, channel: int, duration: float):
        """Attiva il relè per il tempo specificato"""
        try:
            self.logger.info(f"Attivazione relè canale {channel} per {duration}s")
            
            # Attiva relè
            await self._set_relay_state(channel, True)
            
            # Aspetta la durata specificata
            await asyncio.sleep(duration)
            
            # Disattiva relè
            await self._set_relay_state(channel, False)
            
            self.logger.info(f"Relè canale {channel} disattivato")
            
        except asyncio.CancelledError:
            # Task cancellato, assicurati che il relè sia spento
            await self._set_relay_state(channel, False)
            self.logger.info(f"Attivazione relè {channel} cancellata")
            raise
        except Exception as e:
            await self._set_relay_state(channel, False)
            self.logger.error(f"Errore nell'attivazione temporizzata relè {channel}: {e}")
            raise
    
    async def _set_relay_state(self, channel: int, state: bool):
        """Imposta lo stato di un relè"""
        try:
            if not self.config.is_test_mode():
                pin = self.relay_pins[channel]
                GPIO.output(pin, GPIO.HIGH if state else GPIO.LOW)
            else:
                # In modalità test, solo log
                self.logger.info(f"[TEST] Relè {channel} -> {'ON' if state else 'OFF'}")
            
            self.relay_states[channel] = state
            
        except Exception as e:
            self.logger.error(f"Errore nell'impostazione stato relè {channel}: {e}")
            raise
    
    async def get_relay_state(self, channel: int) -> bool:
        """Restituisce lo stato corrente di un relè"""
        return self.relay_states.get(channel, False)
    
    async def emergency_stop_all(self):
        """Ferma immediatamente tutti i relè (emergenza)"""
        self.logger.warning("STOP DI EMERGENZA - Disattivazione tutti i relè")
        
        # Cancella tutti i task attivi
        for task in self._relay_tasks.values():
            if not task.done():
                task.cancel()
        
        # Spegni tutti i relè
        for channel in self.relay_pins.keys():
            await self._set_relay_state(channel, False)
    
    async def cleanup(self):
        """Pulisce le risorse del controller"""
        try:
            # Ferma tutti i relè
            await self.emergency_stop_all()
            
            # Aspetta che tutti i task finiscano
            if self._relay_tasks:
                await asyncio.gather(*self._relay_tasks.values(), return_exceptions=True)
            
            if not self.config.is_test_mode():
                # Pulisce i pin GPIO
                for pin in self.relay_pins.values():
                    GPIO.cleanup(pin)
            
            self.logger.info("Controller relè pulito")
            
        except Exception as e:
            self.logger.error(f"Errore nella pulizia controller relè: {e}")
    
    def get_available_channels(self):
        """Restituisce i canali relè disponibili"""
        return list(self.relay_pins.keys())
    
    def get_relay_info(self):
        """Restituisce informazioni sui relè configurati"""
        return {
            'channels': list(self.relay_pins.keys()),
            'pins': dict(self.relay_pins),
            'states': dict(self.relay_states),
            'open_duration': self.config.RELAY_OPEN_DURATION
        }