from __future__ import annotations

import asyncio
import json
import shutil
import sqlite3
import sys
import time
import uuid
from pathlib import Path
from typing import Any


PYROGRAM_SCHEMA = """
CREATE TABLE sessions
(
    dc_id     INTEGER PRIMARY KEY,
    api_id    INTEGER,
    test_mode INTEGER,
    auth_key  BLOB,
    date      INTEGER NOT NULL,
    user_id   INTEGER,
    is_bot    INTEGER
);
CREATE TABLE peers
(
    id             INTEGER PRIMARY KEY,
    access_hash    INTEGER,
    type           INTEGER NOT NULL,
    username       TEXT,
    phone_number   TEXT,
    last_update_on INTEGER NOT NULL DEFAULT (CAST(STRFTIME('%s', 'now') AS INTEGER))
);
CREATE TABLE version (number INTEGER PRIMARY KEY);
CREATE INDEX idx_peers_id ON peers (id);
CREATE INDEX idx_peers_username ON peers (username);
CREATE INDEX idx_peers_phone_number ON peers (phone_number);
CREATE TRIGGER trg_peers_last_update_on
    AFTER UPDATE ON peers
BEGIN
    UPDATE peers
    SET last_update_on = CAST(STRFTIME('%s', 'now') AS INTEGER)
    WHERE id = NEW.id;
END;
"""

PROFILE_JSON_FILE = "profile.json"


def emit(event: str, **payload: Any) -> None:
    message = json.dumps({"event": event, **payload}, ensure_ascii=False)
    sys.stdout.buffer.write((message + "\n").encode("utf-8"))
    sys.stdout.buffer.flush()


def resolve_tdata(source: str) -> Path:
    selected = Path(source).expanduser().resolve()
    folder = selected if selected.name.lower() == "tdata" else selected / "tdata"
    if not folder.is_dir():
        raise ValueError("Выбранная папка не содержит tdata")
    if not any((folder / marker).exists() for marker in ("key_data", "key_datas")):
        raise ValueError("В tdata не найден файл ключа key_data")
    return folder


def create_pyrogram_session(
    path: Path,
    *,
    dc_id: int,
    api_id: int,
    auth_key: bytes,
    user_id: int,
    is_bot: bool,
) -> None:
    if len(auth_key) != 256:
        raise ValueError("Некорректный MTProto auth key")
    connection = sqlite3.connect(path)
    try:
        with connection:
            connection.executescript(PYROGRAM_SCHEMA)
            connection.execute("INSERT INTO version VALUES (?)", (3,))
            connection.execute(
                "INSERT INTO sessions VALUES (?, ?, ?, ?, ?, ?, ?)",
                (dc_id, api_id, 0, auth_key, int(time.time()), user_id, int(is_bot)),
            )
    finally:
        connection.close()


def _clean_name(*parts: str) -> str:
    return " ".join(part.strip() for part in parts if part and part.strip()).strip()


def _optional_text(value: Any) -> str | None:
    text = str(value or "").strip()
    return text or None


def _api_attr(api: Any, name: str, default: Any) -> Any:
    value = getattr(api, name, default)
    return default if value is None else value


def normalize_proxy(value: str) -> str:
    text = str(value or "").strip()
    for prefix in ("socks5://", "socks://"):
        if text.casefold().startswith(prefix):
            text = text[len(prefix) :]
            break
    return text.strip()


def telethon_proxy(value: str) -> tuple[Any, ...] | None:
    text = normalize_proxy(value)
    if not text:
        return None

    username = ""
    password = ""
    host_port = text
    if "@" in text:
        auth, host_port = text.rsplit("@", 1)
        if ":" not in auth:
            raise ValueError("Формат прокси: login:password@ip:port")
        username, password = auth.split(":", 1)
        if not username or not password:
            raise ValueError("Формат прокси: login:password@ip:port")

    if ":" not in host_port:
        raise ValueError("Формат прокси: login:password@ip:port")
    host, port_text = host_port.rsplit(":", 1)
    host = host.strip()
    if not host:
        raise ValueError("Формат прокси: login:password@ip:port")
    try:
        port = int(port_text)
    except ValueError as exc:
        raise ValueError("Порт прокси должен быть числом") from exc
    if not 1 <= port <= 65535:
        raise ValueError("Порт прокси должен быть от 1 до 65535")

    return ("socks5", host, port, True, username or None, password or None)


