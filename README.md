简体中文 | [English](README.en.md)

# 米家智能插座 3 功率读取器

通过局域网读取米家智能插座 3（`cuco.plug.v3`）的实时功率。Go 程序适合长期运行，为 KDE Plasma 小部件等客户端提供低开销的轮询后端。读取功率不需要 Home Assistant 或小米云端。

## 一键安装（Arch Linux）

```bash
curl -fsSL https://raw.githubusercontent.com/galiandan/Mi_Power_Monitor/main/install.sh | bash
```

脚本会下载适合当前架构的 Go 二进制并校验 SHA-256，首次安装时优先引导使用二维码登录，然后将命令安装到 `~/.local/bin/xiaomi-power`。脚本会尝试自动打开本机浏览器中的二维码登录页面，并同时显示网址；若浏览器没有弹出，可手动打开该网址，再用手机米家 App 扫描浏览器页面中的二维码并确认。已有配置会先检查 JSON、设备型号、IP、32 位十六进制 token 和超时范围；有效配置会复用，无效配置会引导重新扫码。新配置写入临时文件并原子替换，扫码失败或写入失败时保留旧配置。若米家账号下有多台插座，扫码后会列出候选设备供你按编号选择；不会输出 token。首次扫码和运行时功率读取均由 Go 完成，不需要 Python venv、pip 或外部扫码工具。安装脚本仍使用系统 Python 检查发行包归档。

安装器在独立版本目录中准备并启动新版本，成功切换后保留当前版和上一版。版本目录使用安装标记管理，升级不会清理应用目录中的未知文件；安装和卸载使用同一个用户级锁，避免同时切换文件。若配置校验、扫码、下载或解包失败，原有命令链接继续指向旧版本。

可先查看[安装脚本](install.sh)。系统缺少必要工具时，脚本会提示 Arch Linux 安装命令。

卸载 Go 程序和安装文件（保留配置与 token）：

也可以先查看[卸载脚本](uninstall.sh)。

```bash
curl -fsSL https://raw.githubusercontent.com/galiandan/Mi_Power_Monitor/main/uninstall.sh | bash
```

如需同时删除配置和 token，追加 `--purge-config`：

```bash
curl -fsSL https://raw.githubusercontent.com/galiandan/Mi_Power_Monitor/main/uninstall.sh | bash -s -- --purge-config
```

## 从源码构建

