# -*- coding: utf-8 -*-
"""全仓库唯一的降级入口（Python 版），与 templates/go/fallback/fallback.go 等价。

设计约束（「代码结构层」的三条铁律）：

1. 降级必须有 key，key 必须先 register()；未注册直接抛 UnregisteredFallbackError，
   让「偷偷加一个降级」在第一次运行时就炸掉，而不是安静地上线。
2. 降级事实必须显式返回：FallbackResult.degraded 告诉调用方「这是兜底结果」，
   FallbackResult.cause 保留原始异常对象（含 traceback），排查上下文不丢。
3. 每次降级都记日志 + 打指标（on_fallback 钩子），降级从不免费。

另外：`expected` 是**必填**关键字参数，而不是默认 (Exception,)。
一个专治「宽泛 except」的工具如果自己默认捕获 Exception，就等于把要治的病写进了处方。
写下 expected=(TimeoutError, ConnectionError) 的那一刻，作者必须想清楚
「到底什么失败才配降级」——这正是我们要逼出的思考。

registry 采用编译期/导入期注册而不是读 fallbacks.yaml，理由见
templates/go/fallback/fallback.go 的包注释（审批就近性 + 零依赖 + 启动即校验）。

用法::

    import fallback

    fallback.register("cache-read-degrade")          # 通常写在模块导入期
    fallback.on_fallback = lambda key, cause: METRIC.labels(key).inc()

    def read_profile(uid: int) -> dict:
        result = fallback.run(
            "cache-read-degrade",
            primary=lambda: redis_get(uid),
            degraded=lambda: db_get(uid),
            expected=(TimeoutError, ConnectionError),   # 必填：只有这些异常才降级
        )
        if result.degraded:
            logger.warning("cache degraded uid=%s cause=%r", uid, result.cause)
        return result.value

反例（会被 semgrep 拦下）::

    try:
        return redis_get(uid)
    except Exception:      # 未登记、无 key、无指标、调用方看不见
        return {}

接入方式：把本文件拷进宿主仓库（例如 myapp/fallback.py）。零第三方依赖。
"""

from __future__ import annotations

import logging
from dataclasses import dataclass
from typing import Callable, Generic, Optional, Sequence, Tuple, Type, TypeVar

__all__ = [
    "FallbackResult",
    "UnregisteredFallbackError",
    "register",
    "is_registered",
    "registered",
    "run",
    "on_fallback",
    "logger",
]

T = TypeVar("T")

logger = logging.getLogger("fallback")

#: 可注入的指标钩子，每次降级发生时调用：on_fallback(key, cause)。
#: 默认 None（不打指标也不报错）；接入方在启动阶段赋值一次。
on_fallback: Optional[Callable[[str, BaseException], None]] = None

_REGISTRY: set = set()


class UnregisteredFallbackError(RuntimeError):
    """使用了未注册的降级 key。

    这是「有人偷偷加了一条降级」的信号，属于配置/流程错误，不要 catch 它。
    """

    def __init__(self, key: str) -> None:
        super().__init__(
            "fallback: key %r 未注册。请先 fallback.register(%r)，"
            "并在 policy/fallbacks.yaml 登记 trigger/reason/owner/expires/test 后走审批。"
            % (key, key)
        )
        self.key = key


@dataclass
class FallbackResult(Generic[T]):
    """降级结果。

    三个字段都要被调用方处理，不要只取 value：

    :param value:    primary 成功时是它的返回值；失败时是 degraded() 的返回值
    :param degraded: 本次是否走了兜底路径 —— 请透传到日志/响应头/指标，别咽下去
    :param cause:    触发降级的原始异常对象（含 __traceback__），未降级时为 None
    """

    value: T
    degraded: bool
    cause: Optional[BaseException] = None

    def raise_if_degraded(self) -> None:
        """需要「降级即失败」的调用方可以直接用这个把原始异常链抛出去。"""
        if self.degraded and self.cause is not None:
            raise RuntimeError("degraded result rejected by caller") from self.cause


def register(key: str) -> None:
    """注册一个降级 key（通常在模块导入期调用）。

    key 必须与 policy/fallbacks.yaml 中的条目一一对应（kebab-case）。
    重复注册直接报错：同一个 key 出现在两处意味着 owner 与审批范围含糊不清。
    """
    if not key or not isinstance(key, str):
        raise ValueError("fallback: register() 需要非空字符串 key")
    if key in _REGISTRY:
        raise ValueError("fallback: key %r 重复注册；一个 key 只能对应一处降级" % key)
    _REGISTRY.add(key)


def is_registered(key: str) -> bool:
    """报告 key 是否已注册。"""
    return key in _REGISTRY


def registered() -> Tuple[str, ...]:
    """返回全部已注册 key（已排序），供测试与 CI 对账使用。

    建议在宿主仓库写一个测试：读 policy/fallbacks.yaml 的 key 集合，
    断言与 registered() 相等 —— 「加了降级但没走审批」就会在 CI 红。
    """
    return tuple(sorted(_REGISTRY))


def run(
    key: str,
    primary: Callable[[], T],
    degraded: Callable[[], T],
    *,
    expected: Sequence[Type[BaseException]],
) -> FallbackResult[T]:
    """执行 primary，遇到 expected 中的异常时退到 degraded。

    :param key:      已注册的降级 key
    :param primary:  主路径（无参可调用）
    :param degraded: 兜底路径（无参可调用）；它自己抛异常时**不再兜底**，直接向上抛
    :param expected: 必填。只有这些异常类型会触发降级；其余异常原样上抛。
                     不允许传 (Exception,) 之外没想清楚的宽类型——想清楚了当然可以传。
    :raises UnregisteredFallbackError: key 未注册
    """
    if not is_registered(key):
        raise UnregisteredFallbackError(key)
    if not callable(primary) or not callable(degraded):
        raise TypeError("fallback: key %r 的 primary/degraded 必须是可调用对象" % key)
    if not expected:
        raise ValueError(
            "fallback: key %r 必须显式声明 expected=(...)，"
            "写清楚哪些异常才配降级；空元组等于「什么都不降级」，那就别用本入口。" % key
        )
    exc_types = tuple(expected)

    try:
        return FallbackResult(value=primary(), degraded=False, cause=None)
    except exc_types as exc:  # noqa: B902 - 类型由调用方显式声明，非宽泛捕获
        # 降级从不免费：原始异常必须完整留痕（exc_info 带上 traceback）
        logger.warning(
            "[fallback] key=%s degraded=true cause=%r", key, exc, exc_info=exc
        )
        hook = on_fallback
        if hook is not None:
            hook(key, exc)
        # degraded() 若自己失败，用 raise ... from exc 保住异常链，不吞
        try:
            value = degraded()
        except BaseException as degrade_exc:  # noqa: B036 - 立刻重抛，只为接链
            raise degrade_exc from exc
        return FallbackResult(value=value, degraded=True, cause=exc)
