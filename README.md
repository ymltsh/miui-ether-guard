# MIUI Ethernet Tether Guard

轻量 Magisk 模块：重启后检测到真实 USB 以太网卡，就尝试开启原生以太网共享；共享中断后自动恢复。默认不绑定网卡型号或 MAC，网线可稍后连接。

## 安装与使用

下载 Release 中的 ZIP，在 Magisk → 模块 → 从本地安装，然后重启。无需先手动开启以太网共享。多张网卡同时接入时，实际下游接口由 MIUI 的默认以太网选择决定，不保证同时共享所有端口。

只识别真实 USB 网卡，排除 RNDIS/gadget 和虚拟接口。不设置 USB 功能，不写 iptables，不启动自有 DHCP，不修改 SELinux。NAT、DHCP 和上游选择由系统共享服务管理。

## 自动恢复策略

- 每约 10 秒检查一次，只解析 dumpsys tethering 的当前状态段，忽略历史日志。
- 连续三次确认共享停止后，经再次检查网卡与状态，调用原生 TetheringManager.startTethering(5, Executor, Callback)。
- 不使用硬编码 Binder 事务号。该 MIUI 实机的 cmd tethering 没有命令实现。
- 状态不明、解析格式变化或共享接口有错误时，不猜测为停止。
- 失败按约 30、60、120、240、600 秒退避，持续失败最多六次。重新插拔网卡、链路转为就绪、暂停后恢复或重启可重新尝试。
- API 接受启动请求后，仍需观察到 TetheredState 才能认为恢复成功；不会强制 stop/start 或重置 USB。

系统状态无法可靠区分用户主动关闭和意外关闭。**主动关闭共享之前，先点击 Magisk 模块的 Action 暂停，等约 10 秒后再关闭。** 再次点击恢复。暂停状态跨重启保留。

root 终端暂停与恢复：

```sh
touch /data/adb/modules/miui_ether_guard/pause
# 恢复
rm -f /data/adb/modules/miui_ether_guard/pause
```

## 日志、诊断和卸载

日志位于 /data/adb/modules/miui_ether_guard/run/，仅限 root 读取。guard.log 超过约 128 KiB 轮转一次。probe.txt 保存接口探测，last-start.txt 保存原生回调，before-recovery.txt 保存最近一次恢复前快照。

```sh
cat /data/adb/modules/miui_ether_guard/run/guard.log
ASH_STANDALONE=1 /data/adb/magisk/busybox sh /data/adb/modules/miui_ether_guard/diagnose.sh
```

在 Magisk 中禁用或移除模块，然后重启。模块不主动停止现有原生共享，也没有自建 NAT/DHCP 规则需要撤销。

## 验证与局限

已在小米 11 Pro / Android 13 / MIUI V14.0.6.0.TKACNXM / Magisk 30.7 / SELinux Enforcing 上验证 root、脚本语法、网卡识别、状态解析和 TetheringManager 方法加载。此前已运行约 35 秒只观察模式。0.2.0 已通过 Magisk 实际安装并执行手机重启，25 项模拟测试通过。

重启后 ADB 未自动重连，**尚未实机确认本次开机共享自动恢复成功**，也未完成长时间运行验证。接口探测不代表所有状态下的原生启动调用都成功。

实机内核日志曾显示 USB 集线器和网卡断开、重新枚举，随后共享关闭；模块只能兜底恢复，无法修复供电、接触或 USB 驱动问题。原始实机日志不随仓库发布。

## 源码和构建

module/ 包含 Magisk 模块脚本、辅助程序 Dex JAR 和 Java 源码。helper.jar 使用 JDK 17 的 javac --release 8，以及 Google R8 8.3.37 的 D8 --min-api 30 构建。R8 下载地址与 SHA256 见 BUILD.md。

tests/test_guard.py 使用场景模拟替换硬件和系统调用，执行实际守护脚本，验证自动启动、换卡、无 carrier、多卡、暂停、恢复前竞态和重试上限。需 Python 3 和 POSIX sh；设置 GUARD_TEST_SHELL 可指定 shell 路径。

```sh
python tests/test_guard.py
```

测试结果见 tests/results.json。只支持 Magisk App 安装，未提供 Recovery 安装器。

## 参考

- [AOSP Android 13 TetheringManager](https://android.googlesource.com/platform/packages/modules/Connectivity/+/refs/heads/android13-release/Tethering/common/TetheringLib/src/android/net/TetheringManager.java)
- [Magisk 模块开发指南](https://topjohnwu.github.io/Magisk/guides.html)
