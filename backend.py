from __future__ import annotations

import json
import os
import re
import shutil
import sqlite3
import subprocess
import sys
import tarfile
import time
import uuid
import zipfile
from datetime import datetime, timezone
from pathlib import Path
from typing import Any
from urllib.parse import quote

from PySide6.QtCore import (
    QAbstractListModel,
    QByteArray,
    QFileSystemWatcher,
    QModelIndex,
    QObject,
    Property,
    QProcess,
    QSortFilterProxyModel,
    QTimer,
    QUrl,
    Qt,
    Signal,
    Slot,
)
from PySide6.QtGui import QDesktopServices
from PySide6.QtNetwork import QNetworkAccessManager, QNetworkReply, QNetworkRequest

SUPPORTED_TDATA_ARCHIVE_SUFFIXES = (
    ".zip",
    ".tar",
    ".tar.gz",
    ".tgz",
    ".tar.bz2",
    ".tbz2",
    ".tar.xz",
    ".txz",
    ".7z",
    ".rar",
)

IGNORED_PROFILE_MARKER = ".tga-ignore"


def _now_iso() -> str:
    return datetime.now(timezone.utc).isoformat(timespec="seconds")


def _normalized_path(value: str) -> str:
    value = value.strip().strip('"')
    if not value:
        return ""
    return str(Path(value).expanduser().resolve())


def _path_key(path: str | Path) -> str:
    try:
        resolved = Path(path).expanduser().resolve()
    except (OSError, RuntimeError):
        resolved = Path(path)
    text = str(resolved)
    return text.casefold() if sys.platform == "win32" else text


def _clean_name(*parts: str) -> str:
    return " ".join(part.strip() for part in parts if part and part.strip()).strip()


def _is_profile_folder_name(name: str) -> bool:
    return re.fullmatch(r"Profile_\d+", name, flags=re.IGNORECASE) is not None


def _next_profile_dir(root: Path, reserved: set[str] | None = None) -> Path:
    reserved = reserved or set()
    index = 1
    while True:
        candidate = root / f"Profile_{index}"
        if not candidate.exists() and _path_key(candidate) not in reserved:
            return candidate
        index += 1


def _application_root() -> Path:
    if getattr(sys, "frozen", False):
        return Path(sys.executable).resolve().parent
    return Path(__file__).resolve().parent


def _profiles_root() -> Path:
    root = _application_root() / "data"
    root.mkdir(parents=True, exist_ok=True)
    return root


def _normalize_proxy(value: str) -> str:
    text = str(value or "").strip()
    for prefix in ("socks5://", "socks://"):
        if text.casefold().startswith(prefix):
            text = text[len(prefix) :]
            break
    return text.strip()


def _parse_proxy(value: str) -> dict[str, Any]:
    text = _normalize_proxy(value)
    if not text:
        return {}

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

    return {
        "scheme": "socks5",
        "username": username,
        "password": password,
        "host": host,
        "port": port,
    }


def _telegram_socks_url(proxy: str) -> str:
    parsed = _parse_proxy(proxy)
    if not parsed:
        return ""
    query = f"server={quote(str(parsed['host']), safe='')}&port={parsed['port']}"
    if parsed.get("username"):
        query += f"&user={quote(str(parsed['username']), safe='')}"
    if parsed.get("password"):
        query += f"&pass={quote(str(parsed['password']), safe='')}"
    return f"tg://socks?{query}"


def _is_relative_to(child: Path, parent: Path) -> bool:
    try:
        child.resolve().relative_to(parent.resolve())
        return True
    except (OSError, RuntimeError, ValueError):
        return False


def _safe_extract_zip(archive: Path, destination: Path) -> None:
    destination.mkdir(parents=True, exist_ok=True)
    root = destination.resolve()
    with zipfile.ZipFile(archive) as zip_archive:
        for member in zip_archive.infolist():
            target = (destination / member.filename).resolve()
            if not _is_relative_to(target, root):
                raise ValueError("Архив содержит небезопасный путь")
        zip_archive.extractall(destination)


def _safe_extract_tar(archive: Path, destination: Path) -> None:
    destination.mkdir(parents=True, exist_ok=True)
    root = destination.resolve()
    with tarfile.open(archive) as tar_archive:
        for member in tar_archive.getmembers():
            if member.issym() or member.islnk():
                raise ValueError("Архив содержит небезопасную ссылку")
            target = (destination / member.name).resolve()
            if not _is_relative_to(target, root):
                raise ValueError("Архив содержит небезопасный путь")
        tar_archive.extractall(destination)


def _extract_archive(archive: Path, destination: Path) -> None:
    name = archive.name.casefold()
    if zipfile.is_zipfile(archive):
        _safe_extract_zip(archive, destination)
        return
    if tarfile.is_tarfile(archive):
        _safe_extract_tar(archive, destination)
        return

    if name.endswith((".7z", ".rar")):
        seven_zip = shutil.which("7z") or shutil.which("7za") or shutil.which("7zr")
        if not seven_zip:
            raise RuntimeError("Для .7z/.rar нужен 7-Zip в PATH. Либо используйте .zip архив.")
        destination.mkdir(parents=True, exist_ok=True)
        subprocess.run(
            [seven_zip, "x", "-y", f"-o{destination}", str(archive)],
            check=True,
            capture_output=True,
            text=True,
            timeout=180,
        )
        return

    raise ValueError("Поддерживаются архивы .zip, .tar, .tar.gz, .tar.xz, .tar.bz2, .7z и .rar")


def _is_supported_tdata_archive(path: Path) -> bool:
    name = path.name.casefold()
    return (
        path.is_file()
        and not path.name.startswith(".")
        and any(name.endswith(suffix) for suffix in SUPPORTED_TDATA_ARCHIVE_SUFFIXES)
    )


def _unique_child_path(directory: Path, filename: str) -> Path:
    target = directory / filename
    if not target.exists():
        return target

    source = Path(filename)
    stem = source.stem or "archive"
    suffix = source.suffix
    counter = 2
    while True:
        candidate = directory / f"{stem}_{counter}{suffix}"
        if not candidate.exists():
            return candidate
        counter += 1


def _ignore_archive_profile_noise(_directory: str, names: list[str]) -> set[str]:
    return {
        name
        for name in names
        if name in {"__MACOSX", ".DS_Store", ".tdata-wrapper"}
        or name.casefold() in {"thumbs.db", "desktop.ini"}
    }


def _find_tdata_folder(root: Path) -> Path | None:
    def is_tdata_content(folder: Path) -> bool:
        return folder.is_dir() and any(
            (folder / marker).exists() for marker in ("key_data", "key_datas")
        )

    direct = root if root.name.casefold() == "tdata" else root / "tdata"
    if is_tdata_content(direct):
        return direct
    if is_tdata_content(root):
        return root
    for folder in root.rglob("tdata"):
        if is_tdata_content(folder):
            return folder
    return None


def _ensure_named_tdata_folder(root: Path, folder: Path) -> Path:
    if folder.name.casefold() == "tdata":
        return folder

    wrapper_root = root / ".tdata-wrapper"
    wrapper_tdata = wrapper_root / "tdata"
    shutil.rmtree(wrapper_root, ignore_errors=True)

    root_resolved = root.resolve()

    def ignore(directory: str, names: list[str]) -> set[str]:
        try:
            if Path(directory).resolve() == root_resolved:
                return {".tdata-wrapper"}
        except (OSError, RuntimeError):
            pass
        return set()

    shutil.copytree(folder, wrapper_tdata, ignore=ignore)
    return wrapper_tdata


