import QtQuick
import QtQuick.Controls

Button {
    id: control
    property string symbol: ""
    property string symbolFontFamily: "Segoe MDL2 Assets"
    property bool selected: false

    implicitWidth: 196
    implicitHeight: 48
    hoverEnabled: true

    contentItem: Row {
        anchors.left: parent.left
        anchors.leftMargin: 15
        anchors.verticalCenter: parent.verticalCenter
        spacing: 13
        Text {
            text: control.symbol
            color: control.selected ? "#A996FF" : "#8F8D9C"
            font.family: control.symbolFontFamily
            font.pixelSize: 18
            width: 22
            horizontalAlignment: Text.AlignHCenter
            anchors.verticalCenter: parent.verticalCenter
        }
        Text {
            text: control.text
            color: control.selected ? "#F6F5FA" : "#AAA8B4"
            font.pixelSize: 14
            font.weight: control.selected ? Font.DemiBold : Font.Medium
            anchors.verticalCenter: parent.verticalCenter
        }
    }

    background: Rectangle {
        radius: 12
        color: control.selected ? "#2D2842" : control.hovered ? "#24232C" : "transparent"
        Rectangle {
            visible: control.selected
            width: 3
            height: 22
            radius: 2
            color: "#8A70FF"
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
        }
        Behavior on color { ColorAnimation { duration: 130 } }
    }
}
