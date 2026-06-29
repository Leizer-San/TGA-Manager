import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

Rectangle {
    id: root

    property string currentLanguage: "ru"
    signal languageSelected(string language)

    implicitWidth: 158
    implicitHeight: 44
    radius: 14
    color: "#1D1B24"
    border.width: 1
    border.color: "#302E39"

    RowLayout {
        anchors.fill: parent
        anchors.margins: 3
        spacing: 2

        Repeater {
            model: [
                { code: "en", name: "English" },
                { code: "ru", name: "Русский" },
                { code: "uk", name: "Українська" }
            ]

            Button {
                id: languageButton
                Layout.fillWidth: true
                Layout.fillHeight: true
                hoverEnabled: true
                padding: 0
                ToolTip.visible: hovered
                ToolTip.text: modelData.name
                onClicked: root.languageSelected(modelData.code)

                contentItem: Item {
                    Rectangle {
                        id: flag
                        width: 24
                        height: 16
                        radius: 3
                        anchors.centerIn: parent
                        clip: true
                        color: modelData.code === "en" ? "#244A86"
                               : modelData.code === "ru" ? "#FFFFFF"
                               : "#2D7DD2"

                        // Compact UK-style cross for English.
                        Rectangle { visible: modelData.code === "en"; anchors.horizontalCenter: parent.horizontalCenter; width: 5; height: parent.height; color: "#FFFFFF" }
                        Rectangle { visible: modelData.code === "en"; anchors.verticalCenter: parent.verticalCenter; width: parent.width; height: 5; color: "#FFFFFF" }
                        Rectangle { visible: modelData.code === "en"; anchors.horizontalCenter: parent.horizontalCenter; width: 2; height: parent.height; color: "#E04A55" }
                        Rectangle { visible: modelData.code === "en"; anchors.verticalCenter: parent.verticalCenter; width: parent.width; height: 2; color: "#E04A55" }

                        // Russian tricolour.
                        Rectangle { visible: modelData.code === "ru"; x: 0; y: 0; width: parent.width; height: parent.height / 3; color: "#FFFFFF" }
                        Rectangle { visible: modelData.code === "ru"; x: 0; y: parent.height / 3; width: parent.width; height: parent.height / 3; color: "#3568C8" }
                        Rectangle { visible: modelData.code === "ru"; x: 0; y: parent.height * 2 / 3; width: parent.width; height: parent.height / 3; color: "#D84A54" }

                        // Ukrainian bicolour.
                        Rectangle { visible: modelData.code === "uk"; x: 0; y: 0; width: parent.width; height: parent.height / 2; color: "#2D7DD2" }
                        Rectangle { visible: modelData.code === "uk"; x: 0; y: parent.height / 2; width: parent.width; height: parent.height / 2; color: "#F3CB3E" }
                    }
                }

                background: Rectangle {
                    radius: 11
                    color: root.currentLanguage === modelData.code
                           ? "#322A50"
                           : languageButton.hovered ? "#292630" : "transparent"
                    border.width: root.currentLanguage === modelData.code ? 1 : 0
                    border.color: "#6652B4"
                    Behavior on color { ColorAnimation { duration: 120 } }
                }
            }
        }
    }
}