class AccountModel(QAbstractListModel):
    IdRole = Qt.UserRole + 1
    NameRole = Qt.UserRole + 2
    PhoneRole = Qt.UserRole + 3
    TdataPathRole = Qt.UserRole + 4
    ClientPathRole = Qt.UserRole + 5
    NotesRole = Qt.UserRole + 6
    ColorRole = Qt.UserRole + 7
    FavoriteRole = Qt.UserRole + 8
    RunningRole = Qt.UserRole + 9
    LastLaunchedRole = Qt.UserRole + 10
    CreatedAtRole = Qt.UserRole + 11
    InitialsRole = Qt.UserRole + 12
    PathValidRole = Qt.UserRole + 13
    UsernameRole = Qt.UserRole + 14
    TelegramUserIdRole = Qt.UserRole + 15
    PremiumRole = Qt.UserRole + 16
    AuthorizedRole = Qt.UserRole + 17
    AccountDirectoryRole = Qt.UserRole + 18
    TelethonSessionRole = Qt.UserRole + 19
    PyrogramSessionRole = Qt.UserRole + 20
    AvatarPathRole = Qt.UserRole + 21
    DcIdRole = Qt.UserRole + 22
    ProxyRole = Qt.UserRole + 23

    _roles = {
        IdRole: QByteArray(b"accountId"),
        NameRole: QByteArray(b"name"),
        PhoneRole: QByteArray(b"phone"),
        TdataPathRole: QByteArray(b"tdataPath"),
        ClientPathRole: QByteArray(b"clientPath"),
        NotesRole: QByteArray(b"notes"),
        ColorRole: QByteArray(b"profileColor"),
        FavoriteRole: QByteArray(b"favorite"),
        RunningRole: QByteArray(b"running"),
        LastLaunchedRole: QByteArray(b"lastLaunched"),
        CreatedAtRole: QByteArray(b"createdAt"),
        InitialsRole: QByteArray(b"initials"),
        PathValidRole: QByteArray(b"pathValid"),
        UsernameRole: QByteArray(b"username"),
        TelegramUserIdRole: QByteArray(b"telegramUserId"),
        PremiumRole: QByteArray(b"isPremium"),
        AuthorizedRole: QByteArray(b"authorized"),
        AccountDirectoryRole: QByteArray(b"accountDirectory"),
        TelethonSessionRole: QByteArray(b"telethonSession"),
        PyrogramSessionRole: QByteArray(b"pyrogramSession"),
        AvatarPathRole: QByteArray(b"avatarPath"),
        DcIdRole: QByteArray(b"dcId"),
        ProxyRole: QByteArray(b"proxy"),
    }

    countChanged = Signal()
    runningCountChanged = Signal()
    dataPersisted = Signal()

    def __init__(self, parent: QObject | None = None) -> None:
        super().__init__(parent)
        self._items: list[dict[str, Any]] = []
        data_dir = _profiles_root()
        self._storage_path = data_dir / "accounts.json"
        self._load()
        self.scan_data_profiles()

    def roleNames(self) -> dict[int, QByteArray]:
        return self._roles

    def rowCount(self, parent: QModelIndex = QModelIndex()) -> int:
        return 0 if parent.isValid() else len(self._items)

    def data(self, index: QModelIndex, role: int = Qt.DisplayRole) -> Any:
        if not index.isValid() or not 0 <= index.row() < len(self._items):
            return None
        item = self._items[index.row()]
        key = bytes(self._roles.get(role, b"")).decode()
        if key == "initials":
            words = [part for part in item["name"].split() if part]
            return "".join(word[0].upper() for word in words[:2]) or "TG"
        if key == "pathValid":
            return self._is_tdata_valid(item["tdataPath"])
        if key == "profileColor":
            return item["color"]
        if key:
            return item.get(key)
        if role == Qt.DisplayRole:
            return item["name"]
        return None

    @property
    def storage_path(self) -> Path:
        return self._storage_path

    def _load(self) -> None:
        if not self._storage_path.exists():
            return
        try:
            payload = json.loads(self._storage_path.read_text(encoding="utf-8"))
            items = payload.get("accounts", []) if isinstance(payload, dict) else []
            if isinstance(items, list):
                self._items = [self._sanitize(item) for item in items if isinstance(item, dict)]
        except (OSError, json.JSONDecodeError):
            self._items = []

    def _save(self) -> None:
        payload = {
            "version": 1,
            "accounts": [
                {key: value for key, value in item.items() if key != "running"}
                for item in self._items
            ],
        }
        temporary = self._storage_path.with_suffix(".json.tmp")
        temporary.write_text(json.dumps(payload, ensure_ascii=False, indent=2), encoding="utf-8")
        os.replace(temporary, self._storage_path)
        self.dataPersisted.emit()

    @staticmethod
    def _sanitize(item: dict[str, Any]) -> dict[str, Any]:
        return {
            "accountId": str(item.get("accountId") or uuid.uuid4()),
            "name": str(item.get("name") or "Без имени"),
            "phone": str(item.get("phone") or ""),
            "tdataPath": str(item.get("tdataPath") or ""),
            "clientPath": str(item.get("clientPath") or ""),
            "notes": str(item.get("notes") or ""),
            "color": str(item.get("color") or "#7C5CFC"),
            "favorite": bool(item.get("favorite", False)),
            "running": False,
            "lastLaunched": str(item.get("lastLaunched") or ""),
            "createdAt": str(item.get("createdAt") or _now_iso()),
            "username": str(item.get("username") or ""),
            "firstName": str(item.get("firstName") or ""),
            "lastName": str(item.get("lastName") or ""),
            "telegramUserId": str(item.get("telegramUserId") or ""),
            "isPremium": bool(item.get("isPremium", False)),
            "isBot": bool(item.get("isBot", False)),
            "authorized": bool(item.get("authorized", False)),
            "dcId": int(item.get("dcId") or 0),
            "apiId": int(item.get("apiId") or 0),
            "accountDirectory": str(item.get("accountDirectory") or ""),
            "telethonSession": str(item.get("telethonSession") or ""),
            "pyrogramSession": str(item.get("pyrogramSession") or ""),
            "profileJsonPath": str(item.get("profileJsonPath") or ""),
            "avatarPath": str(item.get("avatarPath") or ""),
            "proxy": _normalize_proxy(str(item.get("proxy") or "")),
        }

    @staticmethod
    def _is_tdata_valid(path: str) -> bool:
        folder = Path(path)
        if folder.name.lower() != "tdata":
            folder = folder / "tdata"
        return folder.is_dir() and any(
            (folder / marker).exists() for marker in ("key_data", "key_datas")
        )

    def index_of(self, account_id: str) -> int:
        return next(
            (i for i, item in enumerate(self._items) if item["accountId"] == account_id),
            -1,
        )

    def item_by_id(self, account_id: str) -> dict[str, Any] | None:
        row = self.index_of(account_id)
        return self._items[row] if row >= 0 else None

    def telegram_user_ids(self, exclude_account_id: str = "") -> list[str]:
        return sorted(
            {
                str(item.get("telegramUserId") or "").strip()
                for item in self._items
                if item.get("accountId") != exclude_account_id
                if str(item.get("telegramUserId") or "").strip()
            }
        )

    @Slot(result=int)
    def scanDataProfiles(self) -> int:
        return self.scan_data_profiles()

    def scan_data_profiles(self) -> int:
        data_root = self._storage_path.parent
        if not data_root.is_dir():
            return 0

        self._pack_root_tdata_profile(data_root)
        self._normalize_existing_profile_paths(data_root)

        existing_dirs = {
            _path_key(item.get("accountDirectory", ""))
            for item in self._items
            if item.get("accountDirectory")
        }
        existing_tdata = {
            _path_key(item.get("tdataPath", ""))
            for item in self._items
            if item.get("tdataPath")
        }
        existing_users = set(self.telegram_user_ids())
        added: list[dict[str, Any]] = []
        reserved_dirs = set(existing_dirs)

        for folder in sorted(data_root.iterdir(), key=lambda value: value.name.casefold()):
            if not folder.is_dir() or folder.name.startswith("."):
                continue
            if folder.name in {"__pycache__"}:
                continue
            if (folder / IGNORED_PROFILE_MARKER).is_file():
                continue
            if _path_key(folder) in existing_dirs:
                continue

            folder = self._normalize_detected_folder(data_root, folder, reserved_dirs)
            if _path_key(folder) in existing_dirs:
                continue

            payload = self._payload_from_profile_folder(folder)
            if not payload:
                continue

            user_id = str(payload.get("telegramUserId") or "").strip()
            tdata_key = _path_key(payload.get("tdataPath", ""))
            if user_id and user_id in existing_users:
                continue
            if tdata_key and tdata_key in existing_tdata:
                continue
            if self.index_of(str(payload["accountId"])) >= 0:
                continue

            item = self._sanitize({**payload, "clientPath": ""})
            added.append(item)
            existing_dirs.add(_path_key(item["accountDirectory"]))
            reserved_dirs.add(_path_key(item["accountDirectory"]))
            existing_tdata.add(_path_key(item["tdataPath"]))
            if item["telegramUserId"]:
                existing_users.add(item["telegramUserId"])

        if not added:
            return 0

        first = len(self._items)
        last = first + len(added) - 1
        self.beginInsertRows(QModelIndex(), first, last)
        self._items.extend(added)
        self.endInsertRows()
        self._save()
        self.countChanged.emit()
        return len(added)

    def _normalize_existing_profile_paths(self, data_root: Path) -> None:
        changed_rows: list[int] = []
        reserved = {
            _path_key(item.get("accountDirectory", ""))
            for item in self._items
            if item.get("accountDirectory")
        }
        for row, item in enumerate(self._items):
            if item.get("running"):
                continue
            account_dir_text = str(item.get("accountDirectory") or "")
            if not account_dir_text:
                continue
            account_dir = Path(account_dir_text)
            try:
                account_dir = account_dir.resolve()
                if account_dir.parent != data_root.resolve():
                    continue
            except (OSError, RuntimeError):
                continue
            if _is_profile_folder_name(account_dir.name) or not account_dir.is_dir():
                continue

            old_dir = account_dir
            target = _next_profile_dir(data_root, reserved)
            try:
                old_dir.rename(target)
            except OSError:
                continue
            reserved.discard(_path_key(old_dir))
            reserved.add(_path_key(target))
            self._retarget_item_paths(item, old_dir, target)
            changed_rows.append(row)

        if changed_rows:
            for row in changed_rows:
                idx = self.index(row)
                self.dataChanged.emit(idx, idx, list(self._roles.keys()))
            self._save()

    @staticmethod
    def _retarget_item_paths(item: dict[str, Any], old_dir: Path, new_dir: Path) -> None:
        old_resolved = old_dir.resolve()
        for key in (
            "accountDirectory",
            "tdataPath",
            "telethonSession",
            "pyrogramSession",
            "profileJsonPath",
            "avatarPath",
        ):
            value = str(item.get(key) or "")
            if not value:
                continue
            path = Path(value)
            try:
                resolved = path.resolve()
                relative = resolved.relative_to(old_resolved)
            except (OSError, RuntimeError, ValueError):
                if key == "accountDirectory":
                    item[key] = str(new_dir)
                continue
            item[key] = str(new_dir / relative)

    @staticmethod
    def _normalize_detected_folder(
        data_root: Path, folder: Path, reserved: set[str]
    ) -> Path:
        if _is_profile_folder_name(folder.name):
            reserved.add(_path_key(folder))
            return folder
        if not AccountModel._is_tdata_valid(str(folder / "tdata")):
            return folder

        target = _next_profile_dir(data_root, reserved)
        try:
            folder.rename(target)
            reserved.add(_path_key(target))
            return target
        except OSError:
            reserved.add(_path_key(folder))
            return folder

    @staticmethod
    def _pack_root_tdata_profile(data_root: Path) -> Path | None:
        root_tdata = data_root / "tdata"
        if not AccountModel._is_tdata_valid(str(root_tdata)):
            return None

        target = _next_profile_dir(data_root)
        try:
            target.mkdir(parents=True, exist_ok=False)
            shutil.move(str(root_tdata), str(target / "tdata"))
            for file_path in sorted(data_root.iterdir(), key=lambda value: value.name.casefold()):
                if not file_path.is_file() or file_path.name.startswith("."):
                    continue
                lower_name = file_path.name.casefold()
                if lower_name == "accounts.json" or lower_name == "accounts.json.tmp":
                    continue
                if (
                    lower_name.endswith(".session")
                    or lower_name.endswith(".json")
                    or lower_name in {"avatar.jpg", "avatar.jpeg", "avatar.png", "avatar.webp"}
                ):
                    shutil.move(str(file_path), str(target / file_path.name))
            return target
        except OSError:
            return None

    @classmethod
    def _payload_from_profile_folder(cls, folder: Path) -> dict[str, Any] | None:
        tdata_path = folder / "tdata"
        if not cls._is_tdata_valid(str(tdata_path)):
            return None

        metadata, metadata_path = cls._read_external_metadata(folder)
        session_files = sorted(folder.glob("*.session"), key=lambda value: value.name.casefold())
        metadata = metadata or {}

        telethon_session = cls._find_session_file(folder, metadata, "telethon")
        pyrogram_session = cls._find_session_file(folder, metadata, "pyrogram")
        telegram_user_id = cls._metadata_text(
            metadata, "telegramUserId", "id", "user_id", "userId"
        )
        if not telegram_user_id:
            telegram_user_id = cls._id_from_file_names(metadata_path, session_files)

        first_name = cls._metadata_text(metadata, "firstName", "first_name")
        last_name = cls._metadata_text(metadata, "lastName", "last_name")
        username = cls._metadata_text(metadata, "username")
        phone = cls._metadata_text(metadata, "phone")
        display_name = _clean_name(first_name, last_name) or username or phone or folder.name

        avatar_path = cls._find_avatar_file(folder, metadata)
        account_id = (
            f"tg_{telegram_user_id}"
            if telegram_user_id
            else f"local_{uuid.uuid5(uuid.NAMESPACE_URL, str(folder.resolve()))}"
        )
        profile_json = folder / "profile.json"
        payload = {
            "accountId": account_id,
            "name": display_name,
            "phone": phone,
            "tdataPath": str(tdata_path.resolve()),
            "notes": "Автообнаружено в папке data",
            "color": "#7657F6",
            "favorite": False,
            "username": username,
            "firstName": first_name,
            "lastName": last_name,
            "telegramUserId": telegram_user_id,
            "isPremium": cls._metadata_bool(metadata, "isPremium", "is_premium"),
            "isBot": cls._metadata_bool(metadata, "isBot", "is_bot"),
            "authorized": bool(telethon_session or pyrogram_session),
            "dcId": cls._metadata_int(metadata, "dcId", "dc_id"),
            "apiId": cls._metadata_int(metadata, "apiId", "app_id", "api_id"),
            "accountDirectory": str(folder.resolve()),
            "telethonSession": str(telethon_session.resolve()) if telethon_session else "",
            "pyrogramSession": str(pyrogram_session.resolve()) if pyrogram_session else "",
            "profileJsonPath": str(profile_json.resolve()),
            "avatarPath": str(avatar_path.resolve()) if avatar_path else "",
            "proxy": _normalize_proxy(cls._metadata_text(metadata, "proxy")),
        }
        cls._ensure_standard_profile_files(folder, payload, metadata)
        return payload

    @staticmethod
    def _read_external_metadata(folder: Path) -> tuple[dict[str, Any] | None, Path | None]:
        candidates: list[Path] = []
        for name in ("profile.json", "account.json"):
            path = folder / name
            if path.is_file():
                candidates.append(path)
        candidates.extend(
            path
            for path in sorted(folder.glob("*.json"), key=lambda value: value.name.casefold())
            if path.name not in {"profile.json", "account.json", "accounts.json"}
            and not path.name.startswith(".")
        )

        seen: set[str] = set()
        for path in candidates:
            key = _path_key(path)
            if key in seen:
                continue
            seen.add(key)
            try:
                payload = json.loads(path.read_text(encoding="utf-8"))
            except (OSError, UnicodeDecodeError, json.JSONDecodeError):
                continue
            if isinstance(payload, dict):
                return payload, path
        return None, None

    @staticmethod
    def _metadata_value(metadata: dict[str, Any], *keys: str) -> Any:
        for key in keys:
            if key in metadata and metadata[key] not in (None, ""):
                return metadata[key]
        return ""

    @classmethod
    def _metadata_text(cls, metadata: dict[str, Any], *keys: str) -> str:
        value = cls._metadata_value(metadata, *keys)
        if value in (None, ""):
            return ""
        if isinstance(value, float) and value.is_integer():
            value = int(value)
        return str(value).strip()

    @classmethod
    def _metadata_int(cls, metadata: dict[str, Any], *keys: str) -> int:
        value = cls._metadata_value(metadata, *keys)
        try:
            return int(value)
        except (TypeError, ValueError):
            return 0

    @classmethod
    def _metadata_bool(cls, metadata: dict[str, Any], *keys: str) -> bool:
        value = cls._metadata_value(metadata, *keys)
        if isinstance(value, bool):
            return value
        if isinstance(value, (int, float)):
            return bool(value)
        if isinstance(value, str):
            return value.strip().casefold() in {"1", "true", "yes", "y", "да"}
        return False

    @staticmethod
    def _id_from_file_names(metadata_path: Path | None, session_files: list[Path]) -> str:
        candidates = [metadata_path] if metadata_path else []
        candidates.extend(session_files)
        for path in candidates:
            if path is None:
                continue
            match = re.match(r"^(\d+)(?:[_-].*)?$", path.stem)
            if match:
                return match.group(1)
        return ""

    @classmethod
    def _find_session_file(
        cls, folder: Path, metadata: dict[str, Any], kind: str
    ) -> Path | None:
        keys = (
            ("telethonSession", "telethonSessionFile", "session_file")
            if kind == "telethon"
            else ("pyrogramSession", "pyrogramSessionFile")
        )
        for key in keys:
            value = cls._metadata_text(metadata, key)
            if not value:
                continue
            path = Path(value)
            if not path.is_absolute():
                path = folder / path
            if path.is_file():
                return path

        exact = folder / f"{kind}.session"
        if exact.is_file():
            return exact

        for path in sorted(folder.glob("*.session"), key=lambda value: value.name.casefold()):
            name = path.name.casefold()
            if kind == "telethon" and "telethon" in name:
                return path
            if kind == "pyrogram" and "pyrogram" in name:
                return path
        return None

    @classmethod
    def _find_avatar_file(cls, folder: Path, metadata: dict[str, Any]) -> Path | None:
        value = cls._metadata_text(metadata, "avatarPath", "avatarFile", "avatar")
        if value and value.casefold() not in {"none", "null"}:
            path = Path(value)
            if not path.is_absolute():
                path = folder / path
            if path.is_file():
                return path

        for name in ("avatar.jpg", "avatar.jpeg", "avatar.png", "avatar.webp"):
            path = folder / name
            if path.is_file():
                return path
        return None

    @classmethod
    def _ensure_standard_profile_files(
        cls, folder: Path, payload: dict[str, Any], metadata: dict[str, Any]
    ) -> None:
        imported_at = cls._metadata_int(metadata, "register_time", "importedAt") or int(time.time())
        last_check = cls._metadata_int(metadata, "last_check_time") or int(time.time())
        avatar_name = Path(payload["avatarPath"]).name if payload.get("avatarPath") else ""
        telethon_name = (
            Path(payload["telethonSession"]).name if payload.get("telethonSession") else ""
        )
        profile_json = folder / "profile.json"
        account_json = folder / "account.json"

        if not profile_json.exists():
            profile_payload = {
                "app_id": cls._metadata_int(metadata, "app_id", "apiId", "api_id") or 2040,
                "app_hash": cls._metadata_text(metadata, "app_hash", "apiHash", "api_hash")
                or "888888888888888888888",
                "device": cls._metadata_text(metadata, "device") or "B9TK_O-EXTREME",
                "sdk": cls._metadata_text(metadata, "sdk") or "Windows 10 x64",
                "app_version": cls._metadata_text(metadata, "app_version") or "6.9.3 x64",
                "system_lang_pack": cls._metadata_text(metadata, "system_lang_pack") or "en-US",
                "system_lang_code": cls._metadata_text(metadata, "system_lang_code") or "en-US",
                "lang_pack": cls._metadata_text(metadata, "lang_pack") or "tdesktop",
                "lang_code": cls._metadata_text(metadata, "lang_code") or "en",
                "twoFA": metadata.get("twoFA"),
                "role": cls._metadata_text(metadata, "role"),
                "id": int(payload["telegramUserId"]) if payload.get("telegramUserId") else None,
                "phone": payload.get("phone") or None,
                "username": payload.get("username") or None,
                "date_of_birth": metadata.get("date_of_birth"),
                "date_of_birth_integrity": metadata.get("date_of_birth_integrity"),
                "is_premium": bool(payload.get("isPremium", False)),
                "has_profile_pic": bool(avatar_name or cls._metadata_bool(metadata, "has_profile_pic")),
                "spamblock": metadata.get("spamblock"),
                "register_time": imported_at,
                "last_check_time": last_check,
                "avatar": avatar_name or None,
                "first_name": payload.get("firstName", ""),
                "last_name": payload.get("lastName", ""),
                "sex": metadata.get("sex"),
                "proxy": payload.get("proxy") or metadata.get("proxy"),
                "ipv6": cls._metadata_bool(metadata, "ipv6"),
                "session_file": telethon_name,
            }
            try:
                profile_json.write_text(
                    json.dumps(profile_payload, ensure_ascii=False, indent=2),
                    encoding="utf-8",
                )
            except OSError:
                pass

        if not account_json.exists():
            account_payload = {
                "accountId": payload["accountId"],
                "name": payload["name"],
                "phone": payload.get("phone", ""),
                "username": payload.get("username", ""),
                "firstName": payload.get("firstName", ""),
                "lastName": payload.get("lastName", ""),
                "telegramUserId": payload.get("telegramUserId", ""),
                "profileFolder": folder.name,
                "isPremium": bool(payload.get("isPremium", False)),
                "isBot": bool(payload.get("isBot", False)),
                "dcId": int(payload.get("dcId") or 0),
                "apiId": int(payload.get("apiId") or 0),
                "avatarFile": avatar_name,
                "telethonSessionFile": telethon_name,
                "pyrogramSessionFile": (
                    Path(payload["pyrogramSession"]).name
                    if payload.get("pyrogramSession")
                    else ""
                ),
                "profileJsonFile": "profile.json",
                "importedAt": imported_at,
                "autoDetected": True,
                "proxy": payload.get("proxy") or "",
            }
            try:
                account_json.write_text(
                    json.dumps(account_payload, ensure_ascii=False, indent=2),
                    encoding="utf-8",
                )
            except OSError:
                pass

    def add_imported_account(self, payload: dict[str, Any]) -> bool:
        account_id = str(payload.get("accountId") or "")
        if not account_id or self.index_of(account_id) >= 0:
            return False
        item = self._sanitize(
            {
                **payload,
                "accountId": account_id,
                "authorized": True,
                "clientPath": "",
            }
        )
        self.beginInsertRows(QModelIndex(), len(self._items), len(self._items))
        self._items.append(item)
        self.endInsertRows()
        self._save()
        self.countChanged.emit()
        return True

    def update_imported_account(self, account_id: str, payload: dict[str, Any]) -> bool:
        row = self.index_of(account_id)
        if row < 0:
            return False

        new_user_id = str(payload.get("telegramUserId") or "").strip()
        if new_user_id:
            for index, item in enumerate(self._items):
                if index == row:
                    continue
                if str(item.get("telegramUserId") or "").strip() == new_user_id:
                    return False

        current = self._items[row]
        merged = {
            **current,
            **payload,
            "accountId": account_id,
            "authorized": True,
            "clientPath": "",
            "notes": str(payload.get("notes") or current.get("notes") or ""),
            "color": str(payload.get("color") or current.get("color") or "#7657F6"),
            "favorite": bool(payload.get("favorite", current.get("favorite", False))),
        }
        if not str(merged.get("name") or "").strip():
            merged["name"] = current.get("name") or "Без имени"
        self._items[row] = self._sanitize(merged)
        idx = self.index(row)
        self.dataChanged.emit(idx, idx, list(self._roles.keys()))
        self._save()
        return True

    @Property(int, notify=countChanged)
    def count(self) -> int:
        return len(self._items)

    @Property(int, notify=runningCountChanged)
    def runningCount(self) -> int:
        return sum(bool(item["running"]) for item in self._items)

    @Slot(str, result="QVariantMap")
    def get(self, account_id: str) -> dict[str, Any]:
        item = self.item_by_id(account_id)
        return dict(item) if item else {}

    @Slot(str, str, str, str, str, str, str, str, result=str)
    def addAccount(
        self,
        name: str,
        phone: str,
        tdata_path: str,
        client_path: str,
        notes: str,
        color: str,
        favorite: str,
        proxy: str,
    ) -> str:
        account_id = str(uuid.uuid4())
        item = self._sanitize(
            {
                "accountId": account_id,
                "name": name.strip(),
                "phone": phone.strip(),
                "tdataPath": _normalized_path(tdata_path),
                "clientPath": _normalized_path(client_path),
                "notes": notes.strip(),
                "color": color,
                "favorite": favorite.lower() == "true",
                "proxy": _normalize_proxy(proxy),
            }
        )
        self.beginInsertRows(QModelIndex(), len(self._items), len(self._items))
        self._items.append(item)
        self.endInsertRows()
        self._save()
        self.countChanged.emit()
        return account_id

    @Slot(str, str, str, str, str, str, str, str, str, result=bool)
    def updateAccount(
        self,
        account_id: str,
        name: str,
        phone: str,
        tdata_path: str,
        client_path: str,
        notes: str,
        color: str,
        favorite: str,
        proxy: str,
    ) -> bool:
        row = self.index_of(account_id)
        if row < 0:
            return False
        self._items[row].update(
            {
                "name": name.strip() or "Без имени",
                "phone": phone.strip(),
                "tdataPath": _normalized_path(tdata_path),
                "clientPath": _normalized_path(client_path),
                "notes": notes.strip(),
                "color": color,
                "favorite": favorite.lower() == "true",
                "proxy": _normalize_proxy(proxy),
            }
        )
        idx = self.index(row)
        self.dataChanged.emit(idx, idx, list(self._roles.keys()))
        self._save()
        return True

    @Slot(str, result=bool)
    def removeAccount(self, account_id: str) -> bool:
        return self.deleteAccount(account_id, False)

    @Slot(str, bool, result=bool)
    def deleteAccount(self, account_id: str, delete_files: bool) -> bool:
        row = self.index_of(account_id)
        if row < 0:
            return False
        item = self._items[row]
        if item.get("running"):
            return False

        account_dir_text = str(item.get("accountDirectory") or "")
        account_dir = Path(account_dir_text) if account_dir_text else None
        managed_dir: Path | None = None
        if account_dir is not None:
            try:
                resolved_dir = account_dir.resolve()
                data_root = self._storage_path.parent.resolve()
                if resolved_dir.parent == data_root:
                    managed_dir = resolved_dir
            except (OSError, RuntimeError):
                managed_dir = None

        if delete_files:
            if managed_dir is None:
                return False
            try:
                if managed_dir.exists():
                    shutil.rmtree(managed_dir)
            except OSError:
                return False
        elif managed_dir is not None and managed_dir.is_dir():
            try:
                (managed_dir / IGNORED_PROFILE_MARKER).write_text(
                    "Профиль исключён из автосканирования TGA Manager.\n",
                    encoding="utf-8",
                )
            except OSError:
                return False

        self.beginRemoveRows(QModelIndex(), row, row)
        self._items.pop(row)
        self.endRemoveRows()
        self._save()
        self.countChanged.emit()
        self.runningCountChanged.emit()
        return True

    @Slot(str)
    def toggleFavorite(self, account_id: str) -> None:
        row = self.index_of(account_id)
        if row < 0:
            return
        self._items[row]["favorite"] = not self._items[row]["favorite"]
        idx = self.index(row)
        self.dataChanged.emit(idx, idx, [self.FavoriteRole])
        self._save()

    def set_running(self, account_id: str, running: bool) -> None:
        row = self.index_of(account_id)
        if row < 0 or self._items[row]["running"] == running:
            return
        self._items[row]["running"] = running
        idx = self.index(row)
        self.dataChanged.emit(idx, idx, [self.RunningRole])
        self.runningCountChanged.emit()

    def mark_launched(self, account_id: str) -> None:
        row = self.index_of(account_id)
        if row < 0:
            return
        self._items[row]["lastLaunched"] = _now_iso()
        idx = self.index(row)
        self.dataChanged.emit(idx, idx, [self.LastLaunchedRole])
        self._save()


