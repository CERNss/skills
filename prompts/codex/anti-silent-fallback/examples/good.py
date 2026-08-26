"""正面教材：允许的降级写法。

本文件对 semgrep/silent-fallback.yaml 的预期结果是 **零命中**：
  1. 必填配置 fail-fast，不给静默默认值；
  2. 真正的降级走统一入口 fallback.run，降级状态显式返回给调用方；
  3. 无法走统一入口的场合，用「白名单 key + nosemgrep」两行注释豁免。

豁免标注顺序（不可颠倒，详见 README「豁免标注约定」）：
    # fallback-key: <key>            <- 先写 key
    # nosemgrep: <rule-id>           <- nosemgrep 必须紧贴命中起始行
    try:                             <- Python try/except 的命中起始行是这一行
"""

import logging
import os

import requests

# 接入时替换成宿主仓库里 templates/python/fallback.py 的落位路径
from myapp.fallback import register, run

logger = logging.getLogger(__name__)

# 降级 key 在导入期注册；未注册的 key 调用 run() 会直接抛 UnregisteredFallbackError
register("cache-read-degrade")


def load_settings() -> dict:
    """必填配置缺失 = 部署错误，立刻 KeyError，不猜默认值。"""
    return {
        "api_key": os.environ["OPENAI_API_KEY"],
        "endpoint": os.environ["BILLING_ENDPOINT"],
        # 非凭据类、且有明确业务默认值的可选项才允许 get()
        "page_size": int(os.environ.get("PAGE_SIZE", "20")),
    }


def fetch_profile(uid: int) -> dict:
    """网络失败不吞：收窄异常类型 + 保留原始异常链向上抛。"""
    try:
        resp = requests.get(f"https://api.example.com/u/{uid}", timeout=3)
        resp.raise_for_status()
        return resp.json()
    except requests.RequestException as exc:
        raise RuntimeError(f"fetch_profile({uid}) failed") from exc


def read_profile_cached(uid: int) -> dict:
    """有意降级：缓存读不到就回源。

    降级事实通过 FallbackResult.degraded 显式暴露给调用方，
    原始异常保存在 result.cause，并触发 on_fallback 指标钩子。
    """
    result = run(
        "cache-read-degrade",
        primary=lambda: _read_cache(uid),
        degraded=lambda: fetch_profile(uid),
        expected=(TimeoutError, ConnectionError),
    )
    if result.degraded:
        logger.warning("cache degraded for uid=%s cause=%r", uid, result.cause)
    return result.value


def close_quietly(handle) -> None:
    """收尾路径：进程即将退出，关闭失败无可挽回，属于已审批的兜底。"""
    # fallback-key: cache-read-degrade
    # nosemgrep: silent-fallback-python-broad-except-swallow
    try:
        handle.close()
    except Exception:
        pass


def _read_cache(uid: int) -> dict:
    raise NotImplementedError
