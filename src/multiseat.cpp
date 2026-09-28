/*
 * SPDX-FileCopyrightText: 2026 Antigravity
 * SPDX-License-Identifier: GPL-2.0-or-later
 */

#include "multiseat.h"

#include <KPluginFactory>
#include <QProcess>
#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QTextStream>
#include <QRegularExpression>
#include <QSet>
#include <QDebug>

K_PLUGIN_CLASS_WITH_JSON(KCMultiseat, "kcm_multiseat.json")

// Helper: Dynamically query lspci for human-readable device name
static QString getPciDeviceDescription(const QString &pciAddr)
{
    if (pciAddr.isEmpty()) return QString();

    QProcess proc;
    proc.start(QStringLiteral("lspci"), {QStringLiteral("-s"), pciAddr});
    proc.waitForFinished(1000);
    QString out = QString::fromUtf8(proc.readAllStandardOutput()).trimmed();
    
    // Output format: "03:00.0 VGA compatible controller: Advanced Micro Devices, Inc. ..."
    int firstColon = out.indexOf(QLatin1Char(':'));
    if (firstColon != -1) {
        int secondColon = out.indexOf(QLatin1Char(':'), firstColon + 1);
        if (secondColon != -1) {
            return out.mid(secondColon + 1).trimmed();
        }
    }
    return out;
}

// Helper: Dynamically parse monitor model name from 128-byte VESA EDID block
static QString parseEdidMonitorName(const QString &edidPath)
{
    QFile file(edidPath);
    if (!file.open(QIODevice::ReadOnly)) {
        return QString();
    }
    QByteArray data = file.readAll();
    file.close();

    // VESA EDID 1.3/1.4 descriptor blocks at offsets 54, 72, 90, 108
    const int offsets[] = {54, 72, 90, 108};
    for (int offset : offsets) {
        if (data.size() >= offset + 18) {
            // Tag 0x00, 0x00, 0x00, 0xFC = Monitor Name
            if (data.at(offset) == 0 && data.at(offset + 1) == 0 &&
                data.at(offset + 2) == 0 && static_cast<unsigned char>(data.at(offset + 3)) == 0xFC) {
                QByteArray nameBytes = data.mid(offset + 5, 13);
                QString name = QString::fromLatin1(nameBytes).trimmed();
                // Strip trailing newlines or control chars
                name.remove(QLatin1Char('\n'));
                name.remove(QLatin1Char('\r'));
                if (!name.isEmpty()) {
                    return name;
                }
            }
        }
    }
    return QString();
}

KCMultiseat::KCMultiseat(QObject *parent, const KPluginMetaData &metaData)
    : KQuickConfigModule(parent, metaData)
{
    refresh();
}

void KCMultiseat::refresh()
{
    m_isLoading = true;
    Q_EMIT isLoadingChanged();

    collectSeatData();
    collectRulesData();

    m_lastUpdated = QDateTime::currentDateTime().toString(QStringLiteral("HH:mm:ss"));
    Q_EMIT lastUpdatedChanged();

    m_isLoading = false;
    Q_EMIT isLoadingChanged();
}

