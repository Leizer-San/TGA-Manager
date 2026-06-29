import QtQuick
import QtQuick.Controls

Button {
    id: control
    property string tone: "primary"
    property string leadingText: ""

    implicitHeight: 44
    implicitWidth: Math.max(112, contentItem.implicitWidth + 34)
    hoverEnabled: true

    contentItem: Item {
        implicitWidth: buttonContent.implicitWidth
        implicitHeight: 22

        Row {
            id: buttonContent
            spacing: 9
            anchors.centerIn: parent

            Text {
                visible: control.leadingText.length > 0
                text: control.leadingText
                color: control.tone === "primary" ? "#FFFFFF" : "#C8C7D3"
                font.pixelSize: 17
                height: 22
                horizontalAlignment: Text.AlignHCenter
                verticalAlignment: Text.AlignVCenter
            }

            Text {
                text: control.text
                color: control.tone === "primary" ? "#FFFFFF" :
                       control.tone === "danger" ? "#FF858D" : "#E9E8F0"
                font.pixelSize: 14
                font.weight: Font.DemiBold
                height: 22
                verticalAlignment: Text.AlignVCenter
            }
        }
    }

    background: Rectangle {
        radius: 12
        color: {
            if (!control.enabled) return "#24232C"
            if (control.tone === "primary") return control.down ? "#6544E7" : control.hovered ? "#886CFF" : "#7657F6"
            if (control.tone === "danger") return control.hovered ? "#3A252C" : "#2A2026"
            return control.hovered ? "#302F3A" : "#292832"
        }
        border.width: control.tone === "primary" ? 0 : 1
        border.color: control.tone === "danger" ? "#523039" : "#3A3945"
        Behavior on color { ColorAnimation { duration: 130 } }
    }
}
