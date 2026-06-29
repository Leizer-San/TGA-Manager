import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

Rectangle {
    id: root

    property string title: ""
    property string value: "—"
    property var copyValue: value
    property bool copyable: true
    property bool highlighted: false

    signal copyRequested(var copiedValue)

    Layout.fillWidth: true
    implicitHeight: 58
    radius: 12
    color: "#111016"
    border.width: 1
    border.color: highlighted ? "#41356A" : "#292733"

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 9
        spacing: 2

        Text {
            text: root.title
            color: "#777582"
            font.pixelSize: 10
            font.weight: Font.DemiBold
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: 4

            Text {
                Layout.fillWidth: true
                text: root.value && root.value.length ? root.value : "—"
                color: root.highlighted ? "#BDAEFF" : "#E8E5EF"
                font.pixelSize: 12
                font.weight: root.highlighted ? Font.DemiBold : Font.Normal
                elide: Text.ElideRight
            }

            ToolButton {
                visible: root.copyable
                implicitWidth: 24
                implicitHeight: 24
                text: "⧉"
                onClicked: root.copyRequested(root.copyValue)

                contentItem: Text {
                    text: parent.text
                    color: "#AFA8C8"
                    font.pixelSize: 13
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                }

                background: Rectangle {
                    radius: 8
                    color: parent.hovered ? "#2B2935" : "transparent"
                }
            }
        }
    }
}
