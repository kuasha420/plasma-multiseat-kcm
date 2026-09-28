/*
 * SPDX-FileCopyrightText: 2026 Antigravity
 * SPDX-License-Identifier: GPL-2.0-or-later
 */

#pragma once

#include <KQuickConfigModule>
#include <QVariantList>
#include <QVariantMap>
#include <QString>
#include <QDateTime>

class KCMultiseat : public KQuickConfigModule
{
    Q_OBJECT
    Q_PROPERTY(QVariantList seats READ seats NOTIFY seatsChanged)
    Q_PROPERTY(QVariantList rules READ rules NOTIFY rulesChanged)
    Q_PROPERTY(bool isLoading READ isLoading NOTIFY isLoadingChanged)
    Q_PROPERTY(QString lastUpdated READ lastUpdated NOTIFY lastUpdatedChanged)

public:
    explicit KCMultiseat(QObject *parent, const KPluginMetaData &metaData);
    ~KCMultiseat() override = default;

    QVariantList seats() const { return m_seats; }
    QVariantList rules() const { return m_rules; }
    bool isLoading() const { return m_isLoading; }
    QString lastUpdated() const { return m_lastUpdated; }

    Q_INVOKABLE void refresh();

Q_SIGNALS:
    void seatsChanged();
    void rulesChanged();
    void isLoadingChanged();
    void lastUpdatedChanged();

private:
    void collectSeatData();
    void collectRulesData();

    QVariantList m_seats;
    QVariantList m_rules;
    bool m_isLoading = false;
    QString m_lastUpdated;
};