void KCMultiseat::collectSeatData()
{
    m_seats.clear();

    // 1. Get list of seats
    QProcess listSeatsProc;
    listSeatsProc.start(QStringLiteral("loginctl"), {QStringLiteral("list-seats"), QStringLiteral("--no-legend")});
    listSeatsProc.waitForFinished(2000);
    QString seatsOutput = QString::fromUtf8(listSeatsProc.readAllStandardOutput()).trimmed();
    QStringList seatNames = seatsOutput.split(QLatin1Char('\n'), Qt::SkipEmptyParts);

    // 2. Get all sessions
    QProcess listSessionsProc;
    listSessionsProc.start(QStringLiteral("loginctl"), {QStringLiteral("list-sessions"), QStringLiteral("--no-legend")});
    listSessionsProc.waitForFinished(2000);
    QString sessionsOutput = QString::fromUtf8(listSessionsProc.readAllStandardOutput()).trimmed();
    QStringList sessionLines = sessionsOutput.split(QLatin1Char('\n'), Qt::SkipEmptyParts);

    QMap<QString, QVariantList> seatSessions;
    for (const QString &line : sessionLines) {
        QStringList parts = line.simplified().split(QLatin1Char(' '));
        if (parts.size() >= 4) {
            QString sessId = parts.at(0);
            QString uid = parts.at(1);
            QString user = parts.at(2);
            QString seat = parts.at(3);
            
            QVariantMap sessMap;
            sessMap[QStringLiteral("id")] = sessId;
            sessMap[QStringLiteral("uid")] = uid;
            sessMap[QStringLiteral("user")] = user;
            sessMap[QStringLiteral("seat")] = seat;

            QProcess sessTypeProc;
            sessTypeProc.start(QStringLiteral("loginctl"), {QStringLiteral("show-session"), sessId, QStringLiteral("-p"), QStringLiteral("Type"), QStringLiteral("-p"), QStringLiteral("State"), QStringLiteral("-p"), QStringLiteral("Class")});
            sessTypeProc.waitForFinished(1000);
            QString propsOutput = QString::fromUtf8(sessTypeProc.readAllStandardOutput());
            for (const QString &prop : propsOutput.split(QLatin1Char('\n'), Qt::SkipEmptyParts)) {
                if (prop.startsWith(QStringLiteral("Type="))) {
                    sessMap[QStringLiteral("type")] = prop.mid(5);
                } else if (prop.startsWith(QStringLiteral("State="))) {
                    sessMap[QStringLiteral("state")] = prop.mid(6);
                } else if (prop.startsWith(QStringLiteral("Class="))) {
                    sessMap[QStringLiteral("class")] = prop.mid(6);
                }
            }
            if (seat != QStringLiteral("-")) {
                seatSessions[seat].append(sessMap);
            }
        }
    }

    // 3. Dynamic DRM outputs map (card -> list of connected outputs)
    QMap<QString, QVariantList> cardOutputs;
    QDir drmDir(QStringLiteral("/sys/class/drm"));
    const QStringList connectors = drmDir.entryList({QStringLiteral("card*-*")}, QDir::Dirs);
    for (const QString &conn : connectors) {
        QString statusPath = QStringLiteral("/sys/class/drm/%1/status").arg(conn);
        QFile statusFile(statusPath);
        if (statusFile.open(QIODevice::ReadOnly | QIODevice::Text)) {
            QString status = QString::fromUtf8(statusFile.readAll()).trimmed();
            if (status == QStringLiteral("connected")) {
                QString card = conn.section(QLatin1Char('-'), 0, 0);
                QString portName = conn.section(QLatin1Char('-'), 1);

                QString modePath = QStringLiteral("/sys/class/drm/%1/modes").arg(conn);
                QFile modeFile(modePath);
                QString mode = QStringLiteral("Auto");
                if (modeFile.open(QIODevice::ReadOnly | QIODevice::Text)) {
                    mode = QString::fromUtf8(modeFile.readLine()).trimmed();
                }

                QString edidPath = QStringLiteral("/sys/class/drm/%1/edid").arg(conn);
                QString monitorName = parseEdidMonitorName(edidPath);
                if (monitorName.isEmpty()) {
                    monitorName = portName;
                }

                QVariantMap outMap;
                outMap[QStringLiteral("port")] = portName;
                outMap[QStringLiteral("mode")] = mode;
                outMap[QStringLiteral("monitor")] = monitorName;
                cardOutputs[card].append(outMap);
            }
        }
    }

    // 4. Process each seat dynamically
    for (const QString &seatNameRaw : seatNames) {
        QString seatName = seatNameRaw.trimmed();
        if (seatName.isEmpty()) continue;

        QProcess seatStatusProc;
        seatStatusProc.start(QStringLiteral("loginctl"), {QStringLiteral("seat-status"), seatName, QStringLiteral("--no-pager")});
        seatStatusProc.waitForFinished(2000);
        QString statusOut = QString::fromUtf8(seatStatusProc.readAllStandardOutput());

        QVariantMap seatData;
        seatData[QStringLiteral("name")] = seatName;
        seatData[QStringLiteral("isSeat0")] = (seatName == QStringLiteral("seat0"));

        // Sessions
        QVariantList sessions = seatSessions.value(seatName);
        seatData[QStringLiteral("sessions")] = sessions;
        seatData[QStringLiteral("hasActiveSession")] = !sessions.isEmpty();
        if (!sessions.isEmpty()) {
            QVariantMap firstSess = sessions.first().toMap();
            seatData[QStringLiteral("primaryUser")] = firstSess.value(QStringLiteral("user")).toString();
            seatData[QStringLiteral("sessionType")] = firstSess.value(QStringLiteral("type")).toString();
            seatData[QStringLiteral("sessionId")] = firstSess.value(QStringLiteral("id")).toString();
            seatData[QStringLiteral("sessionUid")] = firstSess.value(QStringLiteral("uid")).toString();
        } else {
            seatData[QStringLiteral("primaryUser")] = QStringLiteral("Greeter");
            seatData[QStringLiteral("sessionType")] = QStringLiteral("wayland");
            seatData[QStringLiteral("sessionId")] = QStringLiteral("-");
            seatData[QStringLiteral("sessionUid")] = QStringLiteral("-");
        }

        // Parse Master GPU dynamically from seat-status
        QString drmCard;
        QRegularExpression drmRegex(QString::fromUtf8(R"(\[MASTER\]\s+drm:(card\d+))"));
        QRegularExpressionMatch drmMatch = drmRegex.match(statusOut);
        if (drmMatch.hasMatch()) {
            drmCard = drmMatch.captured(1);
        } else {
            // fallback
            if (statusOut.contains(QStringLiteral("drm:card1"))) drmCard = QStringLiteral("card1");
            else if (statusOut.contains(QStringLiteral("drm:card0"))) drmCard = QStringLiteral("card0");
        }

        QString pciAddr;
        QString gpuName = QStringLiteral("Unknown Graphics Controller");
        QString driverName = QStringLiteral("Unknown");

        if (!drmCard.isEmpty()) {
            QString deviceLink = QStringLiteral("/sys/class/drm/%1/device").arg(drmCard);
            QString targetPath = QFileInfo(deviceLink).canonicalFilePath();
            if (!targetPath.isEmpty()) {
                pciAddr = QFileInfo(targetPath).fileName();
                if (pciAddr.startsWith(QStringLiteral("0000:"))) {
                    pciAddr = pciAddr.mid(5); // e.g. "03:00.0"
                }

                // Query lspci for human-readable description
                QString desc = getPciDeviceDescription(pciAddr);
                if (!desc.isEmpty()) {
                    gpuName = desc;
                }
            }

            // Read driver name
            QString driverTarget = QFileInfo(QStringLiteral("/sys/class/drm/%1/device/driver").arg(drmCard)).canonicalFilePath();
            if (!driverTarget.isEmpty()) {
                driverName = QFileInfo(driverTarget).fileName();
            }
        }

        seatData[QStringLiteral("gpuName")] = gpuName;
        seatData[QStringLiteral("drmCard")] = drmCard;
        seatData[QStringLiteral("pciAddr")] = pciAddr;
        seatData[QStringLiteral("driver")] = driverName;

        // Displays
        QVariantList outputs = cardOutputs.value(drmCard);
        seatData[QStringLiteral("displays")] = outputs;

        // Dynamic USB Topology discovery
        QString usbTopologyDesc;
        if (seatName == QStringLiteral("seat0")) {
            usbTopologyDesc = QStringLiteral("Direct Host Controllers (Root xHCI)");
        } else {
            // Check attached USB devices/hubs in seat-status
            QRegularExpression usbHubRegex(QString::fromUtf8(R"(/usb(\d+)/(\d+-\d+))"));
            QRegularExpressionMatch hubMatch = usbHubRegex.match(statusOut);
            if (hubMatch.hasMatch()) {
                QString devId = hubMatch.captured(2); // e.g. "1-5"
                QString prodFile = QStringLiteral("/sys/bus/usb/devices/%1/product").arg(devId);
                QString mfgFile = QStringLiteral("/sys/bus/usb/devices/%1/manufacturer").arg(devId);
                
                QString prodName, mfgName;
                QFile pf(prodFile);
                if (pf.open(QIODevice::ReadOnly)) prodName = QString::fromUtf8(pf.readAll()).trimmed();
                QFile mf(mfgFile);
                if (mf.open(QIODevice::ReadOnly)) mfgName = QString::fromUtf8(mf.readAll()).trimmed();

                if (!prodName.isEmpty()) {
                    usbTopologyDesc = QStringLiteral("%1 %2 USB Hub (%3)").arg(mfgName, prodName, devId);
                } else {
                    usbTopologyDesc = QStringLiteral("Dedicated USB Hub (%1)").arg(devId);
                }
            } else {
                usbTopologyDesc = QStringLiteral("Dedicated Seat USB Controller");
            }
        }
        seatData[QStringLiteral("usbTopology")] = usbTopologyDesc;

        // Dynamic Input Devices Discovery from seat-status
        QStringList inputDevices;
        QSet<QString> seenInputs;
        QRegularExpression inputRegex(QString::fromUtf8("input:input\\d+\\s+\"([^\"]+)\""));
        auto inputMatches = inputRegex.globalMatch(statusOut);
        while (inputMatches.hasNext()) {
            auto match = inputMatches.next();
            QString name = match.captured(1).trimmed();
            // Filter out system control / internal noise
            if (name.contains(QStringLiteral("Consumer Control"), Qt::CaseInsensitive) ||
                name.contains(QStringLiteral("System Control"), Qt::CaseInsensitive) ||
                name.contains(QStringLiteral("MYSTIC LIGHT"), Qt::CaseInsensitive) ||
                name.contains(QStringLiteral("Power Button"), Qt::CaseInsensitive) ||
                name.contains(QStringLiteral("Video Bus"), Qt::CaseInsensitive) ||
                name.contains(QStringLiteral("PC Speaker"), Qt::CaseInsensitive) ||
                name.contains(QStringLiteral("HD-Audio"), Qt::CaseInsensitive) ||
                name.contains(QStringLiteral("HDA"), Qt::CaseInsensitive)) {
                continue;
            }
            if (!seenInputs.contains(name)) {
                seenInputs.insert(name);
                inputDevices.append(name);
            }
        }
        if (inputDevices.isEmpty()) {
            inputDevices.append(QStringLiteral("USB HID Input"));
        }
        seatData[QStringLiteral("inputDevices")] = inputDevices;

        // Dynamic Audio Controller Discovery (matching GPU's PCI audio counterpart or ALSA)
        QString audioSinkDesc;
        if (!pciAddr.isEmpty()) {
            QString audioPci = pciAddr;
            audioPci[audioPci.length() - 1] = QLatin1Char('1'); // e.g. 03:00.1
            QString audioDesc = getPciDeviceDescription(audioPci);
            if (!audioDesc.isEmpty()) {
                audioSinkDesc = QStringLiteral("%1 [%2]").arg(audioDesc, audioPci);
            }
        }
        if (audioSinkDesc.isEmpty()) {
            audioSinkDesc = QStringLiteral("System Default Audio Controller");
        }
        seatData[QStringLiteral("audioSink")] = audioSinkDesc;

        m_seats.append(seatData);
    }

    Q_EMIT seatsChanged();
}

void KCMultiseat::collectRulesData()
{
    m_rules.clear();

    QDir rulesDir(QStringLiteral("/etc/udev/rules.d"));
    const QStringList ruleFiles = rulesDir.entryList({QStringLiteral("72-seat-*.rules")}, QDir::Files);
    for (const QString &filename : ruleFiles) {
        QFile ruleFile(rulesDir.filePath(filename));
        if (ruleFile.open(QIODevice::ReadOnly | QIODevice::Text)) {
            QString content = QString::fromUtf8(ruleFile.readAll()).trimmed();
            QVariantMap ruleMap;
            ruleMap[QStringLiteral("file")] = filename;
            ruleMap[QStringLiteral("content")] = content;
            m_rules.append(ruleMap);
        }
    }

    Q_EMIT rulesChanged();
}

#include "multiseat.moc"
