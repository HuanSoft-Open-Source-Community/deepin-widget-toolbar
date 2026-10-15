// SPDX-FileCopyrightText: 2026 UnionTech Software Technology Co., Ltd.
//
// SPDX-License-Identifier: GPL-3.0-or-later

#pragma once

#include <QObject>
#include <QString>
#include <QStringList>
#include <QVariantMap>

class WidgetManager;

// 小组件宿主能力代理（QML 单例 org.deepin.widgettoolbar/WidgetHost）：
// 小组件自身无法直接访问 WidgetManager，经本代理回写自身实例配置。
// 当前暴露保存配置与键盘焦点请求两项能力。
class WidgetHost : public QObject
{
    Q_OBJECT
public:
    explicit WidgetHost(WidgetManager *manager, QObject *parent = nullptr);

    // 保存该实例的配置；仅允许 manifest settings schema 中声明的 key
    Q_INVOKABLE bool saveConfig(const QString &instanceId, const QVariantMap &values);
    // 其它实例 dials 中已使用的时区 id（世界时间跨实例地区唯一性用）
    Q_INVOKABLE QStringList usedZones(const QString &excludingInstanceId);
    // 小组件点击进入文本编辑（如便签）时请求 OS 键盘焦点：
    // X11 下面板是 Dock/Notification 类窗口，kwin 不因点击授予键盘焦点，
    // 只做 QML 取焦光标会闪但按键无法送达；详见 WindowGuard::ensureKeyboardFocus
    Q_INVOKABLE void activateWindow();
    // 小组件请求宿主打开"选择程序"三级面板（应用快捷启动器用）：
    // index 为待编辑的启动器槽位（-1 = 追加新单元），宿主确认后直接回写实例配置
    Q_INVOKABLE void requestOpenAppPicker(const QString &instanceId, int index);
    // 导入实例图片（image 设置类型用）：校验来源文件存在且后缀为
    // png/jpg/jpeg/bmp/webp 后，由宿主复制到 <dataDir>/<instanceId>/img-<时间戳>.<后缀>
    //（小组件沙箱不能读外部文件，文件对话框来源路径在沙箱外，必须由宿主复制）。
    // 成功返回相对 dataDir 的路径（如 "<instanceId>/img-1727.jpg"），失败返回空串
    Q_INVOKABLE QString importInstanceImage(const QString &instanceId, const QString &sourceFilePath);
    // 删除实例图片：仅允许删除 <dataDir>/<instanceId>/ 内的文件（规范化 +
    // 符号链接解析双重校验防路径逃逸）；文件存在且删除成功返回 true
    Q_INVOKABLE bool removeInstanceImage(const QString &instanceId, const QString &relativePath);

Q_SIGNALS:
    // 打开选择面板请求（宿主 QML 监听并负责弹窗定位）
    void openAppPickerRequested(const QString &instanceId, int index);

private:
    WidgetManager *m_manager = nullptr;
};
