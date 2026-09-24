简体中文 | [English](README.en.md)

# 米家智能插座 3 功率读取器

通过局域网读取米家智能插座 3（`cuco.plug.v3`）的实时功率。Go 程序适合长期运行，为 KDE Plasma 小部件等客户端提供低开销的轮询后端。读取功率不需要 Home Assistant 或小米云端。

## 一键安装（Arch Linux）

```bash
curl -fsSL https://raw.githubusercontent.com/galiandan/Mi_Power_Monitor/main/install.sh | bash
```

脚本会下载适合当前架构的 Go 二进制并校验 SHA-256，首次安装时优先引导使用二维码登录，然后将命令安装到 `~/.local/bin/xiaomi-power`。脚本会尝试自动打开本机浏览器中的二维码登录页面，并同时显示网址；若浏览器没有弹出，可手动打开该网址，再用手机米家 App 扫描终端中的二维码并确认。如果已有设备配置，会直接复用。若米家账号下有多台插座，扫码后会列出候选设备供你按编号选择；不会输出 token。Go 运行时不依赖 Python；Python 只在首次扫码时用于配置 token。

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

将示例中的文档专用 IP、token 和可选设备 ID 替换为插座的实际信息。不要提交真实的 `config.json`；`.gitignore` 已将其排除。Go 程序使用 token 前也会将配置目录和文件权限设为 `700` 和 `600`。

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

每行 JSON 包含 `model`、`power`、`unit` 和 `available`；读取失败时 `power` 为 `null`，并附带 `error`。轮询过程中会复用同一个 LAN 连接；按 Ctrl+C 停止程序。

## MIoT 属性

[`cuco.plug.v3` MIoT 规格](https://home.miot-spec.com/spec/cuco.plug.v3)将服务 11 定义为 `power-consumption`，属性 11.2 为 `electric-power`，单位是瓦特。Go 程序通过 SIID 11 / PIID 2 读取此属性。属性 11.1 表示累计用电量，单位步长为 0.01 kWh。

设备 token 是允许访问插座的本地凭据。局域网读取使用 UDP 54321 端口。如果读取失败，请检查设备 IP、token、网络可达性和插座的局域网访问设置。

## 验证情况

原 Python 程序已在真实设备上完成 30 次、每秒一次的读取，并验证读数会随负载变化。Go 程序也已连续读取 30 次且无失败；在 Arch Linux x86-64 上，该次运行的峰值 RSS 约为 11.7 MiB。实际资源占用会随 Go 运行时和系统环境变化。

## 许可证

本项目仅按 GNU GPL 第 3 版授权，详见 [LICENSE](LICENSE)。Go MIoT 通信库是单独的 MIT 许可证依赖。
