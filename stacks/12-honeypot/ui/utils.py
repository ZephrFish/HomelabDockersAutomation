import os
import json
import time
from typing import Any

CONFIG_PATH   = "/etc/opencanaryd/opencanary.conf"
LOG_PATH      = "/var/tmp/opencanary.log"
SETTINGS_FILE = "/data/settings.conf"
BACKUP_DIR    = "/data/backups"


def read_text(path: str) -> str:
    if not os.path.exists(path):
        return ""
    b = open(path, "rb").read()
    for enc in ("utf-8", "cp1252"):
        try:
            return b.decode(enc)
        except Exception:
            pass
    return b.decode("utf-8", "ignore")


def load_json(path: str) -> dict:
    txt = read_text(path)
    if not txt.strip():
        return {}
    try:
        return json.loads(txt)
    except json.JSONDecodeError:
        return {}


def save_json(path: str, data: dict):
    tmp_path = path + ".tmp"
    with open(tmp_path, "w", encoding="utf-8") as f:
        json.dump(data, f, indent=2)
    os.replace(tmp_path, path)


def restart_opencanary():
    """Restart the opencanary container via Docker socket."""
    import docker
    client = docker.from_env()
    container = client.containers.get("opencanary")
    container.restart()
    time.sleep(3)


def load_settings() -> dict:
    return load_json(SETTINGS_FILE)


def save_settings(settings: dict):
    os.makedirs(os.path.dirname(SETTINGS_FILE), exist_ok=True)
    save_json(SETTINGS_FILE, settings)


def get_setting(key_path: str, default: Any = None) -> Any:
    settings = load_settings()
    keys = key_path.split(".")
    current = settings
    for k in keys:
        if isinstance(current, dict) and k in current:
            current = current[k]
        else:
            return default
    return current


def set_setting(key_path: str, value: Any) -> None:
    settings = load_settings()
    keys = key_path.split(".")
    current = settings
    for k in keys[:-1]:
        if k not in current or not isinstance(current[k], dict):
            current[k] = {}
        current = current[k]
    current[keys[-1]] = value
    save_settings(settings)


def delete_setting(key_path: str) -> None:
    settings = load_settings()
    keys = key_path.split(".")
    current = settings
    for k in keys[:-1]:
        if k not in current or not isinstance(current[k], dict):
            return
        current = current[k]
    current.pop(keys[-1], None)
    save_settings(settings)
