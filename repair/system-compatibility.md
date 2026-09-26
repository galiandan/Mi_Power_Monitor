# SDDM、Plasma 与系统组件兼容性复查

日期：2026-09-26。后端基线 `584f3fd`；KDE 仓库基线 `2a229dd`。

结论：未发现直接修改 SDDM、PAM、KWin、PowerDevil 或登录会话配置的代码，但发现系统权限和安装共存风险，不能确认当前版本“与系统组件没有任何冲突”。以下问题描述修复前基线；本轮修复状态与验证范围见文末。

## 本机验证与边界

- Plasma 版本为 6.7.5；SDDM 为 active/running。
- `systemctl --failed` 和 `systemctl --user --failed` 均为 0。
- 本次启动 SDDM 日志出现一次认证失败，随后认证成功并启动 Wayland 会话；没有证据将该认证失败归因于插件。
- 用户日志最近 150 条匹配查询未返回插件或指定 Plasma 错误记录；这不是完整崩溃历史审查。
- KPackage 列表和 Plasma DBus 枚举都没有本插件；三个用户命令链接、RAPL 规则和权限状态目录也不存在。当前服务正常不能证明安装插件后的兼容性。
- 本轮只读检查系统，用临时目录复现 Shell 行为；没有修改系统权限、安装插件、注销会话或重启 SDDM。

## 按优先级排列的问题

### C01 / P1：权限助手修改系统共用目录模式（已隔离复现）

位置：KDE `setup-rapl-access.sh:65`、`:140`。

`install -d -m 0755 /run/lock` 会修改已经存在的目录模式，而不只是创建目录。临时目录设为 `1777`，执行同样命令后成为 `0755`。在原本允许非 root 程序写锁文件的发行版上，这会破坏其他程序的锁文件创建。卸载路径也会执行此命令。`/etc/tmpfiles.d` 同样不应由本插件重设目录权限。

本机 `/run/lock` 当前为 `0755`；不能据此推断它曾被本插件修改，也不能据此证明其他发行版安全。

修复：使用插件专属的 root 所有运行目录；不对已有系统共用目录 chmod/chown。验收要覆盖共用目录为 `0755`、`1777`、`2775` 时安装和卸载均保留其模式。

### C02 / P1：RAPL 规则覆盖其他监控程序的读权限（代码确认）

位置：KDE `setup-rapl-access.sh:158-168`。

每个 Package 的 `energy_uj` 和 `max_energy_range_uj` 被设置为目标用户所有、模式 `0400`。如果系统此前通过组权限或其他用户所有权提供读取，本规则会移除这些访问权限；原本全局可读的最大能量范围也会被收紧。当前脚本只允许一位用户登记权限，不支持多用户共存。

