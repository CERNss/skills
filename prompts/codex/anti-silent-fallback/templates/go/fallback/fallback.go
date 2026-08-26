// Package fallback 提供全仓库唯一的降级入口。
//
// 设计约束（这是整套反静默降级机制的「代码结构层」）：
//
//  1. 降级必须有 key，key 必须先注册；未注册直接 panic —— 让「偷偷加一个降级」
//     在第一次运行时就炸掉，而不是安静地上线。
//  2. 降级事实必须显式返回：Run 的第二个返回值 degraded 告诉调用方「这次是兜底结果」，
//     第三个返回值同时携带包装过的原始错误（%w），调用方可以 errors.Is/As 追因。
//     ——「静默」之所以有害，核心就在于调用方无从得知发生过降级。
//  3. 每次降级都记日志 + 打指标（OnFallback 钩子），降级从不免费。
//
// 关于 registry 的来源，两种方案二选一，这里选了「编译期注册」：
//
//	方案 A（本实现）：init() 里 Register("cache-read-degrade")
//	  + 不引入 YAML 解析依赖，helper 保持零依赖，任何服务都能直接 vendor；
//	  + key 的定义就写在使用它的包旁边，读代码的人当场看到「这里有一个已审批的降级」；
//	  + 启动即校验：漏注册 = 首次调用 panic，不需要等 CI。
//	  - 代价：代码里的注册表和 policy/fallbacks.yaml 是两份数据，可能漂移。
//	    这份漂移由 CI 兜底：check-fallback.sh full 做豁免对账，
//	    另外建议在仓库里加一个测试，断言 fallback.Registered() ⊆ fallbacks.yaml 的 key 集合
//	    （见本文件末尾 Registered 的注释）。
//
//	方案 B（未采用）：启动时读 fallbacks.yaml
//	  - 要给每个服务塞 YAML 依赖和文件路径约定；
//	  - 更要命的是「审批就近性」被破坏：改 YAML 就能悄悄给一段代码开降级权限，
//	    而代码 diff 里看不到任何变化，reviewer 很难发现。
//
// 接入方式：把本目录拷进宿主仓库（例如 internal/fallback/），删除同目录下的占位 go.mod，
// import 路径改成宿主 module 的路径。
package fallback

import (
	"context"
	"fmt"
	"log"
	"sort"
	"sync"
)

// OnFallback 是可注入的指标钩子，在每次降级发生时被调用。
// 默认 nil（不打指标也不会 panic）；接入方在 main() 里赋值，例如：
//
//	fallback.OnFallback = func(key string, cause error) {
//	    fallbackDegradedTotal.WithLabelValues(key).Inc()
//	}
//
// 赋值应在启动阶段一次性完成；运行中并发改写不安全。
var OnFallback func(key string, cause error)

// Logger 允许替换默认的标准库日志（接入方可换成 zap/slog 适配器）。
var Logger = func(format string, args ...any) {
	log.Printf(format, args...)
}

var (
	mu       sync.RWMutex
	registry = map[string]struct{}{}
)

// Register 注册一个降级 key，通常在包的 init() 中调用。
//
// key 必须与 policy/fallbacks.yaml 中的条目一一对应（kebab-case）。
// 重复注册会 panic：同一个 key 出现在两处意味着 owner 与审批范围含糊不清。
func Register(key string) {
	if key == "" {
		panic("fallback: Register 传入了空 key")
	}
	mu.Lock()
	defer mu.Unlock()
	if _, dup := registry[key]; dup {
		panic(fmt.Sprintf("fallback: key %q 重复注册；一个 key 只能对应一处降级", key))
	}
	registry[key] = struct{}{}
}

// IsRegistered 报告 key 是否已注册。
func IsRegistered(key string) bool {
	mu.RLock()
	defer mu.RUnlock()
	_, ok := registry[key]
	return ok
}

// Registered 返回全部已注册 key（已排序），供测试与 CI 对账使用。
//
// 建议在宿主仓库写一个测试：读 policy/fallbacks.yaml 的 key 集合，
// 断言 Registered() 与之相等 —— 这样「代码里加了降级但没走审批」会在 CI 红。
func Registered() []string {
	mu.RLock()
	defer mu.RUnlock()
	keys := make([]string, 0, len(registry))
	for k := range registry {
		keys = append(keys, k)
	}
	sort.Strings(keys)
	return keys
}

// Run 执行 primary，失败时退到 degraded。
//
// 返回值语义（三个都必须被调用方处理，不要用 _ 丢掉第二、三个）：
//
//	value    primary 成功时是它的结果；失败时是 degraded() 的结果
//	degraded 本次是否走了兜底路径 —— 请把它透传到日志/响应头/指标，别咽下去
//	err      primary 成功时为 nil；失败时为 fmt.Errorf("degraded[key]: %w", 原始 err)
//	         注意：降级成功时 err 依然非 nil。这是刻意设计——
//	         「降级了但没报错」正是我们要消灭的静默。调用方可以选择只记录不中断，
//	         但必须显式做出这个选择。
//
// key 未注册时直接 panic（fail-fast，见包注释）。
// ctx 已取消时不执行 primary，直接返回 ctx.Err()，不做降级：
// 上游已经放弃这次请求，兜底数据没有意义。
func Run[T any](
	ctx context.Context,
	key string,
	primary func() (T, error),
	degraded func() T,
) (T, bool, error) {
	var zero T

	if !IsRegistered(key) {
		panic(fmt.Sprintf(
			"fallback: key %q 未注册。请在 init() 里 Register(%q)，"+
				"并在 policy/fallbacks.yaml 登记 trigger/reason/owner/expires/test 后走审批。",
			key, key))
	}
	if primary == nil || degraded == nil {
		panic(fmt.Sprintf("fallback: key %q 的 primary/degraded 不能为 nil", key))
	}

	if ctx != nil {
		if err := ctx.Err(); err != nil {
			return zero, false, fmt.Errorf("fallback[%s]: context 已结束: %w", key, err)
		}
	}

	v, err := primary()
	if err == nil {
		return v, false, nil
	}

	// 降级从不免费：原始错误必须完整留痕
	Logger("[fallback] key=%s degraded=true cause=%v", key, err)
	if OnFallback != nil {
		OnFallback(key, err)
	}

	return degraded(), true, fmt.Errorf("degraded[%s]: %w", key, err)
}