class AccountFilterModel(QSortFilterProxyModel):
    searchTextChanged = Signal()
    favoritesOnlyChanged = Signal()
    countChanged = Signal()

    def __init__(self, parent: QObject | None = None) -> None:
        super().__init__(parent)
        self._search_text = ""
        self._favorites_only = False
        self.setDynamicSortFilter(True)
        self.setSortRole(AccountModel.FavoriteRole)
        self.sort(0, Qt.DescendingOrder)
        self.rowsInserted.connect(lambda *_: self.countChanged.emit())
        self.rowsRemoved.connect(lambda *_: self.countChanged.emit())
        self.modelReset.connect(self.countChanged.emit)
        self.layoutChanged.connect(lambda *_: self.countChanged.emit())

    @Property(int, notify=countChanged)
    def count(self) -> int:
        return self.rowCount()

    @Property(str, notify=searchTextChanged)
    def searchText(self) -> str:
        return self._search_text

    @Slot(str)
    def setSearchText(self, value: str) -> None:
        normalized = value.strip().casefold()
        if normalized == self._search_text:
            return
        self._search_text = normalized
        self.searchTextChanged.emit()
        self.invalidateFilter()

    @Property(bool, notify=favoritesOnlyChanged)
    def favoritesOnly(self) -> bool:
        return self._favorites_only

    @Slot(bool)
    def setFavoritesOnly(self, value: bool) -> None:
        if value == self._favorites_only:
            return
        self._favorites_only = value
        self.favoritesOnlyChanged.emit()
        self.invalidateFilter()

    def filterAcceptsRow(self, source_row: int, source_parent: QModelIndex) -> bool:
        model = self.sourceModel()
        if model is None:
            return False
        index = model.index(source_row, 0, source_parent)
        if self._favorites_only and not bool(model.data(index, AccountModel.FavoriteRole)):
            return False
        if not self._search_text:
            return True
        haystack = " ".join(
            str(model.data(index, role) or "")
            for role in (
                AccountModel.NameRole,
                AccountModel.PhoneRole,
                AccountModel.UsernameRole,
                AccountModel.NotesRole,
                AccountModel.ProxyRole,
            )
        ).casefold()
        return self._search_text in haystack


