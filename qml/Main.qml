import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Dialogs
import Qt5Compat.GraphicalEffects
import "components"

ApplicationWindow {
    id: window
    width: 1040
    height: 895
    minimumWidth: 1040
    minimumHeight: 680
    visible: true
    title: "TGA Manager"
    color: "#121116"

    property int currentPage: 0
    property string editingId: ""
    property string editingPhone: ""
    property string pendingDeleteId: ""
    property string selectedColor: "#7657F6"
    property var profileColors: [
        "#7657F6", "#8B62D9", "#A855F7", "#D946EF",
        "#3C8DFF", "#38BDF8", "#16A085",
        "#22C55E", "#84CC16", "#F0B55A", "#E38B43",
        "#F97316", "#EF4444", "#D95C7A"
    ]
    property int importProgressValue: 0
    property string importProgressMessage: ""
    property var accountInfo: ({})
    property bool showApiHash: false
    property bool showAuthKey: false
    property bool geometryRestored: false
    property url appLogoSource: Qt.resolvedUrl("../assets/app-icon.svg")
    property string uiLanguage: backend.uiLanguage

    function l(ru, en, uk) {
        return uiLanguage === "en" ? en : uiLanguage === "uk" ? uk : ru
    }

    Timer {
        id: windowGeometrySaveTimer
        interval: 350
        repeat: false
        onTriggered: window.saveWindowGeometry()
    }

    Component.onCompleted: {
        const geometry = backend.windowGeometry()
        if (geometry.width)
            width = Math.max(minimumWidth, Number(geometry.width))
        if (geometry.height)
            height = Math.max(minimumHeight, Number(geometry.height))
        if (geometry.x >= 0)
            x = Number(geometry.x)
        if (geometry.y >= 0)
            y = Number(geometry.y)
        geometryRestored = true
    }

    onWidthChanged: if (geometryRestored) windowGeometrySaveTimer.restart()
    onHeightChanged: if (geometryRestored) windowGeometrySaveTimer.restart()
    onXChanged: if (geometryRestored) windowGeometrySaveTimer.restart()
    onYChanged: if (geometryRestored) windowGeometrySaveTimer.restart()
    onClosing: saveWindowGeometry()

    function saveWindowGeometry() {
        if (!geometryRestored)
            return
        backend.saveWindowGeometry(Math.max(minimumWidth, Math.round(width)),
                                   Math.max(minimumHeight, Math.round(height)),
                                   Math.round(x),
                                   Math.round(y))
    }

    function masked(value, length) {
        if (!value || !String(value).length)
            return "—"
        let result = ""
        const count = length || Math.min(String(value).length, 32)
        for (let i = 0; i < count; ++i)
            result += "•"
        return result
    }

    function infoValue(key, fallback) {
        if (!accountInfo || accountInfo[key] === undefined || accountInfo[key] === null || String(accountInfo[key]).length === 0)
            return fallback || "—"
        return String(accountInfo[key])
    }

    function copyInfo(value) {
        if (value !== undefined && value !== null && String(value).length)
            backend.copyToClipboard(String(value))
    }

    function openAccountInfo(accountId) {
        accountInfo = backend.accountDetails(accountId)
        showApiHash = false
        showAuthKey = false
        accountInfoDialog.open()
    }

    function openAccountEditor(accountId) {
        editingId = accountId || ""
        editorError.text = ""
        importProgressValue = 0
        importProgressMessage = ""
        if (editingId.length === 0) {
            nameField.text = ""
            editingPhone = ""
            tdataField.text = ""
            proxyField.text = ""
            notesField.text = ""
            favoriteCheck.checked = false
            selectedColor = profileColors[0]
        } else {
            const data = accountModel.get(editingId)
            nameField.text = data.name || ""
            editingPhone = data.phone || ""
            tdataField.text = data.tdataPath || ""
            proxyField.text = data.proxy || ""
            notesField.text = data.notes || ""
            favoriteCheck.checked = data.favorite || false
            selectedColor = data.color || profileColors[0]
        }
        accountDialog.open()
    }

    function authorizeAndImport() {
        editorError.text = ""
        if (!tdataField.text.trim().length) {
            editorError.text = window.l("Выберите папку tdata", "Select a tdata folder", "Виберіть папку tdata")
            return
        }
        importProgressValue = 1
        importProgressMessage = window.l("Подготовка…", "Preparing…", "Підготовка…")
        backend.authorizeAccount(nameField.text, tdataField.text, "",
                                 notesField.text, selectedColor,
                                 String(favoriteCheck.checked), proxyField.text)
    }

    function startManualLogin() {
        editorError.text = ""
        importProgressValue = 8
        importProgressMessage = window.l("Открываем Telegram для ручного входа…", "Opening Telegram for manual sign-in…", "Відкриваємо Telegram для ручного входу…")
        if (!backend.startManualLogin(proxyField.text)) {
            importProgressValue = 0
            importProgressMessage = ""
        }
    }

    function finishManualLogin() {
        editorError.text = ""
        importProgressValue = 25
        importProgressMessage = window.l("Закрываем Telegram и сохраняем tdata…", "Closing Telegram and saving tdata…", "Закриваємо Telegram і зберігаємо tdata…")
        if (!backend.finishManualLogin(nameField.text, "", notesField.text,
                                       selectedColor, String(favoriteCheck.checked),
                                       proxyField.text)) {
            importProgressValue = 0
            importProgressMessage = ""
        }
    }

    function closeAccountDialog() {
        if (backend.manualLoginRunning)
            backend.cancelManualLogin()
        accountDialog.close()
    }

    function saveAccount() {
        if (!nameField.text.trim().length) {
            editorError.text = window.l("Укажите название аккаунта", "Enter an account name", "Вкажіть назву акаунта")
            nameField.forceActiveFocus()
            return
        }
        if (!tdataField.text.trim().length) {
            editorError.text = window.l("Выберите папку tdata или её родительскую папку", "Select the tdata folder or its parent folder", "Виберіть папку tdata або її батьківську папку")
            return
        }
        if (!backend.validateProxy(proxyField.text)) {
            editorError.text = window.l("Формат прокси: login:password@ip:port", "Proxy format: login:password@ip:port", "Формат проксі: login:password@ip:port")
            proxyField.forceActiveFocus()
            return
        }
        if (editingId.length === 0) {
            accountModel.addAccount(nameField.text, editingPhone, tdataField.text,
                                    "", notesField.text, selectedColor,
                                    String(favoriteCheck.checked), proxyField.text)
            showToast(window.l("Аккаунт добавлен", "Account added", "Акаунт додано"), "success")
        } else {
            accountModel.updateAccount(editingId, nameField.text, editingPhone,
                                       tdataField.text, "", notesField.text,
                                       selectedColor, String(favoriteCheck.checked),
                                       proxyField.text)
            showToast(window.l("Изменения сохранены", "Changes saved", "Зміни збережено"), "success")
        }
        accountDialog.close()
    }

    function showToast(message, type) {
        const normalizedType = type || "info"
        toastBox.toastType = normalizedType
        toastBox.toastTitle = normalizedType === "error"
                              ? window.l("Ошибка", "Error", "Помилка")
                              : normalizedType === "success"
                                ? window.l("Готово", "Done", "Готово")
                                : window.l("Информация", "Information", "Інформація")
        toastMessage.text = String(message || "")
        toastBox.shown = true
        toastTimer.interval = Math.max(3600, Math.min(7600, 2600 + toastMessage.text.length * 24))
        toastTimer.restart()
        toastLifeAnimation.restart()
    }

    function hideToast() {
        toastTimer.stop()
        toastLifeAnimation.stop()
        toastBox.shown = false
    }

    Connections {
        target: backend
        function onToast(message, type) { window.showToast(message, type) }
        function onImportProgress(value, message) {
            window.importProgressValue = value
            window.importProgressMessage = message
        }
        function onImportSucceeded(accountId) {
            accountDialog.close()
            window.currentPage = 1
            window.showToast(window.l("Аккаунт авторизован и импортирован", "Account authorized and imported", "Акаунт авторизовано та імпортовано"), "success")
        }
        function onImportFailed(message) {
            editorError.text = message
            window.importProgressMessage = ""
        }
        function onTelegramDownloadFinished(success) {
            if (success)
                telegramDownloadDialog.close()
        }
    }

    Rectangle {
        id: sidebar
        width: 232
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        anchors.left: parent.left
        color: "#17161D"
        border.width: 0

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 18
            spacing: 0

            RowLayout {
                Layout.fillWidth: true
                Layout.leftMargin: 5
                Layout.topMargin: 4
                Layout.bottomMargin: 30
                spacing: 11
                Rectangle {
                    width: 38; height: 38; radius: 12
                    color: "#17161D"
                    border.width: 1
                    border.color: "#2B2A34"
                    Image {
                        id: sidebarLogo
                        anchors.fill: parent
                        source: window.appLogoSource
                        fillMode: Image.PreserveAspectFit
                        smooth: true
                        mipmap: true
                        visible: status === Image.Ready
                    }
                    Item {
                        anchors.fill: parent
                        visible: sidebarLogo.status !== Image.Ready

                        Rectangle {
                            width: 24
                            height: 6
                            radius: 2
                            x: 7
                            y: 9
                            gradient: Gradient {
                                GradientStop { position: 0; color: "#9A82FF" }
                                GradientStop { position: 1; color: "#6545EB" }
                            }
                        }
                        Rectangle {
                            width: 7
                            height: 20
                            radius: 2
                            x: 15.5
                            y: 14
                            gradient: Gradient {
                                GradientStop { position: 0; color: "#9A82FF" }
                                GradientStop { position: 1; color: "#6545EB" }
                            }
                        }
                        Rectangle {
                            width: 10
                            height: 10
                            radius: 5
                            x: 25
                            y: 25
                            color: "#56D6A8"
                            border.width: 2
                            border.color: "#17161D"
                        }
                    }
                }
                ColumnLayout {
                    spacing: 0
                    Text { text: "TGA Manager"; color: "#F3F2F7"; font.pixelSize: 16; font.weight: Font.Bold }
                    Text { text: "SESSION CONTROL"; color: "#656370"; font.pixelSize: 8; font.letterSpacing: 1.3 }
                }
            }

            Text {
                text: window.l("РАБОЧЕЕ ПРОСТРАНСТВО", "WORKSPACE", "РОБОЧИЙ ПРОСТІР")
                color: "#5F5D69"
                font.pixelSize: 9
                font.weight: Font.DemiBold
                font.letterSpacing: 1.2
                Layout.leftMargin: 14
                Layout.bottomMargin: 8
            }
            NavButton {
                text: window.l("Обзор", "Overview", "Огляд"); symbol: "\uE80F"; selected: window.currentPage === 0
                onClicked: window.currentPage = 0
            }
            NavButton {
                text: window.l("Аккаунты", "Accounts", "Акаунти"); symbol: "\uE716"; selected: window.currentPage === 1
                onClicked: window.currentPage = 1
            }
            NavButton {
                text: window.l("Настройки", "Settings", "Налаштування"); symbol: "\uE713"; selected: window.currentPage === 2
                onClicked: window.currentPage = 2
            }

            Item { Layout.fillHeight: true }

            LanguageSelector {
                Layout.alignment: Qt.AlignHCenter
                Layout.bottomMargin: 3
                currentLanguage: window.uiLanguage
                onLanguageSelected: language => backend.setUiLanguage(language)
            }
        }
        Rectangle { width: 1; anchors.right: parent.right; anchors.top: parent.top; anchors.bottom: parent.bottom; color: "#24232B" }
    }

    Rectangle {
        id: topbar
        anchors.left: sidebar.right
        anchors.right: parent.right
        anchors.top: parent.top
        height: 76
        color: "#121116"

        Item {
            anchors.fill: parent
            anchors.leftMargin: 30
            anchors.rightMargin: 30

            ColumnLayout {
                anchors.left: parent.left
                anchors.right: topbarActions.visible ? topbarActions.left : parent.right
                anchors.rightMargin: 24
                anchors.verticalCenter: parent.verticalCenter
                spacing: 2
                Text {
                    Layout.fillWidth: true
                    text: window.currentPage === 0
                          ? window.l("Добро пожаловать", "Welcome", "Ласкаво просимо")
                          : window.currentPage === 1
                            ? window.l("Аккаунты", "Accounts", "Акаунти")
                            : window.l("Настройки", "Settings", "Налаштування")
                    color: "#F4F3F8"
                    font.pixelSize: 20
                    font.weight: Font.Bold
                    elide: Text.ElideRight
                }
                Text {
                    Layout.fillWidth: true
                    text: window.currentPage === 0
                          ? window.l("Управляйте Telegram-сессиями в одном месте", "Manage Telegram sessions in one place", "Керуйте Telegram-сесіями в одному місці")
                          : window.currentPage === 1
                            ? window.l("Ваши локальные TDATA-сессии", "Your local TDATA sessions", "Ваші локальні TDATA-сесії")
                            : window.l("Параметры приложения и Telegram Desktop", "Application and Telegram Desktop settings", "Параметри програми та Telegram Desktop")
                    color: "#777582"
                    font.pixelSize: 11
                    elide: Text.ElideRight
                }
            }

            RowLayout {
                id: topbarActions
                visible: window.currentPage === 1
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                spacing: 16

                TextField {
                    id: searchField
                    Layout.preferredWidth: 255
                    implicitHeight: 42
                    placeholderText: window.l("Поиск аккаунта...", "Search account...", "Пошук акаунта...")
                    color: "#E7E5ED"
                    placeholderTextColor: "#666470"
                    leftPadding: 38
                    onTextChanged: accountProxy.setSearchText(text)
                    onActiveFocusChanged: if (activeFocus && window.currentPage !== 1) window.currentPage = 1
                    background: Rectangle { radius: 12; color: "#1B1A21"; border.width: 1; border.color: searchField.activeFocus ? "#5D4AA0" : "#2B2A33" }
                    Text { text: "\uE721"; color: "#777582"; font.family: "Segoe MDL2 Assets"; font.pixelSize: 15; anchors.left: parent.left; anchors.leftMargin: 14; anchors.verticalCenter: parent.verticalCenter }
                }
                AppButton {
                    text: window.l("Добавить", "Add", "Додати")
                    leadingText: "+"
                    onClicked: window.openAccountEditor("")
                }
            }
        }
        Rectangle { height: 1; anchors.left: parent.left; anchors.right: parent.right; anchors.bottom: parent.bottom; color: "#24232B" }
    }

    StackLayout {
        id: pages
        anchors.left: sidebar.right
        anchors.right: parent.right
        anchors.top: topbar.bottom
        anchors.bottom: parent.bottom
        currentIndex: window.currentPage

        Item {
            ColumnLayout {
                anchors.fill: parent
                anchors.margins: 30
                spacing: 22

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 16
                        StatCard { Layout.fillWidth: true; title: window.l("Всего аккаунтов", "Total accounts", "Усього акаунтів"); value: String(accountModel.count); subtitle: window.l("Локальные сессии", "Local sessions", "Локальні сесії"); accent: "#8B72FF"; symbol: "◉" }
                        StatCard { Layout.fillWidth: true; title: window.l("Сейчас запущено", "Running now", "Зараз запущено"); value: String(accountModel.runningCount); subtitle: accountModel.runningCount ? window.l("Telegram активен", "Telegram is active", "Telegram активний") : window.l("Нет активных процессов", "No active processes", "Немає активних процесів"); accent: "#56D6A8"; symbol: "▶" }
                    }

                    Rectangle {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        Layout.minimumHeight: 300
                        radius: 18
                        color: "#1C1B23"
                        border.width: 1
                        border.color: "#2B2A34"

                        ColumnLayout {
                            anchors.fill: parent
                            anchors.margins: 20
                            spacing: 12
                            RowLayout {
                                Layout.fillWidth: true
                                Text { text: window.l("Недавние аккаунты", "Recent accounts", "Нещодавні акаунти"); color: "#F0EFF4"; font.pixelSize: 15; font.weight: Font.DemiBold }
                                Item { Layout.fillWidth: true }
                                Button {
                                    id: allAccountsButton
                                    text: window.l("Все аккаунты →", "All accounts →", "Усі акаунти →")
                                    implicitHeight: 32
                                    hoverEnabled: true
                                    onClicked: window.currentPage = 1
                                    contentItem: Text {
                                        text: allAccountsButton.text
                                        color: allAccountsButton.hovered ? "#B6A5FF" : "#9B87F8"
                                        font.pixelSize: 15
                                        font.weight: Font.DemiBold
                                        horizontalAlignment: Text.AlignHCenter
                                        verticalAlignment: Text.AlignVCenter
                                        Behavior on color { ColorAnimation { duration: 120 } }
                                    }
                                    background: Item {}
                                }
                            }
                            Rectangle { Layout.fillWidth: true; height: 1; color: "#292831" }
                            Item {
                                Layout.fillWidth: true
                                Layout.fillHeight: true
                                Text {
                                    anchors.centerIn: parent
                                    visible: accountModel.count === 0
                                    text: window.l("Пока пусто\nДобавьте первую TDATA-сессию", "Nothing here yet\nAdd your first TDATA session", "Поки порожньо\nДодайте першу TDATA-сесію")
                                    color: "#696773"; font.pixelSize: 12
                                    horizontalAlignment: Text.AlignHCenter; lineHeight: 1.4
                                }
                                ListView {
                                    anchors.fill: parent
                                    visible: accountModel.count > 0
                                    model: recentAccountProxy
                                    spacing: 8
                                    clip: true
                                    reuseItems: false
                                    delegate: Rectangle {
                                        required property string accountId
                                        required property string name
                                        required property string phone
                                        required property string username
                                        required property string telegramUserId
                                        required property string profileColor
                                        required property string initials
                                        required property string avatarPath
                                        required property bool running
                                        required property bool pathValid
                                        required property bool authorized
                                        required property bool isPremium
                                        required property int dcId
                                        required property string lastLaunched
                                        width: ListView.view.width
                                        height: 82
                                        radius: 14
                                        color: recentCardHover.hovered ? "#211F29" : "#18171E"
                                        border.width: 1
                                        border.color: recentCardHover.hovered ? "#3A3748" : "#2B2A34"

                                        Rectangle {
                                            width: 4
                                            height: parent.height * 0.64
                                            radius: 2
                                            color: profileColor
                                            opacity: 0.95
                                            anchors.right: parent.right
                                            anchors.verticalCenter: parent.verticalCenter
                                        }

                                        RowLayout {
                                            anchors.fill: parent
                                            anchors.leftMargin: 12
                                            anchors.rightMargin: 10
                                            spacing: 12

                                            Rectangle {
                                                width: 52
                                                height: 52
                                                radius: 17
                                                color: profileColor
                                                border.width: 2
                                                border.color: profileColor

                                                Rectangle {
                                                    id: recentAvatarMask
                                                    anchors.fill: recentAvatarContent
                                                    radius: 14
                                                    visible: false
                                                }

                                                Item {
                                                    id: recentAvatarContent
                                                    anchors.fill: parent
                                                    anchors.margins: 3
                                                    layer.enabled: true
                                                    layer.effect: OpacityMask { maskSource: recentAvatarMask }

                                                    Rectangle { anchors.fill: parent; color: profileColor }
                                                    Image {
                                                        id: recentAvatar
                                                        anchors.fill: parent
                                                        source: avatarPath.length ? backend.pathToUrl(avatarPath) : ""
                                                        visible: avatarPath.length > 0 && status !== Image.Error
                                                        fillMode: Image.PreserveAspectCrop
                                                        asynchronous: true
                                                        cache: false
                                                    }
                                                    Text {
                                                        anchors.centerIn: parent
                                                        visible: !recentAvatar.visible
                                                        text: initials
                                                        color: "white"
                                                        font.pixelSize: 15
                                                        font.weight: Font.Bold
                                                    }
                                                }
                                            }
                                            ColumnLayout {
                                                Layout.fillWidth: true
                                                spacing: 3
                                                Text {
                                                    Layout.fillWidth: true
                                                    text: name
                                                    color: "#F3F2F7"
                                                    font.pixelSize: 15
                                                    font.weight: Font.DemiBold
                                                    elide: Text.ElideRight
                                                }
                                                Text {
                                                    Layout.fillWidth: true
                                                    text: username.length
                                                          ? "@" + username + (phone.length ? "  ·  +" + phone.replace(/^\+/, "") : "")
                                                          : phone.length ? "+" + phone.replace(/^\+/, "") : window.l("Телефон не указан", "Phone not specified", "Телефон не вказано")
                                                    color: "#777582"
                                                    font.pixelSize: 12
                                                    elide: Text.ElideRight
                                                }
                                                Text {
                                                    Layout.fillWidth: true
                                                    text: authorized ? "ID " + telegramUserId + (dcId ? "  ·  DC " + dcId : "") : lastLaunched.length ? window.l("Был запущен ранее", "Previously launched", "Запускався раніше") : window.l("Ещё не запускался", "Never launched", "Ще не запускався")
                                                    color: "#5F5D69"
                                                    font.pixelSize: 10
                                                    elide: Text.ElideRight
                                                }
                                            }
                                            Rectangle {
                                                visible: running || !authorized
                                                implicitWidth: recentStatusContent.implicitWidth + 28
                                                Layout.preferredWidth: visible ? implicitWidth : 0
                                                Layout.minimumWidth: visible ? implicitWidth : 0
                                                Layout.preferredHeight: 28
                                                radius: 9
                                                color: running || authorized ? "#17352C" : pathValid ? "#24232C" : "#3A252A"
                                                RowLayout {
                                                    id: recentStatusContent
                                                    anchors.centerIn: parent
                                                    spacing: 5
                                                    Text {
                                                        text: running ? "●" : authorized ? "✓" : pathValid ? "●" : "!"
                                                        color: running || authorized ? "#63D6A5" : pathValid ? "#9B99A7" : "#FF8D95"
                                                        font.pixelSize: 11
                                                        font.weight: Font.Bold
                                                    }
                                                    Text {
                                                        id: recentStatusText
                                                        text: running ? window.l("Запущен", "Running", "Запущено") : authorized ? window.l("Авторизован", "Authorized", "Авторизовано") : pathValid ? window.l("Готов", "Ready", "Готово") : window.l("Проверьте tdata", "Check tdata", "Перевірте tdata")
                                                        color: running || authorized ? "#63D6A5" : pathValid ? "#9B99A7" : "#FF8D95"
                                                        font.pixelSize: 11
                                                        font.weight: Font.DemiBold
                                                    }
                                                }
                                            }
                                            Rectangle {
                                                visible: isPremium
                                                implicitWidth: recentPremiumText.implicitWidth + 16
                                                Layout.preferredWidth: visible ? implicitWidth : 0
                                                Layout.minimumWidth: visible ? implicitWidth : 0
                                                Layout.preferredHeight: 28
                                                radius: 9
                                                color: "#302649"
                                                Text {
                                                    id: recentPremiumText
                                                    anchors.centerIn: parent
                                                    text: "★ Premium"
                                                    color: "#BDAEFF"
                                                    font.pixelSize: 10
                                                    font.weight: Font.DemiBold
                                                }
                                            }
                                            Button {
                                                id: recentLaunchButton
                                                implicitWidth: 112
                                                implicitHeight: 40
                                                hoverEnabled: true
                                                text: running ? window.l("Закрыть", "Stop", "Закрити") : window.l("Запустить", "Launch", "Запустити")
                                                onClicked: running ? backend.stopAccount(accountId) : backend.launchAccount(accountId)
                                                contentItem: Text {
                                                    text: recentLaunchButton.text
                                                    color: "white"
                                                    font.pixelSize: 13
                                                    font.weight: Font.DemiBold
                                                    horizontalAlignment: Text.AlignHCenter
                                                    verticalAlignment: Text.AlignVCenter
                                                }
                                                background: Rectangle {
                                                    radius: 12
                                                    color: running
                                                           ? (recentLaunchButton.hovered ? "#B94C5B" : "#9E3F4D")
                                                           : (recentLaunchButton.hovered ? "#866AFF" : "#7657F6")
                                                    Behavior on color { ColorAnimation { duration: 120 } }
                                                }
                                            }
                                            Repeater {
                                                model: [
                                                    { icon: "\uE72C", tip: window.l("Обновить данные и .session", "Refresh data and .session", "Оновити дані та .session") },
                                                    { icon: "\uE838", tip: window.l("Открыть папку профиля", "Open profile folder", "Відкрити папку профілю") },
                                                    { icon: "\uE946", tip: window.l("Информация об аккаунте", "Account information", "Інформація про акаунт") }
                                                ]

                                                ToolButton {
                                                    id: recentActionButton
                                                    implicitWidth: 40
                                                    implicitHeight: 40
                                                    hoverEnabled: true
                                                    enabled: index !== 0 || (!running && !backend.importRunning && pathValid)
                                                    ToolTip.visible: hovered
                                                    ToolTip.text: index === 0 && running ? window.l("Сначала закройте Telegram", "Close Telegram first", "Спочатку закрийте Telegram") : modelData.tip
                                                    onClicked: {
                                                        if (index === 0) backend.refreshAccount(accountId)
                                                        else if (index === 1) backend.openProfileFolder(accountId)
                                                        else window.openAccountInfo(accountId)
                                                    }

                                                    contentItem: Text {
                                                        text: modelData.icon
                                                        color: recentActionButton.enabled
                                                               ? recentActionButton.hovered ? "#D9D2FF" : "#BDB8D0"
                                                               : "#55535F"
                                                        font.family: "Segoe MDL2 Assets"
                                                        font.pixelSize: 15
                                                        horizontalAlignment: Text.AlignHCenter
                                                        verticalAlignment: Text.AlignVCenter
                                                    }

                                                    background: Rectangle {
                                                        radius: 12
                                                        color: recentActionButton.enabled
                                                               ? recentActionButton.hovered ? "#353143" : "#26252E"
                                                               : "#22212A"
                                                        border.width: 1
                                                        border.color: recentActionButton.enabled
                                                                      ? recentActionButton.hovered ? "#655A86" : "#33313B"
                                                                      : "#2B2933"
                                                        Behavior on color { ColorAnimation { duration: 120 } }
                                                        Behavior on border.color { ColorAnimation { duration: 120 } }
                                                    }
                                                }
                                            }
                                        }
                                        HoverHandler { id: recentCardHover }
                                    }
                                }
                            }
                        }
                    }
                }
        }

        Item {
            ColumnLayout {
                anchors.fill: parent
                anchors.margins: 30
                spacing: 18

                RowLayout {
                    Layout.fillWidth: true
                    Text { text: accountProxy.count + " " + window.l("профилей", "profiles", "профілів"); color: "#8B8996"; font.pixelSize: 12 }
                    Item { Layout.fillWidth: true }
                    AppCheckBox {
                        id: favoritesFilter
                        text: window.l("Только избранные", "Favorites only", "Лише вибрані")
                        onToggled: accountProxy.setFavoritesOnly(checked)
                    }
                }

                Item {
                    Layout.fillWidth: true
                    Layout.fillHeight: true

                    Column {
                        anchors.centerIn: parent
                        spacing: 14
                        visible: accountProxy.count === 0
                        Rectangle { width: 68; height: 68; radius: 22; color: "#211F2B"; anchors.horizontalCenter: parent.horizontalCenter; Text { anchors.centerIn: parent; text: searchField.text.length || favoritesFilter.checked ? "⌕" : "+"; color: "#8D78ED"; font.pixelSize: 30 } }
                        Text { anchors.horizontalCenter: parent.horizontalCenter; text: searchField.text.length || favoritesFilter.checked ? window.l("Ничего не найдено", "Nothing found", "Нічого не знайдено") : window.l("Добавьте первый аккаунт", "Add your first account", "Додайте перший акаунт"); color: "#E0DEE7"; font.pixelSize: 17; font.weight: Font.DemiBold }
                        Text { anchors.horizontalCenter: parent.horizontalCenter; text: searchField.text.length || favoritesFilter.checked ? window.l("Измените условия поиска", "Change the search filters", "Змініть умови пошуку") : window.l("Укажите путь к локальной папке tdata", "Select a local tdata folder", "Вкажіть шлях до локальної папки tdata"); color: "#777582"; font.pixelSize: 12 }
                        AppButton { visible: !searchField.text.length && !favoritesFilter.checked; anchors.horizontalCenter: parent.horizontalCenter; text: window.l("Добавить аккаунт", "Add account", "Додати акаунт"); leadingText: "+"; onClicked: window.openAccountEditor("") }
                    }

                    GridView {
                        id: accountGrid
                        anchors.fill: parent
                        visible: accountProxy.count > 0
                        clip: true
                        model: accountProxy
                        cellWidth: width >= 1120 ? width / 3 : width / 2
                        cellHeight: 240
                        reuseItems: false
                        boundsBehavior: Flickable.StopAtBounds
                        maximumFlickVelocity: 5200
                        flickDeceleration: 6200

                        WheelHandler {
                            target: null
                            onWheel: function(event) {
                                const rawDelta = event.pixelDelta.y !== 0
                                               ? event.pixelDelta.y * 2.0
                                               : (event.angleDelta.y / 120) * 190
                                const maximumY = Math.max(0, accountGrid.contentHeight - accountGrid.height)
                                accountGrid.contentY = Math.max(0, Math.min(maximumY, accountGrid.contentY - rawDelta))
                                event.accepted = true
                            }
                        }

                        delegate: Item {
                            required property string accountId
                            required property string name
                            required property string phone
                            required property string username
                            required property string telegramUserId
                            required property int dcId
                            required property string initials
                            required property string avatarPath
                            required property string profileColor
                            required property bool favorite
                            required property bool running
                            required property bool pathValid
                            required property bool authorized
                            required property bool isPremium
                            required property string lastLaunched
                            id: accountDelegate
                            width: accountGrid.cellWidth
                            height: accountGrid.cellHeight

                            AccountCard {
                                objectName: "accountCard"
                                anchors.left: parent.left
                                anchors.right: parent.right
                                anchors.rightMargin: 14
                                accountId: accountDelegate.accountId
                                accountName: accountDelegate.name
                                phone: accountDelegate.phone
                                username: accountDelegate.username
                                telegramUserId: accountDelegate.telegramUserId
                                dcId: accountDelegate.dcId
                                initials: accountDelegate.initials
                                avatarSource: accountDelegate.avatarPath.length ? backend.pathToUrl(accountDelegate.avatarPath) : ""
                                accentColor: accountDelegate.profileColor
                                language: window.uiLanguage
                                favorite: accountDelegate.favorite
                                running: accountDelegate.running
                                pathValid: accountDelegate.pathValid
                                authorized: accountDelegate.authorized
                                premium: accountDelegate.isPremium
                                busy: backend.importRunning
                                lastLaunched: accountDelegate.lastLaunched
                                onLaunchRequested: aid => backend.launchAccount(aid)
                                onStopRequested: aid => backend.stopAccount(aid)
                                onRefreshRequested: aid => backend.refreshAccount(aid)
                                onInfoRequested: aid => window.openAccountInfo(aid)
                                onEditRequested: aid => window.openAccountEditor(aid)
                                onFavoriteRequested: aid => accountModel.toggleFavorite(aid)
                                onFolderRequested: aid => backend.openProfileFolder(aid)
                                onDeleteRequested: (aid, title) => {
                                    window.pendingDeleteId = aid
                                    deleteDialog.accountName = title
                                    deleteDialog.open()
                                }
                            }
                        }
                        ScrollBar.vertical: ScrollBar {}
                    }
                }
            }
        }

        Item {
            ScrollView {
                id: settingsScroll
                anchors.fill: parent
                contentWidth: availableWidth
                clip: true
                ScrollBar.horizontal.policy: ScrollBar.AlwaysOff

                ColumnLayout {
                    width: Math.min(settingsScroll.availableWidth - 48, 940)
                    x: Math.max(24, (settingsScroll.availableWidth - width) / 2)
                    y: 24
                    spacing: 16

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 3
                        Text { text: window.l("Локальная среда", "Local environment", "Локальне середовище"); color: "#F2F0F6"; font.pixelSize: 16; font.weight: Font.DemiBold }
                        Text { text: window.l("Клиент Telegram и профили хранятся рядом с приложением.", "Telegram client and profiles are stored next to the application.", "Клієнт Telegram і профілі зберігаються поруч із програмою."); color: "#777582"; font.pixelSize: 11 }
                    }

                    GridLayout {
                        Layout.fillWidth: true
                        columns: width >= 700 ? 2 : 1
                        columnSpacing: 14
                        rowSpacing: 14

                        Rectangle {
                            Layout.fillWidth: true
                            Layout.preferredHeight: 176
                            radius: 16
                            color: "#1B1A22"
                            border.width: 1
                            border.color: backend.telegramDownloadRunning ? "#4A3D68" : backend.telegramReady ? "#29463C" : "#42362E"

                            Rectangle {
                                anchors.left: parent.left
                                anchors.top: parent.top
                                anchors.bottom: parent.bottom
                                anchors.leftMargin: 1
                                anchors.topMargin: 12
                                anchors.bottomMargin: 12
                                width: 3
                                radius: 2
                                color: backend.telegramDownloadRunning ? "#8B72FF" : backend.telegramReady ? "#4ED19E" : "#E4A552"
                            }

                            ColumnLayout {
                                anchors.fill: parent
                                anchors.margins: 17
                                spacing: 10

                                RowLayout {
                                    Layout.fillWidth: true
                                    spacing: 11
                                    Rectangle {
                                        Layout.preferredWidth: 42
                                        Layout.preferredHeight: 42
                                        radius: 13
                                        color: backend.telegramDownloadRunning ? "#302750" : backend.telegramReady ? "#19372E" : "#3A2924"
                                        Text {
                                            anchors.centerIn: parent
                                            text: backend.telegramDownloadRunning ? "↓" : backend.telegramReady ? "✓" : "!"
                                            color: backend.telegramDownloadRunning ? "#B5A4FF" : backend.telegramReady ? "#63D6A5" : "#F0B55A"
                                            font.pixelSize: 18
                                            font.weight: Font.Bold
                                        }
                                    }
                                    ColumnLayout {
                                        Layout.fillWidth: true
                                        spacing: 2
                                        Text { text: "Telegram Desktop"; color: "#E7E4EC"; font.pixelSize: 14; font.weight: Font.DemiBold }
                                        Text {
                                            Layout.fillWidth: true
                                            text: backend.telegramDownloadRunning
                                                  ? backend.telegramDownloadStatus
                                                  : backend.telegramReady ? window.l("Клиент готов к запуску", "Client is ready", "Клієнт готовий до запуску") : window.l("Клиент можно установить из официального релиза", "Install the client from the official release", "Клієнт можна встановити з офіційного релізу")
                                            color: backend.telegramReady ? "#62CFA5" : "#D6A05A"
                                            font.pixelSize: 10
                                            elide: Text.ElideRight
                                        }
                                    }
                                }

                                Text { Layout.fillWidth: true; text: backend.defaultClient(); color: "#777482"; font.pixelSize: 10; elide: Text.ElideMiddle }
                                Item { Layout.fillHeight: true }
                                RowLayout {
                                    Layout.fillWidth: true
                                    spacing: 10
                                    AppButton {
                                        Layout.fillWidth: true
                                        text: backend.telegramDownloadRunning
                                              ? "Загрузка " + backend.telegramDownloadProgress + "%"
                                              : backend.telegramReady ? window.l("Проверить", "Check", "Перевірити") : window.l("Скачать", "Download", "Завантажити")
                                        tone: backend.telegramReady ? "secondary" : "primary"
                                        enabled: !backend.telegramDownloadRunning
                                        onClicked: backend.telegramReady
                                                   ? backend.refreshTelegramStatus()
                                                   : telegramDownloadDialog.open()
                                    }
                                    AppButton { Layout.fillWidth: true; text: window.l("Открыть папку", "Open folder", "Відкрити папку"); tone: "secondary"; onClicked: backend.openTelegramDirectory() }
                                }
                            }
                        }

                        Rectangle {
                            Layout.fillWidth: true
                            Layout.preferredHeight: 176
                            radius: 16
                            color: "#1B1A22"
                            border.width: 1
                            border.color: "#353144"

                            Rectangle {
                                anchors.left: parent.left
                                anchors.top: parent.top
                                anchors.bottom: parent.bottom
                                anchors.leftMargin: 1
                                anchors.topMargin: 12
                                anchors.bottomMargin: 12
                                width: 3
                                radius: 2
                                color: "#8770F8"
                            }

                            ColumnLayout {
                                anchors.fill: parent
                                anchors.margins: 17
                                spacing: 10

                                RowLayout {
                                    Layout.fillWidth: true
                                    spacing: 11
                                    Rectangle {
                                        Layout.preferredWidth: 42
                                        Layout.preferredHeight: 42
                                        radius: 13
                                        color: "#28243C"
                                        Text {
                                            anchors.centerIn: parent
                                            text: String(accountModel.count)
                                            color: "#B3A4FF"
                                            font.pixelSize: accountModel.count > 99 ? 11 : 13
                                            font.weight: Font.Bold
                                        }
                                    }
                                    ColumnLayout {
                                        Layout.fillWidth: true
                                        spacing: 2
                                        Text { text: window.l("Профили и сессии", "Profiles and sessions", "Профілі та сесії"); color: "#E7E4EC"; font.pixelSize: 14; font.weight: Font.DemiBold }
                                        Text { text: window.l("Локальное хранилище данных", "Local data storage", "Локальне сховище даних"); color: "#85818F"; font.pixelSize: 10 }
                                    }
                                }

                                Text { Layout.fillWidth: true; text: backend.dataDirectory(); color: "#777482"; font.pixelSize: 10; elide: Text.ElideMiddle }
                                Item { Layout.fillHeight: true }
                                RowLayout {
                                    Layout.fillWidth: true
                                    spacing: 10
                                    AppButton { Layout.fillWidth: true; text: window.l("Сканировать", "Scan", "Сканувати"); tone: "secondary"; onClicked: backend.scanDataProfiles() }
                                    AppButton { Layout.fillWidth: true; text: window.l("Открыть папку", "Open folder", "Відкрити папку"); tone: "secondary"; onClicked: backend.openDataDirectory() }
                                }
                            }
                        }
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        Layout.topMargin: 4
                        spacing: 3
                        Text { text: window.l("Подключение", "Connection", "Підключення"); color: "#F2F0F6"; font.pixelSize: 16; font.weight: Font.DemiBold }
                        Text { text: window.l("Прокси по умолчанию для авторизации и запуска Telegram.", "Default proxy for authorization and Telegram launch.", "Проксі за замовчуванням для авторизації та запуску Telegram."); color: "#777582"; font.pixelSize: 11 }
                    }

                    Rectangle {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 152
                        radius: 16
                        color: "#1B1A22"
                        border.width: 1
                        border.color: settingsProxyField.activeFocus ? "#4D416F" : "#302E39"

                        ColumnLayout {
                            anchors.fill: parent
                            anchors.margins: 17
                            spacing: 10

                            RowLayout {
                                Layout.fillWidth: true
                                spacing: 11
                                Rectangle {
                                    Layout.preferredWidth: 66
                                    Layout.preferredHeight: 38
                                    radius: 12
                                    color: "#28243C"
                                    Text { anchors.centerIn: parent; text: "SOCKS5"; color: "#B3A4FF"; font.pixelSize: 10; font.weight: Font.DemiBold }
                                }
                                ColumnLayout {
                                    Layout.fillWidth: true
                                    spacing: 2
                                    Text { text: window.l("Глобальный прокси", "Global proxy", "Глобальний проксі"); color: "#E7E4EC"; font.pixelSize: 14; font.weight: Font.DemiBold }
                                    Text { text: window.l("Применяется, если у профиля не указан собственный", "Used when a profile has no proxy of its own", "Використовується, якщо профіль не має власного проксі"); color: "#777482"; font.pixelSize: 10 }
                                }
                            }

                            RowLayout {
                                Layout.fillWidth: true
                                spacing: 10
                                TextField {
                                    id: settingsProxyField
                                    Layout.fillWidth: true
                                    implicitHeight: 42
                                    placeholderText: "login:password@ip:port"
                                    color: "#ECEAF1"
                                    placeholderTextColor: "#5F5D69"
                                    leftPadding: 13
                                    rightPadding: 13
                                    inputMethodHints: Qt.ImhNoAutoUppercase | Qt.ImhNoPredictiveText
                                    Component.onCompleted: text = backend.defaultProxy()
                                    background: Rectangle {
                                        radius: 11
                                        color: "#121117"
                                        border.width: 1
                                        border.color: settingsProxyField.activeFocus ? "#715AC7" : "#302F38"
                                    }
                                }
                                AppButton { text: window.l("Сохранить", "Save", "Зберегти"); tone: "secondary"; onClicked: backend.saveDefaultProxy(settingsProxyField.text) }
                                AppButton { text: window.l("Очистить", "Clear", "Очистити"); tone: "secondary"; onClicked: { settingsProxyField.text = ""; backend.saveDefaultProxy("") } }
                            }
                        }
                    }

                    Rectangle {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 74
                        Layout.bottomMargin: 24
                        radius: 15
                        color: "#201E29"
                        border.width: 1
                        border.color: "#322D44"
                        RowLayout {
                            anchors.fill: parent
                            anchors.margins: 16
                            spacing: 13
                            Rectangle {
                                Layout.preferredWidth: 32
                                Layout.preferredHeight: 32
                                radius: 10
                                color: "#2E2847"
                                Text { anchors.centerIn: parent; text: "i"; color: "#AA96FF"; font.pixelSize: 16; font.weight: Font.Bold }
                            }
                            Text {
                                Layout.fillWidth: true
                                text: window.l(
                                          "TGA Manager работает в переносном режиме: Telegram, Profile_N и .session-файлы остаются в папке приложения и не отправляются в сеть.",
                                          "TGA Manager is portable: Telegram, Profile_N and .session files remain in the application folder and are never uploaded.",
                                          "TGA Manager працює в переносному режимі: Telegram, Profile_N і файли .session залишаються в папці програми та не надсилаються в мережу."
                                      )
                                color: "#A7A3B2"
                                font.pixelSize: 10
                                wrapMode: Text.WordWrap
                                lineHeight: 1.2
                            }
                        }
                    }
                }
            }
        }
    }

    Dialog {
        id: telegramDownloadDialog
        modal: true
        width: Math.min(650, window.width - 60)
        height: Math.min(560, window.height - 50)
        x: (window.width - width) / 2
        y: (window.height - height) / 2
        padding: 0
        closePolicy: Popup.CloseOnEscape
        background: Rectangle { radius: 20; color: "#1B1A21"; border.width: 1; border.color: "#34323D" }

        contentItem: ColumnLayout {
            spacing: 0

            RowLayout {
                Layout.fillWidth: true
                Layout.preferredHeight: 72
                Layout.leftMargin: 24
                Layout.rightMargin: 16
                ColumnLayout {
                    spacing: 2
                    Text { text: window.l("Установка Telegram Desktop", "Install Telegram Desktop", "Встановлення Telegram Desktop"); color: "#F4F3F8"; font.pixelSize: 19; font.weight: Font.Bold }
                    Text { text: window.l("Официальная portable-версия для Windows x64", "Official portable version for Windows x64", "Офіційна переносна версія для Windows x64"); color: "#777582"; font.pixelSize: 11 }
                }
                Item { Layout.fillWidth: true }
                ToolButton {
                    id: telegramDownloadCloseButton
                    implicitWidth: 32
                    implicitHeight: 32
                    padding: 0
                    onClicked: telegramDownloadDialog.close()
                    contentItem: Item {
                        Rectangle { width: 12; height: 1.8; radius: 1; color: "#AAA8B4"; anchors.centerIn: parent; rotation: 45 }
                        Rectangle { width: 12; height: 1.8; radius: 1; color: "#AAA8B4"; anchors.centerIn: parent; rotation: -45 }
                    }
                    background: Rectangle { anchors.fill: parent; radius: 8; color: telegramDownloadCloseButton.hovered ? "#2B2933" : "transparent" }
                }
            }

            Rectangle { Layout.fillWidth: true; Layout.preferredHeight: 1; color: "#2B2A33" }

            ColumnLayout {
                Layout.fillWidth: true
                Layout.fillHeight: true
                Layout.margins: 22
                spacing: 13

                Text {
                    Layout.fillWidth: true
                    text: window.l("Можно скачать последнюю стабильную версию автоматически или выбрать официальный ZIP вручную. Аккаунты и tdata при этом не затрагиваются.", "Download the latest stable release automatically or select the official ZIP manually. Accounts and tdata are not affected.", "Можна автоматично завантажити останню стабільну версію або вибрати офіційний ZIP вручну. Акаунти й tdata не змінюються.")
                    color: "#A7A3B2"
                    font.pixelSize: 11
                    wrapMode: Text.WordWrap
                    lineHeight: 1.2
                }

                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 146
                    radius: 16
                    color: "#201D2B"
                    border.width: 1
                    border.color: "#3A3350"

                    ColumnLayout {
                        anchors.fill: parent
                        anchors.margins: 16
                        spacing: 10

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 12
                            Rectangle {
                                Layout.preferredWidth: 42
                                Layout.preferredHeight: 42
                                radius: 13
                                color: "#302750"
                                Text { anchors.centerIn: parent; text: "↓"; color: "#B6A4FF"; font.pixelSize: 21; font.weight: Font.Bold }
                            }
                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 3
                                Text { text: window.l("Автоматически", "Automatically", "Автоматично"); color: "#F0EDF6"; font.pixelSize: 14; font.weight: Font.DemiBold }
                                Text {
                                    Layout.fillWidth: true
                                    text: window.l("Найдём последний tportable-x64 на GitHub, скачаем и распакуем его в папку Telegram.", "Find the latest tportable-x64 on GitHub, download it and extract it into the Telegram folder.", "Знайдемо останній tportable-x64 на GitHub, завантажимо та розпакуємо його в папку Telegram.")
                                    color: "#8D8898"
                                    font.pixelSize: 10
                                    wrapMode: Text.WordWrap
                                }
                            }
                            AppButton {
                                text: backend.telegramDownloadRunning ? window.l("Загрузка…", "Downloading…", "Завантаження…") : window.l("Скачать x64", "Download x64", "Завантажити x64")
                                enabled: !backend.telegramDownloadRunning
                                onClicked: backend.downloadLatestTelegram()
                            }
                        }

                        ProgressBar {
                            id: telegramDownloadProgress
                            Layout.fillWidth: true
                            Layout.preferredHeight: 6
                            visible: backend.telegramDownloadRunning
                            from: 0
                            to: 100
                            value: backend.telegramDownloadProgress
                            indeterminate: backend.telegramDownloadRunning && backend.telegramDownloadProgress === 0
                            background: Rectangle { implicitHeight: 6; radius: 3; color: "#302D39" }
                            contentItem: Item {
                                implicitHeight: 6
                                Rectangle {
                                    width: telegramDownloadProgress.visualPosition * parent.width
                                    height: parent.height
                                    radius: 3
                                    color: "#8065F5"
                                }
                            }
                        }

                        Text {
                            Layout.fillWidth: true
                            visible: backend.telegramDownloadStatus.length > 0
                            text: backend.telegramDownloadStatus
                            color: backend.telegramDownloadRunning ? "#AAA1C7" : "#FF9299"
                            font.pixelSize: 10
                            elide: Text.ElideRight
                        }
                    }
                }

                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 142
                    radius: 16
                    color: "#19181F"
                    border.width: 1
                    border.color: "#302E39"

                    ColumnLayout {
                        anchors.fill: parent
                        anchors.margins: 16
                        spacing: 9

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 12
                            Rectangle {
                                Layout.preferredWidth: 42
                                Layout.preferredHeight: 42
                                radius: 13
                                color: "#25242D"
                                Text { anchors.centerIn: parent; text: "▣"; color: "#AAA6B7"; font.pixelSize: 17 }
                            }
                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 3
                                Text { text: window.l("Вручную", "Manually", "Вручну"); color: "#E7E4EC"; font.pixelSize: 14; font.weight: Font.DemiBold }
                                Text {
                                    Layout.fillWidth: true
                                    text: window.l("Скачайте на странице релизов файл tportable-x64.*.zip, затем выберите его здесь.", "Download tportable-x64.*.zip from the releases page, then select it here.", "Завантажте tportable-x64.*.zip зі сторінки релізів, потім виберіть його тут.")
                                    color: "#85818F"
                                    font.pixelSize: 10
                                    wrapMode: Text.WordWrap
                                }
                            }
                        }

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 10
                            AppButton { Layout.fillWidth: true; text: window.l("Открыть релизы", "Open releases", "Відкрити релізи"); tone: "secondary"; enabled: !backend.telegramDownloadRunning; onClicked: backend.openTelegramReleases() }
                            AppButton { Layout.fillWidth: true; text: window.l("Выбрать ZIP", "Select ZIP", "Вибрати ZIP"); tone: "secondary"; enabled: !backend.telegramDownloadRunning; onClicked: telegramArchiveDialog.open() }
                        }
                    }
                }

                Item { Layout.fillHeight: true }
                RowLayout {
                    Layout.fillWidth: true
                    Item { Layout.fillWidth: true }
                    AppButton { text: backend.telegramDownloadRunning ? window.l("Скрыть", "Hide", "Сховати") : window.l("Закрыть", "Close", "Закрити"); tone: "secondary"; onClicked: telegramDownloadDialog.close() }
                }
            }
        }
    }

    Dialog {
        id: accountDialog
        modal: true
        width: 610
        height: Math.min(window.height - 70, 700)
        x: (window.width - width) / 2
        y: (window.height - height) / 2
        padding: 0
        closePolicy: (backend.importRunning || backend.manualLoginRunning) ? Popup.NoAutoClose : Popup.CloseOnEscape
        background: Rectangle { radius: 20; color: "#1B1A21"; border.width: 1; border.color: "#34323D" }

        contentItem: ColumnLayout {
            spacing: 0
            RowLayout {
                Layout.fillWidth: true; Layout.preferredHeight: 70; Layout.leftMargin: 24; Layout.rightMargin: 16
                ColumnLayout { spacing: 2; Text { text: window.editingId.length ? window.l("Редактировать аккаунт", "Edit account", "Редагувати акаунт") : window.l("Новый аккаунт", "New account", "Новий акаунт"); color: "#F4F3F8"; font.pixelSize: 19; font.weight: Font.Bold } Text { text: window.l("Настройте локальную TDATA-сессию", "Configure a local TDATA session", "Налаштуйте локальну TDATA-сесію"); color: "#777582"; font.pixelSize: 11 } }
                Item { Layout.fillWidth: true }
                ToolButton {
                    id: accountDialogCloseButton
                    implicitWidth: 32
                    implicitHeight: 32
                    padding: 0
                    enabled: !backend.importRunning
                    onClicked: window.closeAccountDialog()
                    contentItem: Item {
                        Rectangle { width: 12; height: 1.8; radius: 1; color: accountDialogCloseButton.enabled ? "#AAA8B4" : "#55535F"; anchors.centerIn: parent; rotation: 45 }
                        Rectangle { width: 12; height: 1.8; radius: 1; color: accountDialogCloseButton.enabled ? "#AAA8B4" : "#55535F"; anchors.centerIn: parent; rotation: -45 }
                    }
                    background: Rectangle { anchors.fill: parent; radius: 8; color: parent.hovered ? "#2B2933" : "transparent" }
                }
            }
            Rectangle { Layout.fillWidth: true; height: 1; color: "#2B2A33" }

            ScrollView {
                Layout.fillWidth: true; Layout.fillHeight: true; clip: true
                contentWidth: availableWidth
                ColumnLayout {
                    width: parent.width - 48
                    x: 24
                    y: 20
                    spacing: 14
                    RowLayout {
                        Layout.fillWidth: true; spacing: 12
                        ColumnLayout {
                            Layout.preferredWidth: 190
                            Layout.minimumWidth: 165
                            Layout.maximumWidth: 220
                            spacing: 6
                            Text { text: window.editingId.length ? window.l("Название *", "Name *", "Назва *") : window.l("Название", "Name", "Назва"); color: "#AAA8B4"; font.pixelSize: 11; font.weight: Font.DemiBold }
                            TextField {
                                id: nameField
                                Layout.fillWidth: true
                                implicitHeight: 42
                                placeholderText: window.l("Заполнится из Telegram", "Filled from Telegram", "Заповниться з Telegram")
                                color: "#ECEAF1"
                                placeholderTextColor: "#5F5D69"
                                background: Rectangle { radius: 10; color: "#141319"; border.width: 1; border.color: parent.activeFocus ? "#654FBB" : "#302F38" }
                            }
                        }
                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 6
                            Text { text: window.l("Прокси SOCKS5", "SOCKS5 proxy", "Проксі SOCKS5"); color: "#AAA8B4"; font.pixelSize: 11; font.weight: Font.DemiBold }
                            TextField {
                                id: proxyField
                                enabled: !backend.manualLoginRunning && !backend.importRunning
                                Layout.fillWidth: true
                                implicitHeight: 42
                                placeholderText: backend.defaultProxy().length ? "Пусто = глобальный прокси" : "login:password@ip:port"
                                color: enabled ? "#ECEAF1" : "#777582"
                                placeholderTextColor: "#5F5D69"
                                inputMethodHints: Qt.ImhNoAutoUppercase | Qt.ImhNoPredictiveText
                                background: Rectangle {
                                    radius: 10
                                    color: "#141319"
                                    border.width: 1
                                    border.color: parent.activeFocus ? "#654FBB" : "#302F38"
                                    opacity: parent.enabled ? 1 : 0.72
                                }
                            }
                        }
                    }
                    Text { text: window.l("Пустое поле использует глобальный прокси. Формат: login:password@ip:port", "An empty field uses the global proxy. Format: login:password@ip:port", "Порожнє поле використовує глобальний проксі. Формат: login:password@ip:port"); color: "#5F5D69"; font.pixelSize: 10; wrapMode: Text.WordWrap; Layout.fillWidth: true }

                    Text { text: window.l("Папка TDATA", "TDATA folder", "Папка TDATA"); color: "#AAA8B4"; font.pixelSize: 11; font.weight: Font.DemiBold }
                    RowLayout {
                        Layout.fillWidth: true; spacing: 9
                        TextField { id: tdataField; enabled: !backend.manualLoginRunning && !backend.importRunning; Layout.fillWidth: true; implicitHeight: 42; placeholderText: "D:\\Sessions\\Account\\tdata"; color: enabled ? "#ECEAF1" : "#777582"; placeholderTextColor: "#5F5D69"; background: Rectangle { radius: 10; color: "#141319"; border.width: 1; border.color: parent.activeFocus ? "#654FBB" : "#302F38"; opacity: parent.enabled ? 1 : 0.72 } }
                        AppButton { text: window.l("Обзор", "Browse", "Огляд"); tone: "secondary"; enabled: !backend.manualLoginRunning && !backend.importRunning; onClicked: tdataFolderDialog.open() }
                    }
                    Text { text: window.l("Можно выбрать готовую tdata или войти вручную через Telegram без выбора папки.", "Select an existing tdata or sign in manually through Telegram without choosing a folder.", "Можна вибрати готову tdata або увійти вручну через Telegram без вибору папки."); color: "#5F5D69"; font.pixelSize: 10 }

                    Rectangle {
                        Layout.fillWidth: true
                        implicitHeight: 62
                        radius: 11
                        color: "#242032"
                        border.width: 1
                        border.color: "#3A3155"
                        visible: backend.importRunning || backend.manualLoginRunning || window.importProgressMessage.length > 0
                        ColumnLayout {
                            anchors.fill: parent; anchors.margins: 12; spacing: 7
                            RowLayout { Layout.fillWidth: true; Text { text: backend.manualLoginRunning ? "Пройдите авторизацию в Telegram, дождитесь загрузки аккаунта и нажмите «Завершить»." : window.importProgressMessage; color: "#C7C2D8"; font.pixelSize: 11; Layout.fillWidth: true; elide: Text.ElideRight } Text { text: backend.manualLoginRunning ? "ручной вход" : window.importProgressValue + "%"; color: "#9B87F8"; font.pixelSize: 10; font.weight: Font.DemiBold } }
                            ProgressBar {
                                Layout.fillWidth: true; from: 0; to: 100; value: window.importProgressValue
                                background: Rectangle { implicitHeight: 5; radius: 3; color: "#302D3D" }
                                contentItem: Item { implicitHeight: 5; Rectangle { width: parent.width * Math.max(0, Math.min(1, window.importProgressValue / 100)); height: parent.height; radius: 3; color: "#7657F6"; Behavior on width { NumberAnimation { duration: 180 } } } }
                            }
                        }
                    }

                    Text { text: window.l("Цвет профиля", "Profile color", "Колір профілю"); color: "#AAA8B4"; font.pixelSize: 11; font.weight: Font.DemiBold }
                    Flow {
                        Layout.fillWidth: true
                        spacing: 10
                        Repeater {
                            model: window.profileColors
                            Rectangle {
                                width: 30; height: 30; radius: 9; color: modelData
                                border.width: window.selectedColor === modelData ? 3 : 0
                                border.color: "#E8E4FF"
                                scale: colorMouse.containsMouse ? 1.08 : 1
                                Behavior on scale { NumberAnimation { duration: 100 } }
                                MouseArea { id: colorMouse; anchors.fill: parent; hoverEnabled: true; onClicked: window.selectedColor = modelData }
                            }
                        }
                    }

                    Text { text: window.l("Заметка", "Note", "Нотатка"); color: "#AAA8B4"; font.pixelSize: 11; font.weight: Font.DemiBold }
                    TextArea { id: notesField; Layout.fillWidth: true; Layout.preferredHeight: 68; placeholderText: window.l("Например: основной рабочий профиль", "For example: main work profile", "Наприклад: основний робочий профіль"); color: "#ECEAF1"; placeholderTextColor: "#5F5D69"; wrapMode: TextArea.Wrap; background: Rectangle { radius: 10; color: "#141319"; border.width: 1; border.color: parent.activeFocus ? "#654FBB" : "#302F38" } }
                    AppCheckBox { id: favoriteCheck; text: window.l("Добавить в избранное", "Add to favorites", "Додати до вибраного") }
                    Text { id: editorError; Layout.fillWidth: true; color: "#FF858D"; font.pixelSize: 11; visible: text.length > 0 }
                }
            }

            Rectangle { Layout.fillWidth: true; height: 1; color: "#2B2A33" }
            RowLayout {
                Layout.fillWidth: true; Layout.preferredHeight: 70; Layout.leftMargin: 24; Layout.rightMargin: 24; spacing: 10
                Item { Layout.fillWidth: true }
                AppButton { text: backend.manualLoginRunning ? window.l("Отменить вход", "Cancel sign-in", "Скасувати вхід") : window.l("Отмена", "Cancel", "Скасувати"); tone: "secondary"; enabled: !backend.importRunning; onClicked: window.closeAccountDialog() }
                AppButton { visible: window.editingId.length === 0 && !backend.manualLoginRunning; enabled: !backend.importRunning && !backend.manualLoginRunning; text: window.l("Ручной вход", "Manual sign-in", "Ручний вхід"); tone: "secondary"; onClicked: window.startManualLogin() }
                AppButton { visible: window.editingId.length === 0 && backend.manualLoginRunning; enabled: !backend.importRunning; text: window.l("Завершить", "Finish", "Завершити"); onClicked: window.finishManualLogin() }
                AppButton { visible: !backend.manualLoginRunning || window.editingId.length > 0; text: backend.importRunning ? window.l("Импорт…", "Importing…", "Імпорт…") : window.editingId.length ? window.l("Сохранить", "Save", "Зберегти") : window.l("Авторизация TDATA", "Authorize TDATA", "Авторизація TDATA"); enabled: !backend.importRunning && !backend.manualLoginRunning; onClicked: window.editingId.length ? window.saveAccount() : window.authorizeAndImport() }
            }
        }
    }

    Dialog {
        id: accountInfoDialog
        modal: true
        width: Math.min(window.width - 80, 760)
        height: Math.min(window.height - 80, 700)
        x: (window.width - width) / 2
        y: (window.height - height) / 2
        padding: 0
        standardButtons: Dialog.NoButton
        background: Rectangle { radius: 20; color: "#1B1A21"; border.width: 1; border.color: "#34323D" }

        contentItem: ColumnLayout {
            spacing: 0
            RowLayout {
                Layout.fillWidth: true
                Layout.preferredHeight: 74
                Layout.leftMargin: 24
                Layout.rightMargin: 16
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 2
                    Text { text: window.l("Информация об аккаунте", "Account information", "Інформація про акаунт"); color: "#F4F3F8"; font.pixelSize: 20; font.weight: Font.Bold }
                    Text { text: infoValue("profileFolder", window.l("Локальный профиль", "Local profile", "Локальний профіль")); color: "#777582"; font.pixelSize: 11; elide: Text.ElideMiddle; Layout.fillWidth: true }
                }
                ToolButton {
                    id: accountInfoCloseButton
                    implicitWidth: 32
                    implicitHeight: 32
                    padding: 0
                    onClicked: accountInfoDialog.close()
                    contentItem: Item {
                        Rectangle { width: 12; height: 1.8; radius: 1; color: "#AAA8B4"; anchors.centerIn: parent; rotation: 45 }
                        Rectangle { width: 12; height: 1.8; radius: 1; color: "#AAA8B4"; anchors.centerIn: parent; rotation: -45 }
                    }
                    background: Rectangle { anchors.fill: parent; radius: 8; color: parent.hovered ? "#2B2933" : "transparent" }
                }
            }
            Rectangle { Layout.fillWidth: true; height: 1; color: "#2B2A33" }

            ScrollView {
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true
                contentWidth: availableWidth

                ColumnLayout {
                    width: Math.min(parent.width - 48, 720)
                    x: (parent.width - width) / 2
                    y: 22
                    spacing: 18

                    Item {
                        Layout.fillWidth: true
                        implicitHeight: 158

                        RowLayout {
                            anchors.fill: parent
                            spacing: 12

                            Item {
                                Layout.preferredWidth: 152
                                Layout.minimumWidth: 132
                                Layout.maximumWidth: 168
                                Layout.fillHeight: true

                                ColumnLayout {
                                    anchors.centerIn: parent
                                    width: parent.width
                                    spacing: 9

                                    Rectangle {
                                        id: accountInfoAvatar
                                        property string avatarUrl: String(accountInfo.avatarUrl || (accountInfo.avatarPath ? backend.pathToUrl(accountInfo.avatarPath) : ""))
                                        Layout.alignment: Qt.AlignHCenter
                                        width: 82; height: 82; radius: 24
                                        color: accountInfoAvatarImage.status === Image.Ready ? "#15141A" : "#7657F6"
                                        border.width: 2
                                        border.color: "#7657F6"

                                        Rectangle {
                                            id: accountInfoAvatarMask
                                            anchors.fill: accountInfoAvatarContent
                                            radius: 21
                                            visible: false
                                        }

                                        Item {
                                            id: accountInfoAvatarContent
                                            anchors.fill: parent
                                            anchors.margins: 3
                                            layer.enabled: true
                                            layer.effect: OpacityMask { maskSource: accountInfoAvatarMask }

                                            Rectangle { anchors.fill: parent; color: "#7657F6" }
                                            Image {
                                                id: accountInfoAvatarImage
                                                anchors.fill: parent
                                                source: accountInfoAvatar.avatarUrl
                                                fillMode: Image.PreserveAspectCrop
                                                visible: status === Image.Ready
                                                asynchronous: true
                                                cache: false
                                                mipmap: true
                                            }
                                            Text { anchors.centerIn: parent; visible: accountInfoAvatarImage.status !== Image.Ready; text: infoValue("name", "TG").substring(0, 2).toUpperCase(); color: "white"; font.pixelSize: 20; font.weight: Font.Bold }
                                        }
                                    }
                                    Text { Layout.fillWidth: true; text: infoValue("name"); color: "#F4F3F8"; font.pixelSize: 13; font.weight: Font.DemiBold; horizontalAlignment: Text.AlignHCenter; elide: Text.ElideRight }
                                }
                            }

                            ColumnLayout {
                                Layout.fillWidth: true
                                Layout.fillHeight: true
                                spacing: 10

                                InfoTile { title: window.l("Телефон", "Phone", "Телефон"); value: infoValue("phone"); copyValue: accountInfo.phone; onCopyRequested: copiedValue => window.copyInfo(copiedValue) }
                                InfoTile { title: "Username"; value: infoValue("username") === "—" ? "—" : "@" + infoValue("username"); copyValue: accountInfo.username; onCopyRequested: copiedValue => window.copyInfo(copiedValue) }
                            }

                            ColumnLayout {
                                Layout.fillWidth: true
                                Layout.fillHeight: true
                                spacing: 10

                                InfoTile { title: "Telegram ID"; value: infoValue("telegramUserId"); copyValue: accountInfo.telegramUserId; onCopyRequested: copiedValue => window.copyInfo(copiedValue) }
                                InfoTile { title: window.l("Ник", "Name", "Ім'я"); value: infoValue("name"); copyValue: accountInfo.name; onCopyRequested: copiedValue => window.copyInfo(copiedValue) }
                            }

                            ColumnLayout {
                                Layout.preferredWidth: 158
                                Layout.minimumWidth: 134
                                Layout.maximumWidth: 176
                                Layout.fillHeight: true
                                spacing: 10

                                InfoTile { title: "Premium"; value: accountInfo.isPremium ? "Да" : "Нет"; copyable: false; highlighted: accountInfo.isPremium }
                                InfoTile { title: "DC"; value: infoValue("dcId"); copyable: false }
                            }
                        }
                    }

                    Text { text: window.l("Сессия и API", "Session and API", "Сесія та API"); color: "#F0EFF4"; font.pixelSize: 15; font.weight: Font.DemiBold }

                    RowLayout {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 38
                        spacing: 12

                        ApiPill {
                            Layout.preferredWidth: 214
                            label: "API ID:"
                            value: infoValue("apiId")
                            copyValue: accountInfo.apiId
                            onCopyRequested: copiedValue => window.copyInfo(copiedValue)
                        }

                        ApiPill {
                            Layout.fillWidth: true
                            label: "API HASH:"
                            value: infoValue("apiHash") === "—" ? "—" : (window.showApiHash ? infoValue("apiHash") : window.masked(accountInfo.apiHash, 24))
                            copyValue: accountInfo.apiHash
                            canReveal: true
                            revealed: window.showApiHash
                            onRevealToggled: window.showApiHash = !window.showApiHash
                            onCopyRequested: copiedValue => window.copyInfo(copiedValue)
                        }
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 38

                        ApiPill {
                            Layout.fillWidth: true
                            label: "AUTH KEY (HEX):"
                            value: infoValue("authKeyHex") === "—"
                                   ? "Не найден"
                                   : (window.showAuthKey ? infoValue("authKeyHex") : window.masked(accountInfo.authKeyHex, 56))
                            copyValue: accountInfo.authKeyHex
                            canReveal: true
                            revealed: window.showAuthKey
                            onRevealToggled: window.showAuthKey = !window.showAuthKey
                            onCopyRequested: copiedValue => window.copyInfo(copiedValue)
                        }
                    }

                    Rectangle {
                        Layout.fillWidth: true
                        implicitHeight: 82
                        radius: 14
                        color: "#18171E"
                        border.width: 1
                        border.color: "#2C2A36"
                        ColumnLayout {
                            anchors.fill: parent
                            anchors.margins: 14
                            spacing: 6
                            Text { text: window.l("Заметки", "Notes", "Нотатки"); color: "#F0EFF4"; font.pixelSize: 13; font.weight: Font.DemiBold }
                            TextArea {
                                Layout.fillWidth: true
                                Layout.fillHeight: true
                                text: infoValue("notes", window.l("Заметок нет", "No notes", "Нотаток немає"))
                                color: infoValue("notes") === "—" ? "#777582" : "#CFCBDA"
                                font.pixelSize: 12
                                readOnly: true
                                selectByMouse: true
                                persistentSelection: true
                                wrapMode: TextArea.Wrap
                                padding: 0
                                selectedTextColor: "#FFFFFF"
                                selectionColor: "#7657F6"
                                background: Item {}
                            }
                        }
                    }
                }
            }
        }
    }

    Dialog {
        id: deleteDialog
        property string accountName: ""
        property bool deleteFiles: false

        function confirmDelete() {
            const removed = accountModel.deleteAccount(window.pendingDeleteId, deleteDialog.deleteFiles)
            if (!removed) {
                window.showToast(window.l("Не удалось удалить профиль. Убедитесь, что Telegram закрыт.", "Failed to remove the profile. Make sure Telegram is closed.", "Не вдалося видалити профіль. Переконайтеся, що Telegram закрито."), "error")
                return
            }
            deleteDialog.close()
            window.showToast(
                deleteDialog.deleteFiles
                    ? window.l("Профиль и его файлы удалены", "Profile and its files deleted", "Профіль і його файли видалено")
                    : window.l("Профиль убран из менеджера", "Profile removed from manager", "Профіль прибрано з менеджера"),
                "success"
            )
        }

        modal: true
        width: Math.min(540, window.width - 60)
        height: Math.min(deleteDialog.deleteFiles ? 460 : 410, window.height - 50)
        x: (window.width - width) / 2
        y: (window.height - height) / 2
        padding: 0
        onOpened: deleteFiles = false
        standardButtons: Dialog.NoButton
        closePolicy: Popup.CloseOnEscape
        Behavior on height { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
        Behavior on y { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
        background: Rectangle { radius: 20; color: "#1B1A21"; border.width: 1; border.color: "#3C3038" }

        contentItem: ColumnLayout {
            spacing: 0

            RowLayout {
                Layout.fillWidth: true
                Layout.preferredHeight: 76
                Layout.leftMargin: 22
                Layout.rightMargin: 15
                spacing: 12

                Rectangle {
                    Layout.preferredWidth: 40
                    Layout.preferredHeight: 40
                    radius: 12
                    color: "#382329"
                    Text {
                        anchors.centerIn: parent
                        text: "\uE74D"
                        font.family: "Segoe MDL2 Assets"
                        font.pixelSize: 17
                        color: "#FF858D"
                    }
                }
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 2
                    Text { text: window.l("Удалить аккаунт?", "Delete account?", "Видалити акаунт?"); color: "#F4F3F8"; font.pixelSize: 18; font.weight: Font.Bold }
                    Text { Layout.fillWidth: true; text: deleteDialog.accountName; color: "#8B8794"; font.pixelSize: 11; elide: Text.ElideRight }
                }
                ToolButton {
                    id: deleteDialogCloseButton
                    implicitWidth: 32
                    implicitHeight: 32
                    padding: 0
                    onClicked: deleteDialog.close()
                    contentItem: Item {
                        Rectangle { width: 12; height: 1.8; radius: 1; color: "#AAA8B4"; anchors.centerIn: parent; rotation: 45 }
                        Rectangle { width: 12; height: 1.8; radius: 1; color: "#AAA8B4"; anchors.centerIn: parent; rotation: -45 }
                    }
                    background: Rectangle { anchors.fill: parent; radius: 8; color: deleteDialogCloseButton.hovered ? "#2B2933" : "transparent" }
                }
            }

            Rectangle { Layout.fillWidth: true; Layout.preferredHeight: 1; color: "#2B2A33" }

            ColumnLayout {
                Layout.fillWidth: true
                Layout.fillHeight: true
                Layout.margins: 20
                spacing: 12

                Text {
                    Layout.fillWidth: true
                    text: window.l("Выберите, что нужно сделать с локальными данными профиля.", "Choose what to do with the local profile data.", "Виберіть, що зробити з локальними даними профілю.")
                    color: "#AAA8B4"
                    font.pixelSize: 11
                    wrapMode: Text.WordWrap
                }

                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 88
                    radius: 14
                    color: !deleteDialog.deleteFiles ? "#242033" : keepProfileMouse.containsMouse ? "#211F29" : "#19181F"
                    border.width: 1
                    border.color: !deleteDialog.deleteFiles ? "#6854B6" : keepProfileMouse.containsMouse ? "#3A3748" : "#302E39"

                    RowLayout {
                        anchors.fill: parent
                        anchors.margins: 14
                        spacing: 12
                        Rectangle {
                            Layout.preferredWidth: 36
                            Layout.preferredHeight: 36
                            radius: 11
                            color: "#30284D"
                            Text { anchors.centerIn: parent; text: "−"; color: "#B5A4FF"; font.pixelSize: 20; font.weight: Font.Bold }
                        }
                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 3
                            Text { text: window.l("Убрать из менеджера", "Remove from manager", "Прибрати з менеджера"); color: "#ECE9F2"; font.pixelSize: 13; font.weight: Font.DemiBold }
                            Text { Layout.fillWidth: true; text: window.l("Папка Profile_N, tdata и .session-файлы останутся на диске и будут исключены из автосканирования.", "The Profile_N folder, tdata and .session files remain on disk and are excluded from automatic scanning.", "Папка Profile_N, tdata та файли .session залишаться на диску й будуть виключені з автосканування."); color: "#85818F"; font.pixelSize: 10; wrapMode: Text.WordWrap }
                        }
                        Rectangle {
                            Layout.preferredWidth: 20
                            Layout.preferredHeight: 20
                            radius: 10
                            color: !deleteDialog.deleteFiles ? "#7657F6" : "transparent"
                            border.width: 1
                            border.color: !deleteDialog.deleteFiles ? "#8F77FF" : "#575361"
                            Rectangle { anchors.centerIn: parent; width: 6; height: 6; radius: 3; color: "white"; visible: !deleteDialog.deleteFiles }
                        }
                    }
                    MouseArea { id: keepProfileMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: deleteDialog.deleteFiles = false }
                }

                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 88
                    radius: 14
                    color: deleteDialog.deleteFiles ? "#2D1E23" : deleteFilesMouse.containsMouse ? "#211F29" : "#19181F"
                    border.width: 1
                    border.color: deleteDialog.deleteFiles ? "#753943" : deleteFilesMouse.containsMouse ? "#4A343B" : "#302E39"

                    RowLayout {
                        anchors.fill: parent
                        anchors.margins: 14
                        spacing: 12
                        Rectangle {
                            Layout.preferredWidth: 36
                            Layout.preferredHeight: 36
                            radius: 11
                            color: "#3A242A"
                            Text { anchors.centerIn: parent; text: "\uE74D"; font.family: "Segoe MDL2 Assets"; color: "#FF858D"; font.pixelSize: 15 }
                        }
                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 3
                            Text { text: window.l("Удалить вместе с файлами", "Delete with files", "Видалити разом із файлами"); color: "#F0E8EA"; font.pixelSize: 13; font.weight: Font.DemiBold }
                            Text { Layout.fillWidth: true; text: window.l("Папка профиля и все находящиеся в ней tdata, JSON и .session-файлы будут удалены безвозвратно.", "The profile folder and all tdata, JSON and .session files inside it will be permanently deleted.", "Папку профілю та всі файли tdata, JSON і .session у ній буде видалено назавжди."); color: "#9A7E84"; font.pixelSize: 10; wrapMode: Text.WordWrap }
                        }
                        Rectangle {
                            Layout.preferredWidth: 20
                            Layout.preferredHeight: 20
                            radius: 10
                            color: deleteDialog.deleteFiles ? "#B94C5B" : "transparent"
                            border.width: 1
                            border.color: deleteDialog.deleteFiles ? "#D16673" : "#575361"
                            Rectangle { anchors.centerIn: parent; width: 6; height: 6; radius: 3; color: "white"; visible: deleteDialog.deleteFiles }
                        }
                    }
                    MouseArea { id: deleteFilesMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: deleteDialog.deleteFiles = true }
                }

                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: visible ? 44 : 0
                    visible: deleteDialog.deleteFiles
                    radius: 11
                    color: "#2B2024"
                    border.width: 1
                    border.color: "#4C2D34"
                    Text {
                        anchors.fill: parent
                        anchors.margins: 11
                        text: window.l("Это действие нельзя отменить. Убедитесь, что нужные файлы сохранены.", "This action cannot be undone. Make sure important files are backed up.", "Цю дію неможливо скасувати. Переконайтеся, що потрібні файли збережено.")
                        color: "#E5A0A7"
                        font.pixelSize: 10
                        verticalAlignment: Text.AlignVCenter
                        wrapMode: Text.WordWrap
                    }
                }

                Item { Layout.fillHeight: true }
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 10
                    Item { Layout.fillWidth: true }
                    AppButton { text: window.l("Отмена", "Cancel", "Скасувати"); tone: "secondary"; onClicked: deleteDialog.close() }
                    AppButton {
                        text: deleteDialog.deleteFiles ? window.l("Удалить файлы", "Delete files", "Видалити файли") : window.l("Убрать профиль", "Remove profile", "Прибрати профіль")
                        tone: "danger"
                        onClicked: deleteDialog.confirmDelete()
                    }
                }
            }
        }
    }

    FolderDialog { id: tdataFolderDialog; title: window.l("Выберите папку tdata", "Select tdata folder", "Виберіть папку tdata"); onAccepted: tdataField.text = backend.pathFromUrl(selectedFolder) }
    FileDialog {
        id: telegramArchiveDialog
        title: window.l("Выберите официальный portable ZIP Telegram Desktop", "Select the official Telegram Desktop portable ZIP", "Виберіть офіційний переносний ZIP Telegram Desktop")
        nameFilters: ["Telegram portable (*.zip)", "ZIP-архивы (*.zip)"]
        onAccepted: backend.installTelegramArchive(backend.pathFromUrl(selectedFile))
    }

    DropArea {
        id: archiveDropArea
        anchors.fill: parent
        z: 900
        enabled: !backend.importRunning && !backend.manualLoginRunning
        property bool acceptsArchive: false

        function archiveUrl(urls) {
            const allowed = [
                ".zip", ".tar", ".tar.gz", ".tgz", ".tar.bz2", ".tbz2",
                ".tar.xz", ".txz", ".7z", ".rar"
            ]
            for (let i = 0; i < urls.length; ++i) {
                const url = String(urls[i])
                const lower = url.toLowerCase()
                for (let j = 0; j < allowed.length; ++j) {
                    if (lower.endsWith(allowed[j]))
                        return url
                }
            }
            return ""
        }

        onEntered: (drag) => {
            const urls = drag.urls || []
            acceptsArchive = archiveUrl(urls).length > 0
            drag.accepted = urls.length > 0
        }
        onPositionChanged: (drag) => {
            const urls = drag.urls || []
            acceptsArchive = archiveUrl(urls).length > 0
            drag.accepted = urls.length > 0
        }
        onExited: acceptsArchive = false
        onDropped: (drop) => {
            const url = archiveUrl(drop.urls || [])
            acceptsArchive = false
            if (!url.length) {
                window.showToast("Перетащите архив .zip/.tar/.7z/.rar с папкой tdata", "error")
                return
            }
            drop.acceptProposedAction()
            backend.importArchive(url)
        }

        Rectangle {
            anchors.fill: parent
            visible: archiveDropArea.containsDrag
            color: archiveDropArea.acceptsArchive ? "#B807060B" : "#8F07060B"

            Rectangle {
                anchors.centerIn: parent
                width: Math.min(parent.width - 80, 520)
                height: 186
                radius: 26
                color: "#1B1A24"
                border.width: 1
                border.color: archiveDropArea.acceptsArchive ? "#7657F6" : "#70404A"

                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: 24
                    spacing: 12

                    Rectangle {
                        Layout.alignment: Qt.AlignHCenter
                        width: 54
                        height: 54
                        radius: 18
                        color: archiveDropArea.acceptsArchive ? "#2C244A" : "#30242B"
                        border.width: 1
                        border.color: archiveDropArea.acceptsArchive ? "#7657F6" : "#70404A"

                        Text {
                            anchors.centerIn: parent
                            text: archiveDropArea.acceptsArchive ? "↧" : "!"
                            color: archiveDropArea.acceptsArchive ? "#FFFFFF" : "#FF9299"
                            font.pixelSize: 25
                            font.weight: Font.Bold
                        }
                    }

                    Text {
                        Layout.fillWidth: true
                        text: archiveDropArea.acceptsArchive ? "Отпустите архив для импорта" : "Этот файл не похож на архив"
                        color: "#F4F1FF"
                        horizontalAlignment: Text.AlignHCenter
                        font.pixelSize: 18
                        font.weight: Font.Bold
                    }

                    Text {
                        Layout.fillWidth: true
                        text: archiveDropArea.acceptsArchive
                              ? "Найду внутри tdata, создам Profile_N и добавлю профиль без авторизации."
                              : "Поддерживаются .zip, .tar, .tar.gz, .tar.xz, .tar.bz2, .7z и .rar с папкой tdata внутри."
                        color: "#A8A3B8"
                        horizontalAlignment: Text.AlignHCenter
                        wrapMode: Text.WordWrap
                        font.pixelSize: 12
                    }
                }
            }
        }
    }

    Rectangle {
        id: toastBox
        property string toastType: "info"
        property string toastTitle: "Информация"
        property bool shown: false
        property real lifeProgress: 1

        width: Math.min(420, window.width - 48)
        height: Math.max(72, toastContent.implicitHeight + 26)
        radius: 14
        color: toastType === "error" ? "#25191F" : toastType === "success" ? "#17241F" : "#1D1B28"
        border.width: 1
        border.color: toastType === "error" ? "#65313F" : toastType === "success" ? "#285744" : "#443A68"
        anchors.top: parent.top
        anchors.right: parent.right
        anchors.topMargin: shown ? 96 : 78
        anchors.rightMargin: 24
        opacity: shown ? 1 : 0
        scale: shown ? 1 : 0.97
        visible: opacity > 0.01
        clip: true
        z: 1000

        Behavior on anchors.topMargin { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }
        Behavior on opacity { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
        Behavior on scale { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }

        RowLayout {
            id: toastContent
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.margins: 13
            spacing: 11

            Rectangle {
                Layout.preferredWidth: 34
                Layout.preferredHeight: 34
                Layout.alignment: Qt.AlignTop
                radius: 10
                color: toastBox.toastType === "error"
                       ? "#3B2029"
                       : toastBox.toastType === "success"
                         ? "#193B30"
                         : "#30284D"

                Text {
                    anchors.centerIn: parent
                    text: toastBox.toastType === "error" ? "!" : toastBox.toastType === "success" ? "✓" : "i"
                    color: toastBox.toastType === "error" ? "#FF8792" : toastBox.toastType === "success" ? "#55D6A3" : "#A994FF"
                    font.pixelSize: 16
                    font.weight: Font.Bold
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                Layout.alignment: Qt.AlignVCenter
                spacing: 3

                Text {
                    Layout.fillWidth: true
                    text: toastBox.toastTitle
                    color: "#F4F1FA"
                    font.pixelSize: 13
                    font.weight: Font.DemiBold
                }

                Text {
                    id: toastMessage
                    Layout.fillWidth: true
                    color: "#B5B0C2"
                    font.pixelSize: 12
                    lineHeight: 1.15
                    wrapMode: Text.WordWrap
                }
            }

            Rectangle {
                id: toastCloseButton
                Layout.preferredWidth: 30
                Layout.preferredHeight: 30
                Layout.alignment: Qt.AlignTop
                radius: 8
                color: toastCloseMouse.containsMouse ? "#302D3A" : "transparent"

                Text {
                    anchors.centerIn: parent
                    text: "×"
                    color: toastCloseMouse.containsMouse ? "#F0EDF6" : "#898396"
                    font.pixelSize: 19
                    font.weight: Font.Medium
                }

                MouseArea {
                    id: toastCloseMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: window.hideToast()
                }
            }
        }

        Rectangle {
            anchors.left: parent.left
            anchors.bottom: parent.bottom
            anchors.leftMargin: 14
            anchors.bottomMargin: 3
            width: Math.max(0, (parent.width - 28) * toastBox.lifeProgress)
            height: 2
            radius: 1
            color: toastBox.toastType === "error" ? "#FF6F7D" : toastBox.toastType === "success" ? "#45C995" : "#8E73FF"
            opacity: 0.75
        }
    }

    NumberAnimation {
        id: toastLifeAnimation
        target: toastBox
        property: "lifeProgress"
        from: 1
        to: 0
        duration: toastTimer.interval
    }

    Timer {
        id: toastTimer
        interval: 3600
        onTriggered: window.hideToast()
    }
}
