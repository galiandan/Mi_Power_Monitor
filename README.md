简体中文 | [English](README.en.md)

# 米家智能插座 3 功率读取器

通过局域网读取米家智能插座 3（`cuco.plug.v3`）的实时功率。Go 程序适合长期运行，为 KDE Plasma 小部件等客户端提供低开销的轮询后端。读取功率不需要 Home Assistant 或小米云端。

## 构建

需要 Go 1.25 或更新版本。程序使用 [`github.com/mberatsanli/miio`](https://github.com/mberatsanli/miio) 进行小米 miIO 局域网通信和通用 MIoT 属性读取。协议帧、加密、握手、重试及 `(SIID, PIID)` 属性寻址均由该库处理，本项目不自行实现底层协议。

```bash
CGO_ENABLED=0 go build -trimpath -ldflags='-s -w' -o xiaomi-power ./cmd/xiaomi-power
```

这会生成精简的静态链接二进制，不需要 Python 运行环境。

也可以从 [Releases](https://github.com/galiandan/Mi_Power_Monitor/releases) 下载 Linux x86-64 或 ARM64 版本。

## 首次配置（Python）

Python 只用于首次登录和查询设备信息；Go 后端直接使用 IP 和 token 读取功率。两者共用配置文件 `~/.config/xiaomi-power/config.json`。

首次使用时运行二维码登录：

```bash
python -m venv .venv
.venv/bin/python -m pip install -r requirements.txt
python xiaomi_power.py --setup-cloud-qr
```

按提示选择 `q`，用米家 App 扫描电脑上显示的二维码并确认。程序会自动保存插座 IP 和 token，不会打印 token。没有 QR 登录条件时，也可以从本地备份导入：`python xiaomi_power.py --import-token-source /path/to/miio2.db`（或 Android `.ab` 备份）。

查询固件版本和设备 ID：

```bash
python xiaomi_power.py --info
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

每行 JSON 包含 `model`、`power`、`unit` 和 `available`。轮询过程中会复用同一个 LAN 连接；按 Ctrl+C 停止程序。

## MIoT 属性

[`cuco.plug.v3` MIoT 规格](https://home.miot-spec.com/spec/cuco.plug.v3)将服务 11 定义为 `power-consumption`，属性 11.2 为 `electric-power`，单位是瓦特。Go 程序通过 SIID 11 / PIID 2 读取此属性。属性 11.1 表示累计用电量，单位步长为 0.01 kWh。

设备 token 是允许访问插座的本地凭据。局域网读取使用 UDP 54321 端口。如果读取失败，请检查设备 IP、token、网络可达性和插座的局域网访问设置。

## 验证情况

原 Python 程序已在真实设备上完成 30 次、每秒一次的读取，并验证读数会随负载变化。Go 程序也已连续读取 30 次且无失败；在 Arch Linux x86-64 上，该次运行的峰值 RSS 约为 11.7 MiB。实际资源占用会随 Go 运行时和系统环境变化。

## 许可证

本项目仅按 GNU GPL 第 3 版授权，详见 [LICENSE](LICENSE)。Go MIoT 通信库是单独的 MIT 许可证依赖。