def build_profile_json(
    *,
    api: Any,
    user: Any,
    avatar_name: str,
    imported_at: int,
    proxy: str,
) -> dict[str, Any]:
    return {
        "app_id": int(_api_attr(api, "api_id", 2040)),
        "app_hash": str(_api_attr(api, "api_hash", "888888888888888888888")),
        "device": str(_api_attr(api, "device_model", "B9TK_O-EXTREME")),
        "sdk": str(_api_attr(api, "system_version", "Windows 10 x64")),
        "app_version": str(_api_attr(api, "app_version", "6.9.3 x64")),
        "system_lang_pack": str(_api_attr(api, "system_lang_pack", "en-US")),
        "system_lang_code": str(_api_attr(api, "system_lang_code", "en-US")),
        "lang_pack": str(_api_attr(api, "lang_pack", "tdesktop")),
        "lang_code": str(_api_attr(api, "lang_code", "en")),
        "twoFA": None,
        "role": "",
        "id": int(user.id) if getattr(user, "id", None) is not None else None,
        "phone": _optional_text(getattr(user, "phone", "")),
        "username": _optional_text(getattr(user, "username", "")),
        "date_of_birth": None,
        "date_of_birth_integrity": None,
        "is_premium": bool(getattr(user, "premium", False)),
        "has_profile_pic": bool(avatar_name or getattr(user, "photo", None)),
        "spamblock": None,
        "register_time": imported_at,
        "last_check_time": imported_at,
        "avatar": avatar_name or None,
        "first_name": str(getattr(user, "first_name", "") or ""),
        "last_name": str(getattr(user, "last_name", "") or ""),
        "sex": None,
        "proxy": normalize_proxy(proxy) or None,
        "ipv6": False,
        "session_file": "telethon.session",
    }


def next_profile_dir(root: Path) -> Path:
    index = 1
    while True:
        candidate = root / f"Profile_{index}"
        if not candidate.exists():
            return candidate
        index += 1