class RecentAccountModel(QSortFilterProxyModel):
    """Accounts ordered by their most recent successful Telegram launch."""

    def __init__(self, parent: QObject | None = None) -> None:
        super().__init__(parent)
        self.setDynamicSortFilter(True)
        self.setSortRole(AccountModel.LastLaunchedRole)
        self.sort(0, Qt.DescendingOrder)

    def lessThan(self, left: QModelIndex, right: QModelIndex) -> bool:
        model = self.sourceModel()
        if model is None:
            return super().lessThan(left, right)

        left_launched = str(model.data(left, AccountModel.LastLaunchedRole) or "")
        right_launched = str(model.data(right, AccountModel.LastLaunchedRole) or "")
        if left_launched != right_launched:
            return left_launched < right_launched

        # Keep accounts that have never been launched predictable: newest profile first.
        left_created = str(model.data(left, AccountModel.CreatedAtRole) or "")
        right_created = str(model.data(right, AccountModel.CreatedAtRole) or "")
        if left_created != right_created:
            return left_created < right_created
        return left.row() < right.row()


class AppBackend(QObject):
    toast = Signal(str, str)
    launchFinished = Signal(str, bool)
    dataDirectoryChanged = Signal()
    telegramStatusChanged = Signal()
    importProgress = Signal(int, str)
    importSucceeded = Signal(str)
    importFailed = Signal(str)
    importRunningChanged = Signal()
    manualLoginChanged = Signal()
    telegramDownloadChanged = Signal()
    telegramDownloadFinished = Signal(bool)
    uiLanguageChanged = Signal()

    def __init__(self, model: AccountModel, parent: QObject | None = None) -> None:
        super().__init__(parent)
        self._model = model
        saved_language = str(self._read_ui_settings().get("language") or "ru").casefold()
        self._ui_language = saved_language if saved_language in {"en", "ru", "uk"} else "ru"
        self._telegram_dir = _application_root() / "Telegram"
        self._telegram_dir.mkdir(parents=True, exist_ok=True)
        self._telegram_executable = self._telegram_dir / "Telegram.exe"
        self._network_manager = QNetworkAccessManager(self)
        self._telegram_release_reply: QNetworkReply | None = None
        self._telegram_download_reply: QNetworkReply | None = None
        self._telegram_download_file: Any = None
        self._telegram_download_archive = self._telegram_dir / ".telegram-portable-download.zip"
        self._telegram_download_running = False
        self._telegram_download_progress = 0
        self._telegram_download_status = ""
        self._telegram_download_version = ""
        self._telegram_download_write_error = ""
        self._pids: dict[str, int] = {}
        self._stopping: set[str] = set()
        self._process_timer = QTimer(self)
        self._process_timer.setInterval(2000)
        self._process_timer.timeout.connect(self._refresh_process_states)
        self._import_process: QProcess | None = None
        self._import_stdout = ""
        self._import_stderr = ""
        self._import_job_id = ""
        self._import_terminal_event = False
        self._import_successful = False
        self._import_update_account_id = ""
        self._manual_pid = 0
        self._manual_login_dir: Path | None = None
        self._manual_import_data: dict[str, Any] = {}
        self._pending_manual_cleanup: Path | None = None
        self._pending_archive_cleanup: Path | None = None
        self._data_archive_queue: list[Path] = []
        self._active_data_archive: Path | None = None
        self._data_archive_scan_timer = QTimer(self)
        self._data_archive_scan_timer.setSingleShot(True)
        self._data_archive_scan_timer.setInterval(1800)
        self._data_archive_scan_timer.timeout.connect(self._scan_data_archives_silently)
        self._data_watcher = QFileSystemWatcher(self)
        self._data_watcher.addPath(str(self._model.storage_path.parent))
        self._data_watcher.directoryChanged.connect(self._schedule_data_archive_scan)
        QTimer.singleShot(700, self._scan_data_archives_silently)

    @property
    def _ui_settings_path(self) -> Path:
        return self._model.storage_path.parent / "ui_settings.json"

    def _read_ui_settings(self) -> dict[str, Any]:
        path = self._ui_settings_path
        try:
            payload = json.loads(path.read_text(encoding="utf-8"))
        except (OSError, UnicodeDecodeError, json.JSONDecodeError):
            return {}
        return payload if isinstance(payload, dict) else {}

    def _write_ui_settings(self, payload: dict[str, Any]) -> bool:
        path = self._ui_settings_path
        try:
            temporary = path.with_suffix(".json.tmp")
            temporary.write_text(json.dumps(payload, ensure_ascii=False, indent=2), encoding="utf-8")
            os.replace(temporary, path)
            return True
        except OSError:
            return False

    def _effective_proxy(self, account_proxy: str = "") -> str:
        return _normalize_proxy(account_proxy) or self.defaultProxy()

    @Property(str, notify=uiLanguageChanged)
    def uiLanguage(self) -> str:
        return self._ui_language

    @Slot(str, result=bool)
    def setUiLanguage(self, language: str) -> bool:
        normalized = str(language or "").strip().casefold()
        if normalized not in {"en", "ru", "uk"}:
            return False
        if normalized == self._ui_language:
            return True

        payload = self._read_ui_settings()
        payload["language"] = normalized
        if not self._write_ui_settings(payload):
            return False
        self._ui_language = normalized
        self.uiLanguageChanged.emit()
        return True

    @Property(bool, notify=importRunningChanged)
    def importRunning(self) -> bool:
        return self._import_process is not None

    @Property(bool, notify=manualLoginChanged)
    def manualLoginRunning(self) -> bool:
        return self._manual_login_dir is not None

    @Slot(str, str, str, str, str, str, str, result=bool)
    def authorizeAccount(
        self,
        display_name: str,
        source_tdata: str,
        passcode: str,
        notes: str,
        color: str,
        favorite: str,
        proxy: str,
    ) -> bool:
        if self._import_process is not None:
            self.toast.emit("Импорт уже выполняется", "info")
            return False
        if not self._model._is_tdata_valid(source_tdata):
            self.importFailed.emit("Выберите корректную папку tdata")
            return False

        self._pending_manual_cleanup = None
        return self._start_import(
            display_name=display_name,
            source_tdata=source_tdata,
            passcode=passcode,
            notes=notes,
            color=color,
            favorite=favorite,
            proxy=proxy,
        )

    @Slot(str, result=bool)
    def importArchive(self, archive_url: str) -> bool:
        if self._import_process is not None:
            self.toast.emit("Импорт уже выполняется", "info")
            return False
        if self._manual_login_dir is not None:
            self.toast.emit("Сначала завершите или отмените ручной вход", "info")
            return False

        from PySide6.QtCore import QUrl

        raw = str(archive_url or "").strip()
        archive_path = Path(QUrl(raw).toLocalFile() if raw.casefold().startswith("file:") else raw)
        try:
            archive_path = archive_path.expanduser().resolve()
        except (OSError, RuntimeError):
            pass
        if not archive_path.is_file():
            self.toast.emit("Архив не найден", "error")
            return False

        if self._is_direct_data_archive(archive_path):
            self._remove_data_archive_from_queue(archive_path)
            self._active_data_archive = archive_path
            success = self._import_archive_as_profile(archive_path, show_success=True)
            self._finalize_data_archive_import(success)
            self._start_next_data_archive()
            return success

        return self._import_archive_as_profile(archive_path, show_success=True)

    def _extract_archive_profile(self, archive_path: Path) -> Path:
        extract_root = _profiles_root() / f".archive-import-{uuid.uuid4()}"
        target_dir: Path | None = None
        try:
            self.importProgress.emit(2, "Распаковка архива…")
            _extract_archive(archive_path, extract_root)
            tdata_path = _find_tdata_folder(extract_root)
            if tdata_path is None:
                raise RuntimeError("В архиве не найдена корректная папка tdata")

            target_dir = _next_profile_dir(_profiles_root())
            if tdata_path.name.casefold() == "tdata":
                shutil.copytree(
                    tdata_path.parent,
                    target_dir,
                    ignore=_ignore_archive_profile_noise,
                )
            else:
                target_dir.mkdir(parents=True, exist_ok=False)
                shutil.copytree(
                    tdata_path,
                    target_dir / "tdata",
                    ignore=_ignore_archive_profile_noise,
                )
            return target_dir
        except Exception:
            if target_dir is not None:
                shutil.rmtree(target_dir, ignore_errors=True)
            raise
        finally:
            shutil.rmtree(extract_root, ignore_errors=True)

    def _import_archive_as_profile(self, archive_path: Path, show_success: bool) -> bool:
        profile_dir: Path | None = None
        try:
            self.importProgress.emit(2, "Распаковка архива…")
            profile_dir = self._extract_archive_profile(archive_path)
            self.importProgress.emit(70, "Добавляем профиль без авторизации…")
            added = self._model.scan_data_profiles()
            if added <= 0:
                raise RuntimeError("Профиль распакован, но уже есть в списке или не распознан")
            self.importProgress.emit(100, "Профиль добавлен")
            if show_success:
                self.toast.emit(
                    f"Профиль {profile_dir.name} добавлен.\n"
                    "Авторизацию можно запустить вручную после настройки прокси.",
                    "success",
                )
            return True
        except Exception as exc:
            if profile_dir is not None:
                shutil.rmtree(profile_dir, ignore_errors=True)
            message = str(exc).strip() or "Не удалось распаковать архив"
            self.toast.emit(message, "error")
            self.importFailed.emit(message)
            return False
        finally:
            self.importProgress.emit(0, "")

    def _schedule_data_archive_scan(self, *_args: Any) -> None:
        self._data_archive_scan_timer.start()

    def _scan_data_archives_silently(self) -> None:
        self._queue_data_archives(show_empty=False)

    def _is_direct_data_archive(self, archive_path: Path) -> bool:
        try:
            return archive_path.resolve().parent == self._model.storage_path.parent.resolve()
        except (OSError, RuntimeError):
            return False

    def _remove_data_archive_from_queue(self, archive_path: Path) -> None:
        archive_key = _path_key(archive_path)
        self._data_archive_queue = [
            queued for queued in self._data_archive_queue if _path_key(queued) != archive_key
        ]

    def _queue_data_archives(self, show_empty: bool) -> int:
        data_root = self._model.storage_path.parent
        if not data_root.is_dir():
            return 0

        queued_keys = {_path_key(path) for path in self._data_archive_queue}
        if self._active_data_archive is not None:
            queued_keys.add(_path_key(self._active_data_archive))

        added = 0
        waiting_for_copy = False
        now = time.time()

        for archive_path in sorted(data_root.iterdir(), key=lambda value: value.name.casefold()):
            if not _is_supported_tdata_archive(archive_path):
                continue
            try:
                stat = archive_path.stat()
            except OSError:
                continue
            if now - stat.st_mtime < 2.0:
                waiting_for_copy = True
                continue

            archive_key = _path_key(archive_path)
            if archive_key in queued_keys:
                continue
            try:
                archive_path = archive_path.resolve()
            except (OSError, RuntimeError):
                pass
            self._data_archive_queue.append(archive_path)
            queued_keys.add(archive_key)
            added += 1

        if waiting_for_copy:
            self._schedule_data_archive_scan()
            if show_empty and not added:
                self.toast.emit("Архив в data ещё копируется, подожду немного…", "info")

        processed = self._start_next_data_archive()

        if processed:
            self.toast.emit(
                f"Добавлено профилей: {processed}.\n"
                "Авторизацию запускайте вручную после настройки прокси.",
                "success",
            )
        elif added:
            self.toast.emit(f"Найдено архивов в data: {added}. Поставлено в очередь.", "info")
        elif show_empty and (self._data_archive_queue or self._active_data_archive):
            self.toast.emit("Архивы из data уже ожидают обработки", "info")
        elif show_empty and not waiting_for_copy:
            self.toast.emit("Новых профилей или архивов в data не найдено", "info")

        return added + processed

    def _start_next_data_archive(self) -> int:
        if (
            self._import_process is not None
            or self._manual_login_dir is not None
            or self._active_data_archive is not None
        ):
            return 0

        processed = 0
        while self._data_archive_queue:
            archive_path = self._data_archive_queue.pop(0)
            if not archive_path.is_file():
                continue

            self._active_data_archive = archive_path
            self.toast.emit(f"Распаковываю архив из data: {archive_path.name}", "info")
            success = self._import_archive_as_profile(archive_path, show_success=False)
            if success:
                processed += 1
            self._finalize_data_archive_import(success)
        return processed

    def _finalize_data_archive_import(self, success: bool) -> None:
        archive_path = self._active_data_archive
        self._active_data_archive = None
        if archive_path is None or not archive_path.exists():
            return

        target_dir = self._model.storage_path.parent / (
            "_imported_archives" if success else "_failed_archives"
        )
        try:
            target_dir.mkdir(parents=True, exist_ok=True)
            target_path = _unique_child_path(target_dir, archive_path.name)
            shutil.move(str(archive_path), str(target_path))
        except OSError as exc:
            self.toast.emit(f"Не удалось перенести архив {archive_path.name}: {exc}", "error")

    @Slot(str, result=bool)
    def refreshAccount(self, account_id: str) -> bool:
        if self._import_process is not None:
            self.toast.emit("Дождитесь завершения текущего импорта", "info")
            return False
        account = self._model.item_by_id(account_id)
        if not account:
            self.toast.emit("Аккаунт не найден", "error")
            return False
        if account.get("running"):
            self.toast.emit("Сначала закройте Telegram для этого профиля", "info")
            return False
        if not self._model._is_tdata_valid(str(account.get("tdataPath") or "")):
            self.toast.emit("Не найдена корректная папка tdata", "error")
            return False

        profile_dir = Path(str(account.get("accountDirectory") or "")).expanduser()
        if not profile_dir.is_dir():
            profile_dir = self._workdir_for_tdata(str(account.get("tdataPath") or ""))
        if not profile_dir.is_dir():
            self.toast.emit("Папка профиля не найдена", "error")
            return False

        self.toast.emit("Обновляем данные аккаунта…", "info")
        return self._start_import(
            display_name=str(account.get("name") or ""),
            source_tdata=str(account.get("tdataPath") or ""),
            passcode="",
            notes=str(account.get("notes") or ""),
            color=str(account.get("color") or "#7657F6"),
            favorite="true" if bool(account.get("favorite", False)) else "false",
            proxy=str(account.get("proxy") or ""),
            mode="refresh",
            update_account_id=account_id,
            target_dir=str(profile_dir),
        )

    def _start_import(
        self,
        *,
        display_name: str,
        source_tdata: str,
        passcode: str,
        notes: str,
        color: str,
        favorite: str,
        proxy: str = "",
        mode: str = "import",
        update_account_id: str = "",
        target_dir: str = "",
    ) -> bool:
        if self._import_process is not None:
            self.toast.emit("Импорт уже выполняется", "info")
            return False

        account_proxy = _normalize_proxy(proxy)
        effective_proxy = self._effective_proxy(account_proxy)
        try:
            _parse_proxy(effective_proxy)
        except ValueError as exc:
            if effective_proxy:
                self.toast.emit(str(exc), "error")
                self.importFailed.emit(str(exc))
                return False

        self._import_job_id = str(uuid.uuid4())
        accounts_root = _profiles_root()
        request = {
            "job_id": self._import_job_id,
            "mode": mode,
            "display_name": display_name.strip(),
            "source_tdata": _normalized_path(source_tdata),
            "accounts_root": str(accounts_root),
            "existing_telegram_user_ids": self._model.telegram_user_ids(update_account_id),
            "target_dir": _normalized_path(target_dir) if target_dir else "",
            "passcode": passcode,
            "notes": notes.strip(),
            "color": color,
            "favorite": favorite.lower() == "true",
            "proxy": effective_proxy,
            "account_proxy": account_proxy,
        }

        process = QProcess(self)
        if getattr(sys, "frozen", False):
            process.setProgram(sys.executable)
            process.setArguments(["--session-import-worker"])
        else:
            process.setProgram(sys.executable)
            process.setArguments([str(_application_root() / "session_import_worker.py")])
        process.setWorkingDirectory(str(_application_root()))
        process.setProcessChannelMode(QProcess.SeparateChannels)
        process.started.connect(
            lambda payload=json.dumps(request, ensure_ascii=False): self._write_import_request(payload)
        )
        process.readyReadStandardOutput.connect(self._read_import_stdout)
        process.readyReadStandardError.connect(self._read_import_stderr)
        process.errorOccurred.connect(self._on_import_process_error)
        process.finished.connect(self._on_import_finished)

        self._import_stdout = ""
        self._import_stderr = ""
        self._import_terminal_event = False
        self._import_successful = False
        self._import_update_account_id = update_account_id if mode == "refresh" else ""
        self._import_process = process
        self.importRunningChanged.emit()
        self.importProgress.emit(3, "Запуск обновления…" if mode == "refresh" else "Запуск импорта…")
        process.start()
        return True

    @Slot(str, result=bool)
    def startManualLogin(self, proxy: str = "") -> bool:
        if self._import_process is not None:
            self.toast.emit("Дождитесь завершения импорта", "info")
            return False
        if self._manual_login_dir is not None:
            self.toast.emit("Ручной вход уже запущен", "info")
            return False
        if not self._telegram_executable.is_file():
            self.toast.emit("Поместите Telegram.exe в папку Telegram", "error")
            return False

        account_proxy = _normalize_proxy(proxy)
        effective_proxy = self._effective_proxy(account_proxy)
        try:
            telegram_proxy_url = _telegram_socks_url(effective_proxy)
        except ValueError as exc:
            if effective_proxy:
                self.toast.emit(str(exc), "error")
                return False
            telegram_proxy_url = ""

        job_id = str(uuid.uuid4())
        manual_dir = _profiles_root() / f".manual-login-{job_id}"
        if manual_dir.exists():
            shutil.rmtree(manual_dir, ignore_errors=True)
        manual_dir.mkdir(parents=True, exist_ok=True)

        arguments = ["-many", "-workdir", str(manual_dir)]
        if telegram_proxy_url:
            arguments.append(telegram_proxy_url)

        success, pid = QProcess.startDetached(
            str(self._telegram_executable),
            arguments,
            str(self._telegram_executable.parent),
        )
        if not success:
            shutil.rmtree(manual_dir, ignore_errors=True)
            self.toast.emit("Не удалось запустить Telegram", "error")
            return False

        self._manual_pid = int(pid)
        self._manual_login_dir = manual_dir
        self._manual_import_data = {"proxy": account_proxy}
        self.manualLoginChanged.emit()
        self.importProgress.emit(12, "Пройдите авторизацию в Telegram, затем нажмите «Завершить».")
        self.toast.emit("Telegram открыт для ручного входа", "success")
        return True

    @Slot(str, str, str, str, str, str, result=bool)
    def finishManualLogin(
        self,
        display_name: str,
        passcode: str,
        notes: str,
        color: str,
        favorite: str,
        proxy: str,
    ) -> bool:
        if self._manual_login_dir is None:
            self.toast.emit("Ручной вход не запущен", "info")
            return False
        if self._import_process is not None:
            self.toast.emit("Импорт уже выполняется", "info")
            return False

        self._manual_import_data = {
            "display_name": display_name,
            "passcode": passcode,
            "notes": notes,
            "color": color,
            "favorite": favorite,
            "proxy": _normalize_proxy(proxy),
        }
        self.importProgress.emit(25, "Закрываем Telegram и сохраняем tdata…")
        if self._manual_pid and self._pid_is_running(self._manual_pid):
            self._request_graceful_close(self._manual_pid)
        QTimer.singleShot(2600, self._finish_manual_login_after_close)
        return True

    @Slot()
    def cancelManualLogin(self) -> None:
        manual_dir = self._manual_login_dir
        pid = self._manual_pid
        self._manual_login_dir = None
        self._manual_pid = 0
        self._manual_import_data = {}
        self.manualLoginChanged.emit()
        if pid and self._pid_is_running(pid):
            self._request_graceful_close(pid)
            QTimer.singleShot(1800, lambda process_id=pid: self._force_pid_if_running(process_id))
            QTimer.singleShot(2300, lambda folder=manual_dir: self._remove_manual_dir(folder))
        else:
            self._remove_manual_dir(manual_dir)
        self.importProgress.emit(0, "")
        self.toast.emit("Ручной вход отменён", "info")
        self._start_next_data_archive()

    def _finish_manual_login_after_close(self) -> None:
        manual_dir = self._manual_login_dir
        if manual_dir is None:
            return

        if self._manual_pid and self._pid_is_running(self._manual_pid):
            self._force_pid_if_running(self._manual_pid)
            QTimer.singleShot(500, self._finish_manual_login_after_close)
            return

        self._manual_pid = 0
        self._manual_login_dir = None
        self.manualLoginChanged.emit()

        source_tdata = manual_dir / "tdata"
        if not self._model._is_tdata_valid(str(source_tdata)):
            self.importProgress.emit(0, "")
            self.importFailed.emit("Временная tdata не найдена. Убедитесь, что авторизация в Telegram была завершена.")
            self.toast.emit("Временная tdata не найдена", "error")
            if manual_dir.is_dir() and manual_dir.parent == _profiles_root():
                shutil.rmtree(manual_dir, ignore_errors=True)
            self._start_next_data_archive()
            return

        data = self._manual_import_data
        self._pending_manual_cleanup = manual_dir
        self.importProgress.emit(35, "Авторизация завершена. Импортируем tdata…")
        started = self._start_import(
            display_name=str(data.get("display_name") or ""),
            source_tdata=str(source_tdata),
            passcode=str(data.get("passcode") or ""),
            notes=str(data.get("notes") or ""),
            color=str(data.get("color") or "#7657F6"),
            favorite=str(data.get("favorite") or "false"),
            proxy=str(data.get("proxy") or ""),
        )
        self._manual_import_data = {}
        if not started:
            self._pending_manual_cleanup = None

    @staticmethod
    def _force_pid_if_running(pid: int) -> None:
        if pid <= 0 or not AppBackend._pid_is_running(pid):
            return
        if sys.platform == "win32":
            import ctypes

            process_terminate = 0x0001
            handle = ctypes.windll.kernel32.OpenProcess(process_terminate, False, pid)
            if handle:
                try:
                    ctypes.windll.kernel32.TerminateProcess(handle, 0)
                finally:
                    ctypes.windll.kernel32.CloseHandle(handle)
            return

        import signal

        try:
            os.kill(pid, signal.SIGKILL)
        except OSError:
            pass

    def _write_import_request(self, payload: str) -> None:
        if self._import_process is None:
            return
        self._import_process.write((payload + "\n").encode("utf-8"))
        self._import_process.closeWriteChannel()

    def _read_import_stdout(self) -> None:
        if self._import_process is None:
            return
        self._import_stdout += bytes(self._import_process.readAllStandardOutput()).decode(
            "utf-8", errors="replace"
        )
        while "\n" in self._import_stdout:
            line, self._import_stdout = self._import_stdout.split("\n", 1)
            self._handle_import_line(line.strip())

    def _read_import_stderr(self) -> None:
        if self._import_process is None:
            return
        self._import_stderr += bytes(self._import_process.readAllStandardError()).decode(
            "utf-8", errors="replace"
        )

    def _handle_import_line(self, line: str) -> None:
        if not line:
            return
        try:
            event = json.loads(line)
        except json.JSONDecodeError:
            return
        event_type = event.get("event")
        if event_type == "progress":
            self.importProgress.emit(int(event.get("value", 0)), str(event.get("message", "")))
        elif event_type == "complete":
            result = event.get("result")
            if not isinstance(result, dict):
                self._report_import_error("Импорт вернул некорректные данные")
                return
            if self._import_update_account_id:
                if not self._model.update_imported_account(self._import_update_account_id, result):
                    self._report_import_error("Не удалось обновить данные аккаунта")
                    return
                self._import_terminal_event = True
                self._import_successful = True
                self.importProgress.emit(100, "Данные аккаунта обновлены")
                self.toast.emit("Данные аккаунта обновлены", "success")
                return
            if not self._model.add_imported_account(result):
                self._report_import_error("Не удалось добавить импортированный аккаунт")
                return
            self._import_terminal_event = True
            self._import_successful = True
            self.importProgress.emit(100, "Аккаунт импортирован")
            self.importSucceeded.emit(str(result["accountId"]))
        elif event_type == "error":
            self._report_import_error(str(event.get("message") or "Ошибка импорта"))

    def _report_import_error(self, message: str) -> None:
        if self._import_terminal_event:
            return
        self._import_terminal_event = True
        detailed_message = message
        if self._pending_manual_cleanup is not None and self._pending_manual_cleanup.exists():
            detailed_message = (
                f"{message}\nРучная tdata сохранена во временной папке: "
                f"{self._pending_manual_cleanup}"
            )
        self.importFailed.emit(detailed_message)
        self.toast.emit(message, "error")

    def _on_import_process_error(self, _error: QProcess.ProcessError) -> None:
        if self._import_process is not None:
            self._report_import_error(
                f"Не удалось запустить импорт: {self._import_process.errorString()}"
            )

    def _on_import_finished(self, exit_code: int, _status: QProcess.ExitStatus) -> None:
        if self._import_stdout.strip():
            self._handle_import_line(self._import_stdout.strip())
        if exit_code != 0 and not self._import_terminal_event:
            detail = self._import_stderr.strip().splitlines()
            message = detail[-1] if detail else "Процесс импорта завершился с ошибкой"
            self._report_import_error(message)
        process = self._import_process
        self._import_process = None
        self.importRunningChanged.emit()
        if process is not None:
            process.deleteLater()
        self._cleanup_import_staging()
        self._cleanup_pending_archive_import()
        self._finalize_data_archive_import(self._import_successful)
        if self._import_successful:
            self._cleanup_pending_manual_login()
        self._start_next_data_archive()

    def _cleanup_import_staging(self) -> None:
        if not self._import_job_id:
            return
        profiles_root = _profiles_root()
        staging = profiles_root / f".import-{self._import_job_id}"
        if staging.is_dir() and staging.parent == profiles_root:
            shutil.rmtree(staging, ignore_errors=True)
        self._import_job_id = ""
        self._import_update_account_id = ""

    def _cleanup_pending_manual_login(self) -> None:
        manual_dir = self._pending_manual_cleanup
        self._pending_manual_cleanup = None
        self._remove_manual_dir(manual_dir)

    def _cleanup_pending_archive_import(self) -> None:
        archive_dir = self._pending_archive_cleanup
        self._pending_archive_cleanup = None
        profiles_root = _profiles_root()
        if archive_dir and archive_dir.is_dir() and archive_dir.parent == profiles_root:
            shutil.rmtree(archive_dir, ignore_errors=True)

    @staticmethod
    def _remove_manual_dir(manual_dir: Path | None) -> None:
        if manual_dir and manual_dir.is_dir() and manual_dir.parent == _profiles_root():
            shutil.rmtree(manual_dir, ignore_errors=True)

    @Slot(result=str)
    def defaultClient(self) -> str:
        return str(self._telegram_executable)

    @Property(bool, notify=telegramStatusChanged)
    def telegramReady(self) -> bool:
        return self._telegram_executable.is_file()

    @Property(bool, notify=telegramDownloadChanged)
    def telegramDownloadRunning(self) -> bool:
        return self._telegram_download_running

    @Property(int, notify=telegramDownloadChanged)
    def telegramDownloadProgress(self) -> int:
        return self._telegram_download_progress

    @Property(str, notify=telegramDownloadChanged)
    def telegramDownloadStatus(self) -> str:
        return self._telegram_download_status

    @Property(str, notify=telegramDownloadChanged)
    def telegramDownloadVersion(self) -> str:
        return self._telegram_download_version

    @Slot()
    def refreshTelegramStatus(self) -> None:
        self.telegramStatusChanged.emit()

    def _set_telegram_download_state(
        self,
        *,
        running: bool | None = None,
        progress: int | None = None,
        status: str | None = None,
        version: str | None = None,
    ) -> None:
        if running is not None:
            self._telegram_download_running = running
        if progress is not None:
            self._telegram_download_progress = max(0, min(100, progress))
        if status is not None:
            self._telegram_download_status = status
        if version is not None:
            self._telegram_download_version = version
        self.telegramDownloadChanged.emit()

    @Slot()
    def openTelegramReleases(self) -> None:
        QDesktopServices.openUrl(
            QUrl("https://github.com/telegramdesktop/tdesktop/releases/latest")
        )

    @Slot(result=bool)
    def downloadLatestTelegram(self) -> bool:
        if self._telegram_download_running:
            self.toast.emit("Загрузка Telegram уже выполняется", "info")
            return False
        if self.telegramReady:
            self.toast.emit("Telegram.exe уже найден", "info")
            return False

        self._telegram_download_write_error = ""
        self._set_telegram_download_state(
            running=True,
            progress=0,
            status="Проверяем последний стабильный релиз…",
            version="",
        )

        request = QNetworkRequest(
            QUrl("https://api.github.com/repos/telegramdesktop/tdesktop/releases/latest")
        )
        request.setRawHeader(b"User-Agent", b"TGA-Manager")
        request.setRawHeader(b"Accept", b"application/vnd.github+json")
        self._telegram_release_reply = self._network_manager.get(request)
        self._telegram_release_reply.finished.connect(self._on_telegram_release_received)
        return True

    def _on_telegram_release_received(self) -> None:
        reply = self._telegram_release_reply
        self._telegram_release_reply = None
        if reply is None:
            return

        try:
            if reply.error() != QNetworkReply.NetworkError.NoError:
                self._finish_telegram_download(False, f"GitHub: {reply.errorString()}")
                return

            try:
                payload = json.loads(bytes(reply.readAll()).decode("utf-8"))
            except (UnicodeDecodeError, json.JSONDecodeError):
                self._finish_telegram_download(False, "GitHub вернул некорректные данные релиза")
                return

            assets = payload.get("assets", []) if isinstance(payload, dict) else []
            portable_asset: dict[str, Any] | None = None
            for asset in assets if isinstance(assets, list) else []:
                if not isinstance(asset, dict):
                    continue
                name = str(asset.get("name") or "").casefold()
                if name.startswith("tportable-x64.") and name.endswith(".zip"):
                    portable_asset = asset
                    break

            if portable_asset is None:
                self._finish_telegram_download(
                    False,
                    "В последнем релизе не найден portable ZIP для Windows x64",
                )
                return

            download_url = str(portable_asset.get("browser_download_url") or "")
            if not download_url.startswith(
                "https://github.com/telegramdesktop/tdesktop/releases/download/"
            ):
                self._finish_telegram_download(False, "GitHub вернул неожиданный адрес файла")
                return

            version = str(payload.get("tag_name") or "").lstrip("v")
            self._set_telegram_download_state(
                progress=0,
                status=f"Подготовка Telegram Desktop {version or 'x64'}…",
                version=version,
            )
            self._start_telegram_archive_download(download_url)
        finally:
            reply.deleteLater()

    def _start_telegram_archive_download(self, download_url: str) -> None:
        try:
            self._telegram_dir.mkdir(parents=True, exist_ok=True)
            self._telegram_download_archive.unlink(missing_ok=True)
            self._telegram_download_file = self._telegram_download_archive.open("wb")
        except OSError as exc:
            self._finish_telegram_download(False, f"Не удалось создать файл: {exc}")
            return

        request = QNetworkRequest(QUrl(download_url))
        request.setRawHeader(b"User-Agent", b"TGA-Manager")
        self._telegram_download_reply = self._network_manager.get(request)
        self._telegram_download_reply.readyRead.connect(self._on_telegram_download_ready_read)
        self._telegram_download_reply.downloadProgress.connect(
            self._on_telegram_download_progress
        )
        self._telegram_download_reply.finished.connect(self._on_telegram_archive_received)

    def _on_telegram_download_ready_read(self) -> None:
        reply = self._telegram_download_reply
        output = self._telegram_download_file
        if reply is None or output is None:
            return
        try:
            output.write(bytes(reply.readAll()))
        except OSError as exc:
            self._telegram_download_write_error = str(exc)
            reply.abort()

    def _on_telegram_download_progress(self, received: int, total: int) -> None:
        if total > 0:
            progress = int(received * 100 / total)
            status = (
                f"Скачивание: {progress}%  ·  "
                f"{received / 1048576:.1f} / {total / 1048576:.1f} МБ"
            )
        else:
            progress = 0
            status = f"Скачивание: {received / 1048576:.1f} МБ"
        self._set_telegram_download_state(progress=progress, status=status)

    def _on_telegram_archive_received(self) -> None:
        reply = self._telegram_download_reply
        if reply is None:
            return

        self._on_telegram_download_ready_read()
        self._telegram_download_reply = None
        if self._telegram_download_file is not None:
            try:
                self._telegram_download_file.close()
            except OSError:
                pass
            self._telegram_download_file = None

        try:
            if self._telegram_download_write_error:
                self._finish_telegram_download(
                    False,
                    f"Ошибка записи: {self._telegram_download_write_error}",
                )
                return
            if reply.error() != QNetworkReply.NetworkError.NoError:
                self._finish_telegram_download(False, f"Загрузка: {reply.errorString()}")
                return

            self._set_telegram_download_state(progress=100, status="Распаковка Telegram…")
            self._install_telegram_archive_file(self._telegram_download_archive)
            version = self._telegram_download_version
            message = f"Telegram Desktop {version} установлен" if version else "Telegram Desktop установлен"
            self._finish_telegram_download(True, message)
        except (OSError, ValueError, zipfile.BadZipFile) as exc:
            self._finish_telegram_download(False, f"Не удалось установить Telegram: {exc}")
        finally:
            reply.deleteLater()

    def _install_telegram_archive_file(self, archive_path: Path) -> None:
        if not archive_path.is_file() or not zipfile.is_zipfile(archive_path):
            raise ValueError("выбранный файл не является ZIP-архивом")

        staging = self._telegram_dir / f".telegram-install-{uuid.uuid4().hex}"
        try:
            _safe_extract_zip(archive_path, staging)
            executables = sorted(
                (
                    path
                    for path in staging.rglob("*")
                    if path.is_file() and path.name.casefold() == "telegram.exe"
                ),
                key=lambda path: len(path.parts),
            )
            if not executables:
                raise ValueError("в архиве не найден Telegram.exe")

            source_root = executables[0].parent
            for source in source_root.iterdir():
                target = self._telegram_dir / source.name
                if source.is_dir():
                    shutil.copytree(source, target, dirs_exist_ok=True)
                else:
                    shutil.copy2(source, target)

            if not self._telegram_executable.is_file():
                raise ValueError("Telegram.exe не появился после распаковки")
        finally:
            shutil.rmtree(staging, ignore_errors=True)

    @Slot(str, result=bool)
    def installTelegramArchive(self, archive_path: str) -> bool:
        if self._telegram_download_running:
            self.toast.emit("Дождитесь завершения текущей загрузки", "info")
            return False

        selected = Path(_normalized_path(archive_path))
        self._set_telegram_download_state(
            running=True,
            progress=100,
            status="Распаковка выбранного архива…",
            version="",
        )
        try:
            self._install_telegram_archive_file(selected)
            self._finish_telegram_download(True, "Telegram Desktop установлен")
            return True
        except (OSError, ValueError, zipfile.BadZipFile) as exc:
            self._finish_telegram_download(False, f"Не удалось установить Telegram: {exc}")
            return False

    def _finish_telegram_download(self, success: bool, message: str) -> None:
        if self._telegram_download_file is not None:
            try:
                self._telegram_download_file.close()
            except OSError:
                pass
            self._telegram_download_file = None
        self._telegram_download_archive.unlink(missing_ok=True)

        self._set_telegram_download_state(
            running=False,
            progress=100 if success else 0,
            status=message,
        )
        self.telegramStatusChanged.emit()
        self.telegramDownloadFinished.emit(success)
        self.toast.emit(message, "success" if success else "error")

    @Slot(result=str)
    def telegramDirectory(self) -> str:
        return str(self._telegram_dir)

    @Slot(result=str)
    def dataDirectory(self) -> str:
        return str(self._model.storage_path.parent)

    @Slot(result=str)
    def defaultProxy(self) -> str:
        payload = self._read_ui_settings()
        return _normalize_proxy(str(payload.get("proxy") or ""))

    @Slot(str, result=bool)
    def saveDefaultProxy(self, proxy: str) -> bool:
        proxy_text = _normalize_proxy(proxy)
        try:
            _parse_proxy(proxy_text)
        except ValueError as exc:
            if proxy_text:
                self.toast.emit(str(exc), "error")
                return False

        payload = self._read_ui_settings()
        payload["proxy"] = proxy_text
        if not self._write_ui_settings(payload):
            self.toast.emit("Не удалось сохранить прокси", "error")
            return False
        self.toast.emit("Прокси сохранён" if proxy_text else "Прокси очищен", "success")
        return True

    @Slot(str, result=bool)
    def validateProxy(self, proxy: str) -> bool:
        proxy_text = _normalize_proxy(proxy)
        if not proxy_text:
            return True
        try:
            _parse_proxy(proxy_text)
            return True
        except ValueError:
            return False

    @Slot(result="QVariantMap")
    def windowGeometry(self) -> dict[str, int]:
        default = {"width": 1040, "height": 895, "x": -1, "y": -1}
        payload = self._read_ui_settings()
        if not isinstance(payload, dict):
            return default
        window = payload.get("window", payload)
        if not isinstance(window, dict):
            return default

        result = default.copy()
        for key in ("width", "height", "x", "y"):
            try:
                result[key] = int(window.get(key, result[key]))
            except (TypeError, ValueError):
                pass
        return result

    @Slot(int, int, int, int)
    def saveWindowGeometry(self, width: int, height: int, x: int, y: int) -> None:
        payload = self._read_ui_settings()

        payload["window"] = {
            "width": max(1040, int(width)),
            "height": max(680, int(height)),
            "x": int(x),
            "y": int(y),
        }
        self._write_ui_settings(payload)

    @Slot(result=int)
    def scanDataProfiles(self) -> int:
        count = self._model.scan_data_profiles()
        archive_count = self._queue_data_archives(show_empty=not bool(count))
        if count:
            self.toast.emit(f"Найдено и добавлено профилей: {count}", "success")
        return count + archive_count

    @Slot(str, result=bool)
    def validateTdata(self, path: str) -> bool:
        return self._model._is_tdata_valid(path)

    @staticmethod
    def _workdir_for_tdata(path: str) -> Path:
        selected = Path(path)
        return selected.parent if selected.name.lower() == "tdata" else selected

    @Slot(str)
    def launchAccount(self, account_id: str) -> None:
        account = self._model.item_by_id(account_id)
        if not account:
            self.toast.emit("Аккаунт не найден", "error")
            return

        tdata_path = account["tdataPath"]
        if not self._model._is_tdata_valid(tdata_path):
            self.toast.emit("Не найдена корректная папка tdata", "error")
            self.launchFinished.emit(account_id, False)
            return

        executable = str(self._telegram_executable)
        if not self._telegram_executable.is_file():
            self.toast.emit("Поместите Telegram.exe в папку Telegram", "error")
            self.launchFinished.emit(account_id, False)
            return

        running_pid = self._pids.get(account_id)
        if running_pid and self._pid_is_running(running_pid):
            self.toast.emit("Этот аккаунт уже запущен", "info")
            return

        proxy_text = self._effective_proxy(str(account.get("proxy") or ""))
        try:
            telegram_proxy_url = _telegram_socks_url(proxy_text)
        except ValueError as exc:
            if proxy_text:
                self.toast.emit(str(exc), "error")
                self.launchFinished.emit(account_id, False)
                return
            telegram_proxy_url = ""

        arguments = ["-many", "-workdir", str(self._workdir_for_tdata(tdata_path))]
        if telegram_proxy_url:
            arguments.append(telegram_proxy_url)

        success, pid = QProcess.startDetached(
            executable,
            arguments,
            str(Path(executable).parent),
        )
        if success:
            self._pids[account_id] = int(pid)
            self._model.set_running(account_id, True)
            self._model.mark_launched(account_id)
            if not self._process_timer.isActive():
                self._process_timer.start()
            self.toast.emit("Telegram запущен", "success")
            self.launchFinished.emit(account_id, True)
        else:
            self._model.set_running(account_id, False)
            self.toast.emit("Не удалось запустить Telegram", "error")
            self.launchFinished.emit(account_id, False)

    @staticmethod
    def _pid_is_running(pid: int) -> bool:
        if pid <= 0:
            return False
        if sys.platform == "win32":
            import ctypes

            synchronize = 0x00100000
            wait_timeout = 0x00000102
            handle = ctypes.windll.kernel32.OpenProcess(synchronize, False, pid)
            if not handle:
                return False
            try:
                return ctypes.windll.kernel32.WaitForSingleObject(handle, 0) == wait_timeout
            finally:
                ctypes.windll.kernel32.CloseHandle(handle)
        try:
            os.kill(pid, 0)
        except (OSError, PermissionError):
            return False
        return True

    def _refresh_process_states(self) -> None:
        finished = [
            account_id
            for account_id, pid in self._pids.items()
            if not self._pid_is_running(pid)
        ]
        for account_id in finished:
            self._pids.pop(account_id, None)
            self._model.set_running(account_id, False)
            if account_id in self._stopping:
                self._stopping.discard(account_id)
                self.toast.emit("Telegram закрыт", "success")
        if not self._pids:
            self._process_timer.stop()

    @Slot(str)
    def stopAccount(self, account_id: str) -> None:
        if account_id in self._stopping:
            self.toast.emit("Telegram уже закрывается", "info")
            return
        pid = self._pids.get(account_id)
        if not pid or not self._pid_is_running(pid):
            self._pids.pop(account_id, None)
            self._model.set_running(account_id, False)
            self.toast.emit("Активный процесс не найден", "info")
            return

        self._stopping.add(account_id)
        self.toast.emit("Закрываем Telegram…", "info")
        self._request_graceful_close(pid)
        QTimer.singleShot(2200, lambda aid=account_id, process_id=pid: self._force_stop_if_needed(aid, process_id))

    @staticmethod
    def _request_graceful_close(pid: int) -> None:
        if sys.platform == "win32":
            import ctypes

            windows: list[int] = []
            enum_callback = ctypes.WINFUNCTYPE(ctypes.c_bool, ctypes.c_void_p, ctypes.c_void_p)

            @enum_callback
            def collect_window(hwnd: int, _lparam: int) -> bool:
                process_id = ctypes.c_ulong()
                ctypes.windll.user32.GetWindowThreadProcessId(hwnd, ctypes.byref(process_id))
                if process_id.value == pid:
                    windows.append(hwnd)
                return True

            ctypes.windll.user32.EnumWindows(collect_window, 0)
            for hwnd in windows:
                ctypes.windll.user32.PostMessageW(hwnd, 0x0010, 0, 0)  # WM_CLOSE
            return

        import signal

        try:
            os.kill(pid, signal.SIGTERM)
        except OSError:
            pass

    def _force_stop_if_needed(self, account_id: str, pid: int) -> None:
        if self._pids.get(account_id) != pid:
            return
        if not self._pid_is_running(pid):
            self._refresh_process_states()
            return

        if sys.platform == "win32":
            import ctypes

            process_terminate = 0x0001
            handle = ctypes.windll.kernel32.OpenProcess(process_terminate, False, pid)
            if handle:
                try:
                    ctypes.windll.kernel32.TerminateProcess(handle, 0)
                finally:
                    ctypes.windll.kernel32.CloseHandle(handle)
        else:
            import signal

            try:
                os.kill(pid, signal.SIGKILL)
            except OSError:
                pass
        QTimer.singleShot(300, self._refresh_process_states)

    @Slot(str)
    def openProfileFolder(self, account_id: str) -> None:
        account = self._model.item_by_id(account_id)
        if not account:
            return
        path = Path(str(account.get("accountDirectory") or ""))
        if not path.exists():
            path = self._workdir_for_tdata(str(account.get("tdataPath") or ""))
        if not path.exists():
            self.toast.emit("Папка профиля не найдена", "error")
            return
        self._open_path(path)

    @Slot(str)
    def openTdataFolder(self, account_id: str) -> None:
        self.openProfileFolder(account_id)

    @Slot(str, result="QVariantMap")
    def accountDetails(self, account_id: str) -> dict[str, Any]:
        account = self._model.item_by_id(account_id)
        if not account:
            return {}

        folder = Path(str(account.get("accountDirectory") or ""))
        if not folder.is_dir():
            folder = self._workdir_for_tdata(str(account.get("tdataPath") or ""))

        metadata: dict[str, Any] = {}
        if folder.is_dir():
            metadata, _ = AccountModel._read_external_metadata(folder)
            metadata = metadata or {}

        telethon_info = self._read_sqlite_session_info(
            Path(str(account.get("telethonSession") or ""))
        )
        pyrogram_info = self._read_sqlite_session_info(
            Path(str(account.get("pyrogramSession") or ""))
        )
        session_info = telethon_info if telethon_info.get("authKeyHex") else pyrogram_info

        api_id = (
            int(account.get("apiId") or 0)
            or AccountModel._metadata_int(metadata, "app_id", "apiId", "api_id")
            or int(session_info.get("apiId") or 0)
        )
        api_hash = AccountModel._metadata_text(metadata, "app_hash", "apiHash", "api_hash")

        first_name = str(account.get("firstName") or "")
        last_name = str(account.get("lastName") or "")
        display_name = str(account.get("name") or "").strip() or _clean_name(first_name, last_name)
        avatar_path = str(account.get("avatarPath") or "")

        return {
            "accountId": str(account.get("accountId") or ""),
            "name": display_name,
            "firstName": first_name,
            "lastName": last_name,
            "username": str(account.get("username") or ""),
            "phone": str(account.get("phone") or ""),
            "notes": str(account.get("notes") or ""),
            "telegramUserId": str(account.get("telegramUserId") or ""),
            "dcId": int(account.get("dcId") or session_info.get("dcId") or 0),
            "isPremium": bool(account.get("isPremium", False)),
            "avatarPath": avatar_path,
            "avatarUrl": self.pathToUrl(avatar_path) if avatar_path else "",
            "apiId": api_id,
            "apiHash": api_hash,
            "authKeyHex": str(session_info.get("authKeyHex") or ""),
            "authKeySource": str(session_info.get("source") or ""),
            "telethonSession": str(account.get("telethonSession") or ""),
            "pyrogramSession": str(account.get("pyrogramSession") or ""),
            "profileFolder": str(folder) if folder else "",
            "profileJsonPath": str(account.get("profileJsonPath") or ""),
            "proxy": str(account.get("proxy") or ""),
            "effectiveProxy": self._effective_proxy(str(account.get("proxy") or "")),
        }

    @staticmethod
    def _read_sqlite_session_info(path: Path) -> dict[str, Any]:
        if not path.is_file():
            return {}
        try:
            connection = sqlite3.connect(str(path))
            connection.row_factory = sqlite3.Row
            try:
                columns = {
                    row["name"]
                    for row in connection.execute("PRAGMA table_info(sessions)").fetchall()
                }
                if "auth_key" not in columns:
                    return {}
                select_parts = ["auth_key"]
                for column in ("dc_id", "api_id", "user_id"):
                    if column in columns:
                        select_parts.append(column)
                row = connection.execute(
                    f"SELECT {', '.join(select_parts)} FROM sessions LIMIT 1"
                ).fetchone()
                if row is None:
                    return {}
                auth_key = row["auth_key"]
                if isinstance(auth_key, memoryview):
                    auth_key = auth_key.tobytes()
                if not isinstance(auth_key, (bytes, bytearray)):
                    return {}
                return {
                    "authKeyHex": bytes(auth_key).hex(),
                    "dcId": int(row["dc_id"]) if "dc_id" in row.keys() and row["dc_id"] else 0,
                    "apiId": int(row["api_id"]) if "api_id" in row.keys() and row["api_id"] else 0,
                    "userId": str(row["user_id"]) if "user_id" in row.keys() and row["user_id"] else "",
                    "source": path.name,
                }
            finally:
                connection.close()
        except (OSError, sqlite3.Error, ValueError):
            return {}

    @Slot(str, result=bool)
    def copyToClipboard(self, value: str) -> bool:
        try:
            from PySide6.QtGui import QGuiApplication

            clipboard = QGuiApplication.clipboard()
            if clipboard is None:
                return False
            clipboard.setText(str(value or ""))
            self.toast.emit("Скопировано", "success")
            return True
        except Exception:
            self.toast.emit("Не удалось скопировать", "error")
            return False

    @Slot()
    def openDataDirectory(self) -> None:
        self._open_path(self._model.storage_path.parent)

    @Slot()
    def openTelegramDirectory(self) -> None:
        self._telegram_dir.mkdir(parents=True, exist_ok=True)
        self._open_path(self._telegram_dir)

    @staticmethod
    def _open_path(path: Path) -> None:
        if sys.platform == "win32":
            os.startfile(str(path))  # type: ignore[attr-defined]
        elif sys.platform == "darwin":
            subprocess.Popen(["open", str(path)])
        else:
            subprocess.Popen(["xdg-open", str(path)])

    @Slot(str, result=str)
    def pathFromUrl(self, url: str) -> str:
        from PySide6.QtCore import QUrl

        return QUrl(url).toLocalFile()

    @Slot(str, result=str)
    def pathToUrl(self, path: str) -> str:
        from PySide6.QtCore import QUrl

        if not path:
            return ""
        return QUrl.fromLocalFile(str(Path(path))).toString()

    @Slot(str, str, result=bool)
    def copyTdata(self, source: str, destination_parent: str) -> bool:
        source_path = Path(_normalized_path(source))
        if source_path.name.lower() != "tdata":
            source_path = source_path / "tdata"
        if not self._model._is_tdata_valid(str(source_path)):
            self.toast.emit("Источник не содержит корректную tdata", "error")
            return False
        target = Path(_normalized_path(destination_parent)) / "tdata"
        if target.exists():
            self.toast.emit("В выбранной папке уже есть tdata", "error")
            return False
        try:
            shutil.copytree(source_path, target)
        except OSError as exc:
            self.toast.emit(f"Ошибка копирования: {exc}", "error")
            return False
        self.toast.emit("tdata скопирована", "success")
        return True
