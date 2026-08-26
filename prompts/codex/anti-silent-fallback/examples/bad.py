"""反面教材：Python 静默降级。

预期命中：
  - silent-fallback-python-bare-except
  - silent-fallback-python-broad-except-swallow
  - silent-fallback-python-config-default
本文件仅供 semgrep 规则自测，不要被真实代码 import。
"""

import os

import requests


def load_user(uid: int):
    # 反面 1：裸 except 吞掉一切（含 KeyboardInterrupt），调用方分不清「没有该用户」和「数据库挂了」
    try:
        return _query_user(uid)
    except:
        return None


def fetch_profile(uid: int) -> dict:
    # 反面 2：宽泛 except + 返回空 dict，下游拿到假数据继续跑
    try:
        return requests.get(f"https://api.example.com/u/{uid}", timeout=3).json()
    except Exception:
        return {}


def warm_cache(uids: list) -> None:
    # 反面 3：宽泛 except + continue，批量任务「全成功」但其实一条没写进去
    for uid in uids:
        try:
            _write_cache(uid, fetch_profile(uid))
        except Exception as exc:
            continue


def flush_metrics() -> None:
    # 反面 4：宽泛 except + pass，指标丢了没人知道
    try:
        _push_metrics()
    except Exception:
        pass


def build_client():
    # 反面 5：凭据缺失时静默用假 key，故障现场被推迟到「服务端返回 401」
    api_key = os.environ.get("OPENAI_API_KEY", "sk-dummy")
    endpoint = os.getenv("BILLING_ENDPOINT", "http://localhost:8080")
    return _Client(api_key, endpoint)


def _query_user(uid: int):
    raise NotImplementedError


def _write_cache(uid: int, payload: dict) -> None:
    raise NotImplementedError


def _push_metrics() -> None:
    raise NotImplementedError


class _Client:
    def __init__(self, api_key: str, endpoint: str) -> None:
        self.api_key = api_key
        self.endpoint = endpoint