async def import_account(request: dict[str, Any]) -> dict[str, Any]:
    try:
        from opentele.api import API, UseCurrentSession
        from opentele.td import TDesktop
    except ImportError as exc:
        missing_module = str(getattr(exc, "name", "") or "opentele").split(".", 1)[0]
        raise RuntimeError(
            f"Не установлен компонент «{missing_module}». "
            "Закройте приложение и запустите install.bat"
        ) from exc

    source_tdata = resolve_tdata(str(request.get("source_tdata", "")))
    accounts_root = Path(str(request["accounts_root"])).resolve()
    accounts_root.mkdir(parents=True, exist_ok=True)
    job_id = str(request.get("job_id") or uuid.uuid4())
    mode = str(request.get("mode") or "import").casefold()
    refresh_mode = mode == "refresh"
    effective_proxy = normalize_proxy(str(request.get("proxy") or ""))
    account_proxy = normalize_proxy(str(request.get("account_proxy") or ""))
    proxy_tuple = telethon_proxy(effective_proxy)
    staging = accounts_root / f".import-{job_id}"
    if staging.exists():
        shutil.rmtree(staging)

    client = None
    final_dir: Path | None = None
    try:
        emit("progress", value=12, message="Копирование tdata…")
        target_tdata = staging / "tdata"
        shutil.copytree(source_tdata, target_tdata)

        emit("progress", value=38, message="Чтение Telegram Desktop-сессии…")
        passcode = str(request.get("passcode") or "")
        desktop = TDesktop(str(target_tdata), passcode=passcode or None)
        if not desktop.isLoaded() or desktop.accountsCount < 1:
            raise RuntimeError("Не удалось прочитать аккаунт из tdata")

        emit("progress", value=56, message="Создание Telethon-сессии…")
        telethon_base = staging / "telethon"
        client = await desktop.ToTelethon(
            session=str(telethon_base),
            flag=UseCurrentSession,
            api=API.TelegramDesktop,
            proxy=proxy_tuple,
        )
        await client.connect()
        if not await client.is_user_authorized():
            raise RuntimeError("Сессия tdata больше не авторизована")

        emit("progress", value=72, message="Получение данных аккаунта…")
        user = await client.get_me()
        if user is None:
            raise RuntimeError("Telegram не вернул данные аккаунта")

        session = client.session
        auth_key_obj = session.auth_key
        auth_key = auth_key_obj.key if auth_key_obj else b""
        dc_id = int(session.dc_id)
        api_id = int(API.TelegramDesktop.api_id)
        api_hash = str(API.TelegramDesktop.api_hash)

        emit("progress", value=84, message="Создание Pyrogram-сессии…")
        pyrogram_path = staging / "pyrogram.session"
        create_pyrogram_session(
            pyrogram_path,
            dc_id=dc_id,
            api_id=api_id,
            auth_key=auth_key,
            user_id=int(user.id),
            is_bot=bool(getattr(user, "bot", False)),
        )

        avatar_name = ""
        try:
            avatar_path = staging / "avatar.jpg"
            downloaded = await client.download_profile_photo(user, file=str(avatar_path))
            if downloaded and avatar_path.is_file():
                avatar_name = avatar_path.name
        except Exception:
            avatar_name = ""

        session.save()
        await client.disconnect()
        session.close()
        client = None

        telegram_user_id = str(int(user.id))
        if telegram_user_id in {
            str(value).strip()
            for value in request.get("existing_telegram_user_ids", [])
            if str(value).strip()
        }:
            raise RuntimeError("Этот Telegram-аккаунт уже импортирован")

        account_id = f"tg_{telegram_user_id}"
        if refresh_mode:
            final_dir = Path(str(request.get("target_dir") or "")).expanduser().resolve()
            if not final_dir.is_dir():
                raise RuntimeError("Папка профиля для обновления не найдена")
        else:
            final_dir = next_profile_dir(accounts_root)

        display_name = _clean_name(
            str(getattr(user, "first_name", "") or ""),
            str(getattr(user, "last_name", "") or ""),
        ) or str(request.get("display_name") or "Аккаунт Telegram")

        imported_at = int(time.time())
        metadata = {
            "accountId": account_id,
            "name": display_name,
            "phone": str(getattr(user, "phone", "") or ""),
            "username": str(getattr(user, "username", "") or ""),
            "firstName": str(getattr(user, "first_name", "") or ""),
            "lastName": str(getattr(user, "last_name", "") or ""),
            "telegramUserId": str(int(user.id)),
            "profileFolder": final_dir.name,
            "isPremium": bool(getattr(user, "premium", False)),
            "isBot": bool(getattr(user, "bot", False)),
            "dcId": dc_id,
            "apiId": api_id,
            "apiHash": api_hash,
            "avatarFile": avatar_name,
            "telethonSessionFile": "telethon.session",
            "pyrogramSessionFile": "pyrogram.session",
            "profileJsonFile": PROFILE_JSON_FILE,
            "importedAt": imported_at,
            "proxy": account_proxy,
            "usedProxy": effective_proxy,
        }
        (staging / "account.json").write_text(
            json.dumps(metadata, ensure_ascii=False, indent=2), encoding="utf-8"
        )
        (staging / PROFILE_JSON_FILE).write_text(
            json.dumps(
                build_profile_json(
                    api=API.TelegramDesktop,
                    user=user,
                    avatar_name=avatar_name,
                    imported_at=imported_at,
                    proxy=effective_proxy,
                ),
                ensure_ascii=False,
                indent=2,
            ),
            encoding="utf-8",
        )

        if refresh_mode:
            emit("progress", value=94, message="Обновление локального профиля…")
            for file_name in (
                "telethon.session",
                "pyrogram.session",
                "account.json",
                PROFILE_JSON_FILE,
            ):
                source_file = staging / file_name
                if source_file.is_file():
                    shutil.copy2(source_file, final_dir / file_name)
            if avatar_name and (staging / avatar_name).is_file():
                shutil.copy2(staging / avatar_name, final_dir / avatar_name)
            shutil.rmtree(staging, ignore_errors=True)
        else:
            emit("progress", value=94, message="Сохранение локального профиля…")
            staging.rename(final_dir)

        return {
            **metadata,
            "accountDirectory": str(final_dir),
            "tdataPath": str(final_dir / "tdata"),
            "telethonSession": str(final_dir / "telethon.session"),
            "pyrogramSession": str(final_dir / "pyrogram.session"),
            "profileJsonPath": str(final_dir / PROFILE_JSON_FILE),
            "avatarPath": str(final_dir / avatar_name) if avatar_name else "",
            "notes": str(request.get("notes") or ""),
            "color": str(request.get("color") or "#7657F6"),
            "favorite": bool(request.get("favorite", False)),
            "proxy": account_proxy,
        }
    except Exception:
        if client is not None:
            try:
                await client.disconnect()
            except Exception:
                pass
        if staging.exists():
            shutil.rmtree(staging, ignore_errors=True)
        raise


def friendly_error(exc: Exception) -> str:
    text = str(exc).strip() or exc.__class__.__name__
    lowered = text.casefold()
    if "decrypt" in lowered or "passcode" in lowered:
        return "tdata защищена локальным паролем — укажите его и повторите"
    if "auth key" in lowered:
        return "Не удалось извлечь ключ авторизации из tdata"
    if "proxy" in lowered or "socks" in lowered:
        return f"Прокси не сработал: {text}"
    return text


def main() -> int:
    try:
        raw = sys.stdin.buffer.readline().decode("utf-8")
        request = json.loads(raw)
        result = asyncio.run(import_account(request))
        emit("complete", value=100, message="Аккаунт импортирован", result=result)
        return 0
    except Exception as exc:
        emit("error", message=friendly_error(exc))
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
