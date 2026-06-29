from __future__ import annotations

import sys
from pathlib import Path

from PySide6.QtCore import QCoreApplication, QUrl
from PySide6.QtGui import QGuiApplication, QIcon
from PySide6.QtQml import QQmlApplicationEngine
from PySide6.QtQuickControls2 import QQuickStyle

from backend import AccountFilterModel, AccountModel, AppBackend, RecentAccountModel


def main() -> int:
    base_dir = Path(__file__).resolve().parent
    if sys.platform == "win32":
        try:
            import ctypes

            ctypes.windll.shell32.SetCurrentProcessExplicitAppUserModelID(
                "TGA.Tools.TGAManager"
            )
        except (AttributeError, OSError):
            pass

    QCoreApplication.setOrganizationName("TGA Tools")
    QCoreApplication.setApplicationName("TGA Manager")

    QQuickStyle.setStyle("Basic")
    app = QGuiApplication(sys.argv)
    app.setApplicationDisplayName("TGA Manager")

    windows_icon = base_dir / "assets" / "app-icon.ico"
    icon_path = windows_icon if windows_icon.exists() else base_dir / "assets" / "app-icon.svg"
    app_icon = QIcon()
    if icon_path.exists():
        app_icon = QIcon(str(icon_path))
        app.setWindowIcon(app_icon)

    account_model = AccountModel()
    account_proxy = AccountFilterModel()
    account_proxy.setSourceModel(account_model)
    recent_account_proxy = RecentAccountModel()
    recent_account_proxy.setSourceModel(account_model)
    backend = AppBackend(account_model)

    engine = QQmlApplicationEngine()
    engine.rootContext().setContextProperty("accountModel", account_model)
    engine.rootContext().setContextProperty("accountProxy", account_proxy)
    engine.rootContext().setContextProperty("recentAccountProxy", recent_account_proxy)
    engine.rootContext().setContextProperty("backend", backend)

    qml_file = base_dir / "qml" / "Main.qml"
    engine.load(QUrl.fromLocalFile(str(qml_file)))
    if not engine.rootObjects():
        return 1
    if not app_icon.isNull():
        engine.rootObjects()[0].setIcon(app_icon)

    return app.exec()


if __name__ == "__main__":
    if "--session-import-worker" in sys.argv:
        from session_import_worker import main as import_worker_main

        raise SystemExit(import_worker_main())
    raise SystemExit(main())
