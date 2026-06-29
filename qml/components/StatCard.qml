import QtQuick

Rectangle {
    id: root
    property string title: ""
    property string value: "0"
    property string subtitle: ""
    property color accent: "#7C5CFC"
    property string symbol: ""

    implicitHeight: 104
    radius: 18
    color: "#1C1B23"
    border.width: 1
    border.color: "#2B2A34"

    Rectangle {
        width: 46
        height: 46
        radius: 14
        color: Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.16)
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.margins: 16
        Text {
            anchors.centerIn: parent
            text: root.symbol
            color: root.accent
            font.pixelSize: 22
            font.weight: Font.DemiBold
        }
    }

    Column {
        anchors.left: parent.left
        anchors.leftMargin: 18
        anchors.verticalCenter: parent.verticalCenter
        spacing: 4
        Text { text: root.value; color: "#F4F3F8"; font.pixelSize: 28; font.weight: Font.Bold }
        Text { text: root.title; color: "#AAA8B4"; font.pixelSize: 13; font.weight: Font.Medium }
        Text { text: root.subtitle; color: "#676572"; font.pixelSize: 11; visible: text.length > 0 }
    }
}
