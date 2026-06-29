import QtQuick
import QtQuick.Controls

CheckBox {
    id: control
    spacing: 9
    implicitHeight: 34
    hoverEnabled: true

    indicator: Rectangle {
        implicitWidth: 19
        implicitHeight: 19
        x: control.leftPadding
        y: (control.height - height) / 2
        radius: 6
        color: control.checked ? "#7657F6" : control.hovered ? "#292733" : "#1B1A21"
        border.width: 1
        border.color: control.checked ? "#8D74FF" : "#45424F"
        Behavior on color { ColorAnimation { duration: 120 } }

        Text {
            anchors.centerIn: parent
            text: "✓"
            visible: control.checked
            color: "white"
            font.pixelSize: 12
            font.weight: Font.Bold
        }
    }

    contentItem: Text {
        text: control.text
        color: control.enabled ? "#AAA8B4" : "#656370"
        font.pixelSize: 12
        verticalAlignment: Text.AlignVCenter
        leftPadding: control.indicator.width + control.spacing
    }
}