`z` 规则确实修改目标的权限和所有权，参见 [systemd 官方说明](https://www.freedesktop.org/software/systemd/man/systemd-tmpfiles.html)。它不写功率限制值，但仍会影响其他读取者。

修复：定义不夺取已有访问权的授权策略；不要修改已经可读的计数器。若采用组权限必须保留既有权限关系；若采用 ACL 需先验证 sysfs 是否支持，不能假设支持。验收使用另一用户/组的既有监控进程检查前后读取能力。

### C03 / P2：卸载可能覆盖安装后管理员的新权限（代码确认）

位置：KDE `setup-rapl-access.sh:103-119`、`:140-151`。

卸载无条件恢复旧快照，没有确认当前权限是否仍是插件设置的值。如果管理员或其他软件在安装后调整权限，卸载将覆盖该新设置。只有旧规则而没有快照时，还会假设原权限是 `root:root 0400`，并非实测原值。

修复：记录应用前后状态，仅在当前状态仍匹配插件应用值时恢复；发生漂移时保留并报告。不要凭猜测恢复遗失的快照。硬件拓扑变化、部分授权失败和规则写入失败也需要恢复测试。

### C04 / P2：RAPL 域名称读取为空，授权流程漏检（已隔离复现）

位置：KDE `install.sh:239` 附近、`setup-rapl-access.sh:94`。

`domain_name="$(<"${rapl_dir}/name" 2>/dev/null || true)"` 并不输出文件内容。临时文件内容为 `package-0`，在 Bash 执行该表达式得到空字符串。因此安装器会漏过授权，而手动助手报告找不到 Package。Python 采样器不使用此表达式，不受同一问题影响。

修复：使用显式 `cat` 或 `read`，分别处理读取失败。验收既要覆盖真实名称，也要覆盖文件不存在和权限不足。本问题不是 SDDM 冲突，但解释了为何当前代码的权限分支未必实际生效；修复它之前必须同时处理 C01/C02。

### C05 / P2：独立后端与 KDE 安装器争用命令路径（代码确认）

位置：两仓库 `install.sh` 的 `command_path` 和已有链接归属检查；两仓库 `uninstall.sh` 的 `--purge-config`。

两者都安装 `~/.local/bin/xiaomi-power`，但独立后端目录是 `~/.local/share/xiaomi-power`，KDE 后端目录是 `~/.local/share/mi-power-monitor`。任一先装后，另一安装器将把链接判为非本安装器管理并拒绝覆盖。保护避免了误覆盖，但两套安装方式不能透明共存/迁移。两者还共享 `~/.config/xiaomi-power/config.json`；任一执行 purge 会删除另一方也可能依赖的配置。

修复：明确定义后端复用/迁移流程以及共享配置归属。分别验收两种安装顺序、单方升级、单方卸载和 purge。

### C06 / P2：隐藏 GPU 仍查询驱动，电源管理兼容性未验证（代码确认查询，影响待实测）

位置：KDE `backend/read-sensors.py:154-159`；`package/contents/ui/main.qml` 的显示开关与轮询命令。

CPU/GPU 开关和 totalOnly 只影响显示，采集器仍每轮执行 `nvidia-smi`。它没有设置 GPU 功率上限、风扇或持久化模式，但仍访问驱动；不能仅凭“只读查询”排除对混合显卡休眠、唤醒和功耗的影响。本轮没有测试 runtime D3，因此不声称已复现独显被唤醒。

修复建议：让停用采集成为明确策略，避免不需要时持续查询；在支持 runtime PM 的机器上检查 GPU runtime_status、空闲功耗、锁屏和休眠恢复。需要区分“隐藏数值”和“停用采集”的语义。

## 未发现直接冲突的代码边界

- Plasmoid ID 独立，为 `com.github.galiandan.mipowermonitor`；默认安装在用户的 Plasma 包目录。
- 没有安装 SDDM 主题、PAM 模块、KWin 插件、登录会话文件或系统共享库；没有重启/停止显示管理器的命令。
- Python 首次配置依赖装入各版本自己的 venv，没有调用系统全局 pip 安装。
- 常规采集没有驻留 systemd 服务；通过 Plasma executable 引擎启动子进程。超时杀进程使用新建会话的子进程组，没有按名字终止 SDDM/KWin/Plasma。
- 卸载通过固定插件 ID 匹配本组件实例，没有删除整个面板的代码。
- CPU 运行时采样只读能量计数器，GPU 命令是查询；没有写 CPU/GPU 调频、风扇和电源配置的代码。

以上是源码边界，不构成所有发行版或驱动组合的兼容认证。QML 仍在 plasmashell 中运行；Plasma5Support 依赖缺失、驱动异常和 Qt/Plasma 版本差异仍需实际安装验证。

## 后续验收

1. 优先修复并隔离验证 C01—C04，再执行需要管理员授权的测试。
2. 验证已有 RAPL 读取者、多用户、自定义组权限、授权失败、卸载时权限漂移。
3. 验证独立后端和 KDE 的两种安装顺序及卸载归属。
4. 在插件实际安装的 Plasma 会话验证添加/移除、多实例、锁屏解锁、注销登录、休眠恢复；记录进程数、日志和 GPU runtime PM 状态。
5. 完整 SDDM 重启或重启机器会结束当前会话，本轮未做。不能用当前未安装插件时的 SDDM 正常代替该项验收。


## 修复记录（2026-09-26）

- C01：移除对 `/run/lock`、`/etc/tmpfiles.d` 的模式设置；仅创建插件自己的 `/run/mi-power-monitor` 和固定读取程序目录。
- C02：用 root 所有的 `/usr/local/libexec/mi-power-monitor/read-rapl` 代替 chmod 授权。它使用 `/usr/bin/python3 -I`，拒绝参数，只读取顶层 Package 的能量和范围。每个 UID 有独立 sudoers 授权，支持多用户。没有新增 systemd 服务，也不修改 sysfs 权限。依赖 sudo、visudo 和 `/usr/bin/python3`；sudoers.d 必须由系统 sudo 策略加载。
- C03：旧记录缺失、归属不同或权限漂移时中止并保留现场，不猜测原值。快照完整且当前状态等于旧版设置时恢复；已恢复原值的条目可重试。新版卸载仅撤销该 UID 的授权，最后一位用户卸载时移除受管读取程序；其他用户授权保留。遇到旧记录不完整或管理员修改时，仍需管理员处理旧规则及快照，安装器会明确提示。
- C04：安装器改用显式 `cat` 读取域名称；旧助手中的错误表达式随授权逻辑移除。
- C05：KDE 命令改为 `mi-power-monitor-backend`，采集器优先调用自身版本目录中的 `xiaomi-power`。独立安装器允许迁移已知 KDE 旧别名；KDE 升级仅删除自己的旧别名。两套卸载器在另一套仍存在时保留共享配置。
- C06：QML 将停用参数传递给采集器；关闭 CPU/GPU 或使用 totalOnly 后不启动对应任务。NVIDIA 显示设备的 runtime 状态不是 active 时跳过驱动查询。状态检查和实际查询之间仍有竞态，不能宣称所有驱动上都绝不唤醒 GPU。

固定读取命令的 sudoers 设置只授权无参数调用，并使用 NOSETENV；成功调用日志、PAM session 和 credential 初始化仅对该命令关闭，避免周期性查询刷日志和反复建立会话。拒绝日志保留；没有修改 `/etc/pam.d` 或 SDDM。选项语义核对了本机 sudo 1.9.17p2 手册及 [sudo 官方手册源码](https://github.com/sudo-project/sudo/blob/main/docs/sudoers.man.in)。sudo 版本不支持设置时，visudo 校验失败，不发布无效规则。

### 本轮验证

- KDE Python 回归 27 项通过，包含原有 17 项及新增兼容性测试。
- 新增覆盖：固定程序拒绝参数、只读 Package 计数器、忽略 PYTHONPATH、sudoers 语法、权限漂移保留与旧权限恢复、停用采集、GPU runtime 状态、QML 命令参数转发、已有独立后端时 KDE 安装与卸载的归属保护。
- 安装测试使用临时 HOME/XDG、模拟 Go 和 KPackage/DBus 工具、空硬件目录；不代表真实 KPackage/驱动测试。
- 另用临时 HOME 验证独立后端卸载 `--purge-config` 保留 KDE 所需共享配置。
- 两仓库修改的 Shell 语法及 diff 空白检查通过。
- qmllint 仍报告 Plasma 动态 configuration/i18n 与外部 ID 访问警告，未把该检查写成无警告通过。
- 本轮未进行真实 sudo 授权安装、SDDM 重启、注销登录、休眠恢复、多账户系统集成或硬件 runtime PM 测试。27 项通过不能替代这些验收，也不意味着所有系统组合绝无冲突。
