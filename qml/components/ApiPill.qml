import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

Rectangle {
    id: root

    function l(ru, en, uk) {
        return backend.uiLanguage === "en" ? en : backend.uiLanguage === "uk" ? uk : ru
    }

    property string label: ""
    property string value: "—"
    property var copyValue: value
    property bool canReveal: false
    property bool revealed: true

    signal copyRequested(var copiedValue)
    signal revealToggled()

    Layout.fillHeight: true
    radius: 12
    color: "#111016"
    border.width: 1
    border.color: "#292733"

    RowLayout {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        anchors.leftMargin: 10
        anchors.rightMargin: 10
        height: 28
        spacing: 8

        Text {
            Layout.alignment: Qt.AlignVCenter
            text: root.label
            color: "#777582"
            font.pixelSize: 11
            font.weight: Font.DemiBold
            height: 28
            verticalAlignment: Text.AlignVCenter
        }

        Text {
            Layout.fillWidth: true
            Layout.alignment: Qt.AlignVCenter
            text: root.value && root.value.length ? root.value : "—"
            color: "#E8E5EF"
            font.pixelSize: 13
            font.family: "Consolas"
            height: 28
            verticalAlignment: Text.AlignVCenter
            elide: Text.ElideRight
        }

        ToolButton {
            visible: root.canReveal
            implicitWidth: 28
            implicitHeight: 28
            text: root.revealed ? "\uED1A" : "\uE890"
            ToolTip.visible: hovered
            ToolTip.text: root.revealed
                          ? root.l("Скрыть", "Hide", "Сховати")
                          : root.l("Показать", "Show", "Показати")
            onClicked: root.revealToggled()

            contentItem: Text {
                text: parent.text
                color: "#AFA8C8"
                font.family: "Segoe MDL2 Assets"
                font.pixelSize: 14
                horizontalAlignment: Text.AlignHCenter
                verticalAlignment: Text.AlignVCenter
            }

            background: Rectangle {
                radius: 8
                width: 28
                height: 28
                anchors.centerIn: parent
                color: parent.hovered ? "#2B2935" : "transparent"
            }
        }

        ToolButton {
            implicitWidth: 28
            implicitHeight: 28
            text: "⧉"
            onClicked: root.copyRequested(root.copyValue)

            contentItem: Text {
                text: parent.text
                color: "#AFA8C8"
                font.pixelSize: 14
                horizontalAlignment: Text.AlignHCenter
                verticalAlignment: Text.AlignVCenter
            }

            background: Rectangle {
                radius: 8
                width: 28
                height: 28
                anchors.centerIn: parent
                color: parent.hovered ? "#2B2935" : "transparent"
            }
        }
    }
}
