/*
 * SPDX-FileCopyrightText: 2026 Antigravity
 * SPDX-License-Identifier: GPL-2.0-or-later
 */

import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC2
import org.kde.kirigami as Kirigami
import org.kde.kcmutils as KCMUtils

Kirigami.ScrollablePage {
    id: root

    title: i18n("Multiseat Workstation Status")

    actions: [
        Kirigami.Action {
            text: i18n("Refresh")
            icon.name: "view-refresh"
            onTriggered: kcm.refresh()
        }
    ]

    ColumnLayout {
        spacing: Kirigami.Units.largeSpacing
        width: root.width
        Layout.fillWidth: true

        // 1. Top Overview Banner
        Kirigami.AbstractCard {
            Layout.fillWidth: true

            contentItem: RowLayout {
                spacing: Kirigami.Units.largeSpacing

                Kirigami.Icon {
                    source: "preferences-desktop-display"
                    implicitWidth: Kirigami.Units.iconSizes.huge
                    implicitHeight: Kirigami.Units.iconSizes.huge
                    Layout.alignment: Qt.AlignVCenter
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: Kirigami.Units.smallSpacing / 2
                    Layout.alignment: Qt.AlignVCenter

                    RowLayout {
                        spacing: Kirigami.Units.mediumSpacing

                        Kirigami.Heading {
                            text: i18n("Multiseat Hardware Isolation")
                            level: 2
                        }

                        Rectangle {
                            radius: 4
                            color: Kirigami.Theme.positiveBackgroundColor
                            implicitHeight: Kirigami.Units.gridUnit * 1.3
                            implicitWidth: statusText.implicitWidth + Kirigami.Units.mediumSpacing * 2
                            border.color: Kirigami.Theme.positiveTextColor

                            QQC2.Label {
                                id: statusText
                                anchors.centerIn: parent
                                text: i18n("Active • %1 Seats Online", kcm.seats.length)
                                color: Kirigami.Theme.positiveTextColor
                                font.bold: true
                                font.pointSize: Kirigami.Theme.smallFont.pointSize
                            }
                        }
                    }

                    QQC2.Label {
                        text: i18n("Hardware-isolated multi-user workstation managed by systemd-logind, DRM/KMS, and Wayland.")
                        color: Kirigami.Theme.disabledTextColor
                        wrapMode: Text.WordWrap
                        Layout.fillWidth: true
                    }

                    QQC2.Label {
                        text: i18n("Last refreshed: %1", kcm.lastUpdated)
                        font.pointSize: Kirigami.Theme.smallFont.pointSize
                        color: Kirigami.Theme.disabledTextColor
                    }
                }
            }
        }

        // 2. Individual Seat Cards (Unified Full-Width Property Sections)
        Repeater {
            model: kcm.seats

            delegate: Kirigami.AbstractCard {
                id: seatCard
                required property var modelData
                Layout.fillWidth: true

                header: RowLayout {
                    spacing: Kirigami.Units.mediumSpacing

                    Kirigami.Icon {
                        source: modelData.isSeat0 ? "computer" : "computer-symbolic"
                        implicitWidth: Kirigami.Units.iconSizes.medium
                        implicitHeight: Kirigami.Units.iconSizes.medium
                    }

                    Kirigami.Heading {
                        text: modelData.name.toUpperCase() + (modelData.isSeat0 ? i18n(" — Primary Station") : i18n(" — Secondary Station"))
                        level: 3
                        Layout.fillWidth: true
                    }

                    Rectangle {
                        radius: 4
                        color: modelData.hasActiveSession ? Kirigami.Theme.positiveBackgroundColor : Kirigami.Theme.neutralBackgroundColor
                        implicitHeight: Kirigami.Units.gridUnit * 1.3
                        implicitWidth: sessBadge.implicitWidth + Kirigami.Units.mediumSpacing * 2
                        border.color: modelData.hasActiveSession ? Kirigami.Theme.positiveTextColor : Kirigami.Theme.disabledTextColor

                        RowLayout {
                            id: sessBadge
                            anchors.centerIn: parent
                            spacing: 6

                            Kirigami.Icon {
                                source: modelData.hasActiveSession ? "user-identity" : "system-lock-screen"
                                implicitWidth: Kirigami.Units.iconSizes.small
                                implicitHeight: Kirigami.Units.iconSizes.small
                            }

                            QQC2.Label {
                                text: modelData.hasActiveSession ? i18n("Logged in: %1 (%2)", modelData.primaryUser, modelData.sessionType.toUpperCase()) : i18n("At Login Screen")
                                color: modelData.hasActiveSession ? Kirigami.Theme.positiveTextColor : Kirigami.Theme.neutralTextColor
                                font.bold: true
                                font.pointSize: Kirigami.Theme.smallFont.pointSize
                            }
                        }
                    }
                }

                contentItem: ColumnLayout {
                    spacing: Kirigami.Units.largeSpacing
                    Layout.fillWidth: true

                    // --- SECTION 1: Display & Graphics ---
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: Kirigami.Units.smallSpacing

                        RowLayout {
                            spacing: Kirigami.Units.smallSpacing
                            Kirigami.Icon {
                                source: "video-display"
                                implicitWidth: Kirigami.Units.iconSizes.smallMedium
                                implicitHeight: Kirigami.Units.iconSizes.smallMedium
                            }
                            Kirigami.Heading {
                                text: i18n("Display & Graphics Engine")
                                level: 4
                            }
                        }

                        Kirigami.Separator {
                            Layout.fillWidth: true
                        }

                        GridLayout {
                            columns: 2
                            columnSpacing: Kirigami.Units.largeSpacing
                            rowSpacing: Kirigami.Units.smallSpacing
                            Layout.fillWidth: true

                            // GPU Model
                            QQC2.Label {
                                text: i18n("GPU Model:")
                                font.bold: true
                                color: Kirigami.Theme.disabledTextColor
                                Layout.preferredWidth: Kirigami.Units.gridUnit * 7
                                horizontalAlignment: Text.AlignRight
                            }
                            QQC2.Label {
                                text: modelData.gpuName
                                font.bold: true
                                wrapMode: Text.WordWrap
                                Layout.fillWidth: true
                            }

                            // Driver & Node
                            QQC2.Label {
                                text: i18n("Kernel Driver:")
                                font.bold: true
                                color: Kirigami.Theme.disabledTextColor
                                Layout.preferredWidth: Kirigami.Units.gridUnit * 7
                                horizontalAlignment: Text.AlignRight
                            }
                            QQC2.Label {
                                text: modelData.driver + " • " + modelData.drmCard + (modelData.pciAddr ? " @ " + modelData.pciAddr : "")
                                font.family: "monospace"
                                font.pointSize: Kirigami.Theme.smallFont.pointSize
                                color: Kirigami.Theme.disabledTextColor
                                Layout.fillWidth: true
                            }

                            // Displays
                            QQC2.Label {
                                text: i18n("Active Displays:")
                                font.bold: true
                                color: Kirigami.Theme.disabledTextColor
                                Layout.preferredWidth: Kirigami.Units.gridUnit * 7
                                horizontalAlignment: Text.AlignRight
                                Layout.alignment: Qt.AlignTop
                            }
                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 4

                                Repeater {
                                    model: modelData.displays
                                    delegate: RowLayout {
                                        spacing: Kirigami.Units.smallSpacing
                                        Kirigami.Icon {
                                            source: "video-television"
                                            implicitWidth: Kirigami.Units.iconSizes.small
                                            implicitHeight: Kirigami.Units.iconSizes.small
                                        }
                                        QQC2.Label {
                                            text: modelData.port + " • " + modelData.monitor + " (" + modelData.mode + ")"
                                            font.bold: true
                                        }
                                    }
                                }
                            }
                        }
                    }

                    // --- SECTION 2: USB Hardware & Audio ---
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: Kirigami.Units.smallSpacing

                        RowLayout {
                            spacing: Kirigami.Units.smallSpacing
                            Kirigami.Icon {
                                source: "input-mouse"
                                implicitWidth: Kirigami.Units.iconSizes.smallMedium
                                implicitHeight: Kirigami.Units.iconSizes.smallMedium
                            }
                            Kirigami.Heading {
                                text: i18n("USB Hardware & Audio")
                                level: 4
                            }
                        }

                        Kirigami.Separator {
                            Layout.fillWidth: true
                        }

                        GridLayout {
                            columns: 2
                            columnSpacing: Kirigami.Units.largeSpacing
                            rowSpacing: Kirigami.Units.smallSpacing
                            Layout.fillWidth: true

                            // USB Ports
                            QQC2.Label {
                                text: i18n("USB Ports:")
                                font.bold: true
                                color: Kirigami.Theme.disabledTextColor
                                Layout.preferredWidth: Kirigami.Units.gridUnit * 7
                                horizontalAlignment: Text.AlignRight
                            }
                            QQC2.Label {
                                text: modelData.usbTopology
                                font.bold: true
                                color: Kirigami.Theme.highlightColor
                                wrapMode: Text.WordWrap
                                Layout.fillWidth: true
                            }

                            // Input Devices
                            QQC2.Label {
                                text: i18n("Input Devices:")
                                font.bold: true
                                color: Kirigami.Theme.disabledTextColor
                                Layout.preferredWidth: Kirigami.Units.gridUnit * 7
                                horizontalAlignment: Text.AlignRight
                                Layout.alignment: Qt.AlignTop
                            }
                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 4

                                Repeater {
                                    model: modelData.inputDevices
                                    delegate: RowLayout {
                                        spacing: Kirigami.Units.smallSpacing
                                        Kirigami.Icon {
                                            source: modelData.indexOf("Keyboard") !== -1 ? "input-keyboard" : (modelData.indexOf("Mouse") !== -1 ? "input-mouse" : "input-gaming")
                                            implicitWidth: Kirigami.Units.iconSizes.small
                                            implicitHeight: Kirigami.Units.iconSizes.small
                                        }
                                        QQC2.Label {
                                            text: modelData
                                        }
                                    }
                                }
                            }

                            // Audio Output
                            QQC2.Label {
                                text: i18n("Audio Output:")
                                font.bold: true
                                color: Kirigami.Theme.disabledTextColor
                                Layout.preferredWidth: Kirigami.Units.gridUnit * 7
                                horizontalAlignment: Text.AlignRight
                            }
                            QQC2.Label {
                                text: modelData.audioSink
                                wrapMode: Text.WordWrap
                                Layout.fillWidth: true
                            }
                        }
                    }
                }
            }
        }

        // 3. Persistent Rules & Quick Diagnostics Card
        Kirigami.AbstractCard {
            Layout.fillWidth: true

            header: RowLayout {
                spacing: Kirigami.Units.mediumSpacing

                Kirigami.Icon {
                    source: "document-properties"
                    implicitWidth: Kirigami.Units.iconSizes.medium
                    implicitHeight: Kirigami.Units.iconSizes.medium
                }
                Kirigami.Heading {
                    text: i18n("Persistent Udev Seat Rules & Diagnostics")
                    level: 3
                    Layout.fillWidth: true
                }
            }

            contentItem: ColumnLayout {
                spacing: Kirigami.Units.mediumSpacing

                QQC2.Label {
                    text: i18n("Active udev rules in /etc/udev/rules.d/ ensuring hardware assignments persist across every reboot:")
                    color: Kirigami.Theme.disabledTextColor
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: Kirigami.Units.smallSpacing

                    Repeater {
                        model: kcm.rules

                        delegate: Rectangle {
                            required property var modelData
                            Layout.fillWidth: true
                            implicitHeight: ruleCol.implicitHeight + Kirigami.Units.mediumSpacing * 2
                            color: Kirigami.Theme.alternateBackgroundColor
                            radius: 6

                            RowLayout {
                                id: ruleCol
                                anchors.fill: parent
                                anchors.margins: Kirigami.Units.mediumSpacing
                                spacing: Kirigami.Units.mediumSpacing

                                Kirigami.Icon {
                                    source: "text-x-script"
                                    implicitWidth: Kirigami.Units.iconSizes.medium
                                    implicitHeight: Kirigami.Units.iconSizes.medium
                                }

                                ColumnLayout {
                                    Layout.fillWidth: true
                                    spacing: 4

                                    QQC2.Label {
                                        text: modelData.file
                                        font.bold: true
                                        font.family: "monospace"
                                    }
                                    QQC2.Label {
                                        text: modelData.content
                                        font.family: "monospace"
                                        color: Kirigami.Theme.highlightColor
                                        font.pointSize: Kirigami.Theme.smallFont.pointSize
                                        wrapMode: Text.WrapAnywhere
                                        Layout.fillWidth: true
                                    }
                                }
                            }
                        }
                    }
                }

                Kirigami.InlineMessage {
                    Layout.fillWidth: true
                    type: Kirigami.MessageType.Information
                    visible: true
                    text: i18n("Tip: To instantly revert to a single unified dual-monitor desktop at any time, run: sudo loginctl flush-devices")
                }
            }
        }
    }
}