需要 Go 1.25 或更新版本。程序使用 [`github.com/mberatsanli/miio`](https://github.com/mberatsanli/miio) 进行小米 miIO 局域网通信和通用 MIoT 属性读取。协议帧、加密、握手、重试及 `(SIID, PIID)` 属性寻址均由该库处理，本项目不自行实现底层协议。

```bash
CGO_ENABLED=0 go build -trimpath -ldflags='-s -w' -o xiaomi-power ./cmd/xiaomi-power
```

这会生成精简的静态链接二进制，不需要 Python 运行环境。

也可以从 [Releases](https://github.com/galiandan/Mi_Power_Monitor/releases) 下载 Linux x86-64 或 ARM64 版本。

## Python 设备详情（可选）

安装脚本首次运行时会自动处理扫码和 token 配置。若之后要查询固件版本或设备 ID，可单独安装 Python 辅助依赖：

```bash
python -m venv .venv
.venv/bin/python -m pip install -r requirements.txt
.venv/bin/python xiaomi_power.py --info
```

`--info` 会显示设备 IP、固件版本和设备 ID；分享前请检查是否包含私人信息。

### 手动配置

如需手动配置：

```bash
install -d -m 700 ~/.config/xiaomi-power
install -m 600 config.example.json ~/.config/xiaomi-power/config.json
$EDITOR ~/.config/xiaomi-power/config.json
chmod 600 ~/.config/xiaomi-power/config.json
```

将示例中的文档专用 IP、token 和可选设备 ID 替换为插座的实际信息。不要提交真实的 `config.json`；`.gitignore` 已将其排除。Go 程序使用 token 前也会将配置目录和文件权限设为 `700` 和 `600`。占位 token 或非 IP 地址会被拒绝。

导入 Android `.ab` 备份时采用顺序流式读取。为限制资源占用，输入备份最多 4 GiB、解包成员总量最多 8 GiB、成员数最多 100,000，米家 SQLite 数据库最多 256 MiB。

## 读取实时功率

编译一次后，读取一次功率：

```bash
./xiaomi-power
```

输出示例：

```text
Device: cuco.plug.v3
Power: 83.4 W
```

保持单个进程运行并持续轮询：

```bash
./xiaomi-power --watch
```

使用机器可读的逐行 JSON 输出。`--count` 可限制读取次数，`--interval` 可调整轮询间隔：

```bash
./xiaomi-power --json
./xiaomi-power --watch --json --interval 1s --count 30
```

每行 JSON 包含 `model`、`power`、`unit` 和 `available`；成功时还包含 UTC `sampled_at`，读取失败时 `power` 为 `null` 并附带 `error`。轮询过程中会复用同一个 LAN 连接；按 Ctrl+C 停止程序。

## MIoT 属性

[`cuco.plug.v3` MIoT 规格](https://home.miot-spec.com/spec/cuco.plug.v3)将服务 11 定义为 `power-consumption`，属性 11.2 为 `electric-power`，单位是瓦特。Go 程序通过 SIID 11 / PIID 2 读取此属性。属性 11.1 表示累计用电量，单位步长为 0.01 kWh。

设备 token 是允许访问插座的本地凭据。局域网读取使用 UDP 54321 端口。如果读取失败，请检查设备 IP、token、网络可达性和插座的局域网访问设置。

## 验证情况

原 Python 程序已在真实设备上完成 30 次、每秒一次的读取，并验证读数会随负载变化。Go 程序也已连续读取 30 次且无失败；在 Arch Linux x86-64 上，该次运行的峰值 RSS 约为 11.7 MiB。实际资源占用会随 Go 运行时和系统环境变化。

## 许可证

本项目仅按 GNU GPL 第 3 版授权，详见 [LICENSE](LICENSE)。Go MIoT 通信库是单独的 MIT 许可证依赖。


### 内置二维码登录

首次安装直接运行 Go 后端的 `--setup-cloud-qr`，默认询问服务器（回车选 cn；支持 de/us/ru/tw/sg/in/i2/all），随后自动打开浏览器。程序只在 `127.0.0.1` 的随机端口提供带随机路径的临时二维码页面；不用固定 31415 端口，也不会绑定代理或局域网地址。手机米家 App 扫码确认后，回终端选择插座；token 不输出，配置用 0600 权限原子保存。登录会话只保留在内存中，网页自动切换为登录成功和配置结果页；结果送达后关闭本机服务，无人查看时最多额外等待 2 秒。已打开页面保留结果，按 Alt+Tab 可返回安装终端。

手动运行（KDE 安装将命令名换为 `mi-power-monitor-backend`）：

```bash
xiaomi-power --setup-cloud-qr
xiaomi-power --setup-cloud-qr --region cn --no-browser
xiaomi-power --validate-config
```

`--no-browser` 只输出本机网址，适合手动打开浏览器。二维码过期后重新运行即可；Ctrl+C 可取消。云端 IP 缺失时会询问局域网 IP。此登录接口属于小米云协议兼容实现，协议变动时可能需要更新。拥有超过单页上限且云端明确返回分页标志的家庭会提示手动配置，避免静默漏选。可选旧版 Python 工具保留，但安装器不再调用它登录；KDE 的 CPU/GPU 采样仍使用系统 Python。

验证：Go 协议向量、模拟登录/设备查询、配置保护和本机 HTTP 页面测试通过；已实际取得小米二维码并主动取消，未完成真实账号授权和设备列表读取。
