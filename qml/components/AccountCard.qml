import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Qt5Compat.GraphicalEffects

Rectangle {
    id: root
    property string accountId: ""
    property string accountName: ""
    property string phone: ""
    property string username: ""
    property string telegramUserId: ""
    property int dcId: 0
    property string initials: "TG"
    property string avatarSource: ""
    property string accentColor: "#7657F6"
    property bool favorite: false
    property bool running: false
    property bool pathValid: false
    property bool authorized: false
    property bool premium: false
    property bool busy: false
    property string lastLaunched: ""
    property string language: "ru"

    function l(ru, en, uk) {
        return root.language === "en" ? en : root.language === "uk" ? uk : ru
    }

    signal launchRequested(string accountId)
    signal stopRequested(string accountId)
    signal refreshRequested(string accountId)
    signal infoRequested(string accountId)
    signal editRequested(string accountId)
    signal deleteRequested(string accountId, string accountName)
    signal favoriteRequested(string accountId)
    signal folderRequested(string accountId)

    function lastLaunchText() {
        if (!root.lastLaunched.length)
            return root.l("Не запускался", "Never launched", "Не запускався")
        const date = new Date(root.lastLaunched)
        if (isNaN(date.getTime()))
            return root.lastLaunched
        return Qt.formatDateTime(date, "dd.MM.yyyy HH:mm")
    }

    implicitHeight: 224
    radius: 18
    color: mouse.containsMouse ? "#211F29" : "#1C1B23"
    border.width: 1
    border.color: mouse.containsMouse ? "#3A3748" : "#2B2A34"
    scale: mouse.pressed ? 0.99 : 1
    Behavior on color { ColorAnimation { duration: 130 } }
    Behavior on border.color { ColorAnimation { duration: 130 } }
    Behavior on scale { NumberAnimation { duration: 90 } }

    Rectangle {
        width: parent.width * 0.48
        height: 4
        radius: 2
        color: root.accentColor
        opacity: 0.95
        anchors.top: parent.top
        anchors.horizontalCenter: parent.horizontalCenter
    }

    MouseArea {
        id: mouse
        anchors.fill: parent
        hoverEnabled: true
        acceptedButtons: Qt.NoButton
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 18
        spacing: 13

        RowLayout {
            Layout.fillWidth: true
            spacing: 12
            Rectangle {
                width: 52; height: 52; radius: 17
                color: root.accentColor
                border.width: 2
                border.color: root.accentColor

                Rectangle {
                    id: avatarClipMask
                    anchors.fill: avatarContent
                    radius: 14
                    visible: false
                }

                Item {
                    id: avatarContent
                    anchors.fill: parent
                    anchors.margins: 3
                    layer.enabled: true
                    layer.effect: OpacityMask { maskSource: avatarClipMask }

                    Rectangle { anchors.fill: parent; color: root.accentColor }

                    Image {
                        id: avatarImage
                        anchors.fill: parent
                        source: root.avatarSource
                        visible: root.avatarSource.length > 0 && status !== Image.Error
                        fillMode: Image.PreserveAspectCrop
                        asynchronous: true
                        cache: false
                    }
                    Text {
                        anchors.centerIn: parent
                        visible: !avatarImage.visible
                        text: root.initials
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
                    text: root.accountName
                    color: "#F3F2F7"
                    font.pixelSize: 16
                    font.weight: Font.DemiBold
                    elide: Text.ElideRight
                }
                Text {
                    text: root.username.length
                          ? "@" + root.username + (root.phone.length ? "  ·  +" + root.phone.replace(/^\+/, "") : "")
                          : root.phone.length ? "+" + root.phone.replace(/^\+/, "") : root.l("Телефон не указан", "Phone not specified", "Телефон не вказано")
                    color: "#777582"
                    font.pixelSize: 12
                }
                Text {
                    Layout.fillWidth: true
                    text: root.l("Последний запуск: ", "Last launch: ", "Останній запуск: ") + root.lastLaunchText()
                    color: "#5F5D69"
                    font.pixelSize: 10
                    elide: Text.ElideRight
                    ToolTip.visible: lastLaunchMouse.containsMouse
                    ToolTip.text: root.lastLaunched.length ? root.l("Последний запуск Telegram для этого профиля", "Last Telegram launch for this profile", "Останній запуск Telegram для цього профілю") : root.l("Этот профиль ещё не запускался", "This profile has not been launched yet", "Цей профіль ще не запускався")
                    MouseArea { id: lastLaunchMouse; anchors.fill: parent; hoverEnabled: true; acceptedButtons: Qt.NoButton }
                }
            }
            ToolButton {
                text: root.favorite ? "★" : "☆"
                Layout.alignment: Qt.AlignTop | Qt.AlignRight
                Layout.topMargin: -2
                Layout.rightMargin: -5
                implicitWidth: 28
                implicitHeight: 28
                onClicked: root.favoriteRequested(root.accountId)
                contentItem: Text {
                    text: parent.text
                    color: root.favorite || parent.hovered ? "#F8C85C" : "#777582"
                    font.pixelSize: 20
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                }
                background: Item {}
            }
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: 7
            Rectangle {
                implicitWidth: statusContent.implicitWidth + 16
                Layout.preferredWidth: implicitWidth
                Layout.minimumWidth: implicitWidth
                Layout.preferredHeight: 26
                radius: 8
                color: root.running || root.authorized ? "#17352C" : root.pathValid ? "#24232C" : "#3A252A"

                RowLayout {
                    id: statusContent
                    anchors.centerIn: parent
                    spacing: 5
                    Text {
                        text: root.running ? "●" : root.authorized ? "✓" : root.pathValid ? "●" : "!"
                        color: root.running || root.authorized ? "#63D6A5" : root.pathValid ? "#9B99A7" : "#FF8D95"
                        font.pixelSize: 11
                        font.weight: Font.Bold
                    }
                    Text {
                        text: root.running ? root.l("Запущен", "Running", "Запущено") : root.authorized ? root.l("Авторизован", "Authorized", "Авторизовано") : root.pathValid ? root.l("Готов", "Ready", "Готово") : root.l("Проверьте tdata", "Check tdata", "Перевірте tdata")
                        color: root.running || root.authorized ? "#63D6A5" : root.pathValid ? "#9B99A7" : "#FF8D95"
                        font.pixelSize: 11
                        font.weight: Font.DemiBold
                    }
                }
            }
            Rectangle {
                visible: root.premium
                implicitWidth: premiumText.implicitWidth + 16
                Layout.preferredWidth: visible ? implicitWidth : 0
                Layout.minimumWidth: visible ? implicitWidth : 0
                Layout.preferredHeight: 26
                radius: 8
                color: "#302649"
                Text { id: premiumText; anchors.centerIn: parent; text: "★ Premium"; color: "#BDAEFF"; font.pixelSize: 10; font.weight: Font.DemiBold }
            }
            Item { Layout.fillWidth: true }
            Text {
                Layout.alignment: Qt.AlignVCenter
                text: root.authorized
                      ? "ID " + root.telegramUserId + (root.dcId ? "  ·  DC " + root.dcId : "")
                      : root.lastLaunched.length ? root.l("Был запущен ранее", "Previously launched", "Запускався раніше") : root.l("Ещё не запускался", "Never launched", "Ще не запускався")
                color: "#5F5D69"
                font.pixelSize: 11
            }
        }

        Rectangle { Layout.fillWidth: true; height: 1; color: "#2A2932" }

        RowLayout {
            Layout.fillWidth: true
            spacing: 8

            Button {
                Layout.fillWidth: true
                implicitHeight: 40
                text: root.running ? root.l("Закрыть", "Stop", "Закрити") : root.l("Запустить", "Launch", "Запустити")
                onClicked: root.running ? root.stopRequested(root.accountId) : root.launchRequested(root.accountId)
                contentItem: Text {
                    text: parent.text
                    color: "white"
                    font.pixelSize: 13; font.weight: Font.DemiBold
                    horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter
                }
                background: Rectangle {
                    radius: 12
                    color: root.running
                           ? (parent.hovered ? "#B94C5B" : "#9E3F4D")
                           : (parent.hovered ? "#866AFF" : "#7657F6")
                    Behavior on color { ColorAnimation { duration: 120 } }
                }
            }

            Repeater {
                model: [
                    { icon: "\uE72C", fallback: "↻", tip: root.l("Обновить данные и .session", "Refresh data and .session", "Оновити дані та .session") },
                    { icon: "\uE946", fallback: "i", tip: root.l("Информация об аккаунте", "Account information", "Інформація про акаунт") },
                    { icon: "\uE838", fallback: "▣", tip: root.l("Открыть папку профиля", "Open profile folder", "Відкрити папку профілю") },
                    { icon: "\uE70F", fallback: "✎", tip: root.l("Редактировать", "Edit", "Редагувати") },
                    { icon: "\uE74D", fallback: "×", tip: root.l("Удалить", "Delete", "Видалити") }
                ]
                ToolButton {
                    implicitWidth: 38
                    implicitHeight: 40
                    enabled: index === 0 ? (!root.running && !root.busy && root.pathValid)
                             : index === 4 ? !root.running
                             : true
                    ToolTip.visible: hovered
                    ToolTip.text: index === 0 && root.running ? root.l("Сначала закройте Telegram", "Close Telegram first", "Спочатку закрийте Telegram") : modelData.tip
                    onClicked: {
                        if (index === 0) root.refreshRequested(root.accountId)
                        else if (index === 1) root.infoRequested(root.accountId)
                        else if (index === 2) root.folderRequested(root.accountId)
                        else if (index === 3) root.editRequested(root.accountId)
                        else root.deleteRequested(root.accountId, root.accountName)
                    }
                    contentItem: Text {
                        text: modelData.icon
                        color: !parent.enabled ? "#55535F" : index === 4 ? "#FF858D" : "#BDB8D0"
                        font.family: "Segoe MDL2 Assets"
                        font.pixelSize: 15
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                    }
                    background: Rectangle {
                        radius: 12
                        color: parent.enabled
                               ? parent.hovered
                                 ? (index === 4 ? "#34232A" : "#302E39")
                                 : "#26252E"
                               : "#22212A"
                        border.width: 1
                        border.color: parent.enabled
                                      ? parent.hovered
                                        ? (index === 4 ? "#57313A" : "#454151")
                                        : "#33313B"
                                      : "#2B2933"
                        Behavior on color { ColorAnimation { duration: 120 } }
                    }
                }
            }
        }
    }
}
