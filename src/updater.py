"""
Sistema di aggiornamenti automatici
"""

import asyncio
import logging
import hashlib
import tarfile
import zipfile
import subprocess
import shutil
import os
from pathlib import Path
from typing import Dict, Any, Optional
import aiofiles

class AutoUpdater:
    def __init__(self, config, backend_client):
        self.config = config
        self.backend_client = backend_client
        self.logger = logging.getLogger(__name__)
        
        # Directory per aggiornamenti
        self.update_dir = Path('/home/turnstile/updates')
        self.backup_dir = Path('/home/turnstile/backups')
        self.app_dir = Path('/home/turnstile/app')
        
        # File versione
        self.version_file = self.app_dir / 'VERSION'
        
        self.updating = False
    
    async def initialize(self):
        """Inizializza il sistema di aggiornamenti"""
        try:
            # Crea directory necessarie
            self.update_dir.mkdir(parents=True, exist_ok=True)
            self.backup_dir.mkdir(parents=True, exist_ok=True)
            
            self.logger.info(f"Auto-updater inizializzato. Versione corrente: {self.get_current_version()}")
            
        except Exception as e:
            self.logger.error(f"Errore nell'inizializzazione auto-updater: {e}")
            raise
    
    def get_current_version(self) -> str:
        """Restituisce la versione corrente"""
        try:
            if self.version_file.exists():
                return self.version_file.read_text().strip()
        except Exception as e:
            self.logger.error(f"Errore lettura versione: {e}")
        return '1.0.0'
    
    async def check_and_update(self):
        """Controlla e applica aggiornamenti se disponibili"""
        if self.updating:
            self.logger.info("Aggiornamento già in corso, skip")
            return
        
        try:
            if not self.config.AUTO_UPDATE_ENABLED:
                return
            
            self.logger.info("Controllo aggiornamenti disponibili...")
            
            # Controlla aggiornamenti
            update_info = await self.backend_client.check_updates()
            
            if not update_info:
                self.logger.debug("Nessuna informazione aggiornamenti dal backend")
                return
            
            if not update_info.get('update_available', False):
                self.logger.debug("Nessun aggiornamento disponibile")
                return
            
            # Aggiornamento disponibile
            new_version = update_info.get('version')
            current_version = self.get_current_version()
            
            self.logger.info(f"Aggiornamento disponibile: {current_version} -> {new_version}")
            
            # Avvia processo di aggiornamento
            await self._perform_update(update_info)
            
        except Exception as e:
            self.logger.error(f"Errore nel controllo aggiornamenti: {e}")
    
    async def _perform_update(self, update_info: Dict[str, Any]):
        """Esegue l'aggiornamento"""
        update_id = update_info.get('id')
        
        try:
            self.updating = True
            
            # Notifica inizio aggiornamento
            await self.backend_client.report_update_status(
                update_id, 'started'
            )
            
            self.logger.info("Inizio processo di aggiornamento...")
            
            # 1. Download aggiornamento
            update_data = await self.backend_client.download_update(update_info)
            if not update_data:
                raise Exception("Download aggiornamento fallito")
            
            # 2. Verifica integrità
            if not await self._verify_update(update_data, update_info):
                raise Exception("Verifica integrità aggiornamento fallita")
            
            # 3. Crea backup
            backup_path = await self._create_backup()
            if not backup_path:
                raise Exception("Creazione backup fallita")
            
            # 4. Estrai aggiornamento
            extracted_path = await self._extract_update(update_data, update_info)
            if not extracted_path:
                raise Exception("Estrazione aggiornamento fallita")
            
            # 5. Applica aggiornamento
            await self._apply_update(extracted_path, update_info)
            
            # 6. Aggiorna versione
            await self._update_version(update_info.get('version'))
            
            # 7. Notifica successo
            await self.backend_client.report_update_status(
                update_id, 'completed'
            )
            
            self.logger.info(f"Aggiornamento completato con successo: {update_info.get('version')}")
            
            # 8. Riavvia servizio se richiesto
            if update_info.get('requires_restart', True):
                await self._schedule_restart()
            
        except Exception as e:
            self.logger.error(f"Errore durante aggiornamento: {e}")
            
            # Notifica errore
            await self.backend_client.report_update_status(
                update_id, 'failed', str(e)
            )
            
            # Prova a ripristinare backup se necessario
            await self._restore_backup()
            
        finally:
            self.updating = False
    
    async def _verify_update(self, update_data: bytes, update_info: Dict[str, Any]) -> bool:
        """Verifica l'integrità dell'aggiornamento"""
        try:
            # Verifica hash se fornito
            expected_hash = update_info.get('hash')
            if expected_hash:
                actual_hash = hashlib.sha256(update_data).hexdigest()
                if actual_hash != expected_hash:
                    self.logger.error(f"Hash non corrispondente: {actual_hash} != {expected_hash}")
                    return False
            
            # Verifica dimensione se fornita
            expected_size = update_info.get('size')
            if expected_size:
                if len(update_data) != expected_size:
                    self.logger.error(f"Dimensione non corrispondente: {len(update_data)} != {expected_size}")
                    return False
            
            self.logger.info("Verifica integrità aggiornamento superata")
            return True
            
        except Exception as e:
            self.logger.error(f"Errore nella verifica aggiornamento: {e}")
            return False
    
    async def _create_backup(self) -> Optional[Path]:
        """Crea un backup dell'applicazione corrente"""
        try:
            timestamp = asyncio.get_event_loop().time()
            backup_name = f"backup_{self.get_current_version()}_{int(timestamp)}.tar.gz"
            backup_path = self.backup_dir / backup_name
            
            self.logger.info(f"Creazione backup: {backup_path}")
            
            # Crea archivio tar.gz dell'applicazione corrente
            with tarfile.open(backup_path, 'w:gz') as tar:
                tar.add(self.app_dir, arcname='app')
            
            # Mantieni solo gli ultimi 5 backup
            await self._cleanup_old_backups()
            
            return backup_path
            
        except Exception as e:
            self.logger.error(f"Errore nella creazione backup: {e}")
            return None
    
    async def _extract_update(self, update_data: bytes, update_info: Dict[str, Any]) -> Optional[Path]:
        """Estrae l'aggiornamento"""
        try:
            # Determina il formato dell'archivio
            file_format = update_info.get('format', 'tar.gz')
            
            # Salva file temporaneo
            temp_file = self.update_dir / f"update_{update_info.get('id')}.{file_format}"
            async with aiofiles.open(temp_file, 'wb') as f:
                await f.write(update_data)
            
            # Directory di estrazione
            extract_dir = self.update_dir / f"extracted_{update_info.get('id')}"
            extract_dir.mkdir(exist_ok=True)
            
            # Estrai in base al formato
            if file_format in ['tar.gz', 'tgz']:
                with tarfile.open(temp_file, 'r:gz') as tar:
                    tar.extractall(extract_dir)
            elif file_format == 'zip':
                with zipfile.ZipFile(temp_file, 'r') as zip_ref:
                    zip_ref.extractall(extract_dir)
            else:
                raise Exception(f"Formato archivio non supportato: {file_format}")
            
            # Rimuovi file temporaneo
            temp_file.unlink()
            
            self.logger.info(f"Aggiornamento estratto in: {extract_dir}")
            return extract_dir
            
        except Exception as e:
            self.logger.error(f"Errore nell'estrazione aggiornamento: {e}")
            return None
    
    async def _apply_update(self, extracted_path: Path, update_info: Dict[str, Any]):
        """Applica l'aggiornamento"""
        try:
            # Esegui script pre-update se presente
            pre_script = extracted_path / 'scripts' / 'pre_update.sh'
            if pre_script.exists():
                await self._run_script(pre_script)
            
            # Copia nuovi file
            update_files = extracted_path / 'app'
            if update_files.exists():
                # Copia ricorsivamente i file
                await self._copy_update_files(update_files, self.app_dir)
            
            # Esegui script post-update se presente
            post_script = extracted_path / 'scripts' / 'post_update.sh'
            if post_script.exists():
                await self._run_script(post_script)
            
            # Installa dipendenze se necessario
            requirements_file = self.app_dir / 'requirements.txt'
            if requirements_file.exists():
                await self._install_requirements()
            
            self.logger.info("Aggiornamento applicato con successo")
            
        except Exception as e:
            self.logger.error(f"Errore nell'applicazione aggiornamento: {e}")
            raise
    
    async def _copy_update_files(self, source: Path, dest: Path):
        """Copia i file dell'aggiornamento"""
        try:
            # Usa shutil per copiare ricorsivamente
            if dest.exists():
                shutil.rmtree(dest)
            shutil.copytree(source, dest)
            
            # Imposta permessi corretti
            await self._set_file_permissions(dest)
            
        except Exception as e:
            self.logger.error(f"Errore nella copia file aggiornamento: {e}")
            raise
    
    async def _set_file_permissions(self, path: Path):
        """Imposta i permessi corretti sui file"""
        try:
            # File Python eseguibili
            for py_file in path.rglob('*.py'):
                os.chmod(py_file, 0o755)
            
            # Script bash eseguibili
            for sh_file in path.rglob('*.sh'):
                os.chmod(sh_file, 0o755)
                
            # Main.py eseguibile
            main_file = path / 'main.py'
            if main_file.exists():
                os.chmod(main_file, 0o755)
                
        except Exception as e:
            self.logger.error(f"Errore nell'impostazione permessi: {e}")
    
    async def _run_script(self, script_path: Path):
        """Esegue uno script di aggiornamento"""
        try:
            self.logger.info(f"Esecuzione script: {script_path}")
            
            result = await asyncio.create_subprocess_exec(
                'bash', str(script_path),
                stdout=asyncio.subprocess.PIPE,
                stderr=asyncio.subprocess.PIPE
            )
            
            stdout, stderr = await result.communicate()
            
            if result.returncode != 0:
                self.logger.error(f"Script fallito: {stderr.decode()}")
                raise Exception(f"Script fallito con codice {result.returncode}")
            else:
                self.logger.info(f"Script completato: {stdout.decode()}")
                
        except Exception as e:
            self.logger.error(f"Errore nell'esecuzione script: {e}")
            raise
    
    async def _install_requirements(self):
        """Installa i requirements Python"""
        try:
            self.logger.info("Installazione dipendenze Python...")
            
            venv_python = Path('/home/turnstile/venv/bin/python')
            requirements_file = self.app_dir / 'requirements.txt'
            
            result = await asyncio.create_subprocess_exec(
                str(venv_python), '-m', 'pip', 'install', '-r', str(requirements_file),
                stdout=asyncio.subprocess.PIPE,
                stderr=asyncio.subprocess.PIPE
            )
            
            stdout, stderr = await result.communicate()
            
            if result.returncode != 0:
                self.logger.error(f"Installazione dipendenze fallita: {stderr.decode()}")
                raise Exception(f"pip install fallito con codice {result.returncode}")
            else:
                self.logger.info("Dipendenze installate con successo")
                
        except Exception as e:
            self.logger.error(f"Errore nell'installazione dipendenze: {e}")
            raise
    
    async def _update_version(self, new_version: str):
        """Aggiorna il file versione"""
        try:
            async with aiofiles.open(self.version_file, 'w') as f:
                await f.write(new_version)
            self.logger.info(f"Versione aggiornata a: {new_version}")
        except Exception as e:
            self.logger.error(f"Errore nell'aggiornamento versione: {e}")
            raise
    
    async def _schedule_restart(self):
        """Programma il riavvio del servizio"""
        try:
            self.logger.info("Programmazione riavvio servizio...")
            
            # Crea file per segnalare il riavvio
            restart_file = Path('/home/turnstile/data/restart_required')
            restart_file.touch()
            
            # Il demone dovrebbe monitorare questo file e riavviare
            
        except Exception as e:
            self.logger.error(f"Errore nella programmazione riavvio: {e}")
    
    async def _restore_backup(self):
        """Ripristina il backup più recente"""
        try:
            # Trova il backup più recente
            backups = list(self.backup_dir.glob('backup_*.tar.gz'))
            if not backups:
                self.logger.error("Nessun backup disponibile per il ripristino")
                return
            
            latest_backup = max(backups, key=os.path.getctime)
            self.logger.info(f"Ripristino backup: {latest_backup}")
            
            # Rimuovi directory corrente
            if self.app_dir.exists():
                shutil.rmtree(self.app_dir)
            
            # Estrai backup
            with tarfile.open(latest_backup, 'r:gz') as tar:
                tar.extractall(self.app_dir.parent)
            
            self.logger.info("Backup ripristinato con successo")
            
        except Exception as e:
            self.logger.error(f"Errore nel ripristino backup: {e}")
    
    async def _cleanup_old_backups(self):
        """Rimuove i backup più vecchi"""
        try:
            backups = list(self.backup_dir.glob('backup_*.tar.gz'))
            backups.sort(key=os.path.getctime, reverse=True)
            
            # Mantieni solo gli ultimi 5 backup
            for old_backup in backups[5:]:
                old_backup.unlink()
                self.logger.info(f"Backup rimosso: {old_backup}")
                
        except Exception as e:
            self.logger.error(f"Errore nella pulizia backup: {e}")