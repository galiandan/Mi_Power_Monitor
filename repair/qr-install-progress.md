# 首次安装停在“找不到配置文件”后的修复

日期：2026-09-26。

用户报告长期无输出。代码检查发现该提示后先创建 venv，再执行 pip --quiet 安装完整 requirements（包括 GitHub python-miio 源码依赖），成功后才显示扫码提示。本轮未取得用户卡住的进程现场，因此没有断言具体阻塞在 venv、PyPI 或 GitHub。

修复：两安装器提供分阶段输出，venv 120 秒、pip 300 秒总预算及 5 秒强制终止宽限；pip 显示进度并限制单次网络等待与重试。按固定扫码工具的[依赖清单](https://raw.githubusercontent.com/PiotrMachowski/Xiaomi-cloud-tokens-extractor/c4db715dace9806e905153c2977608873e8ab7c9/requirements.txt)只安装扫码所需包。Python 扫码下载分阶段提示，Git clone/fetch 各限时 120 秒、checkout 30 秒，超时清理整个进程组。隐藏 KDE 构建自检产生的帮助文字。

验证：KDE Python 回归 30 项通过；新增模拟依赖超时、Git 失败和超时清理测试；两安装器 bash -n、公共 Python 编译及两副本一致性检查通过。本轮未完成真实小米扫码登录，也未复现用户网络环境。
