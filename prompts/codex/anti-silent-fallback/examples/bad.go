// 反面教材：Go 静默降级。
//
// 预期命中：
//   - silent-fallback-go-nilerr
//   - silent-fallback-go-empty-err-block
//
// 本文件仅供 semgrep 规则自测，故意不属于任何可编译的 package（文件名不以 _test.go 结尾，
// 且被 //go:build ignore 排除，避免污染宿主仓库的 go build）。

//go:build ignore

package examples

import (
	"encoding/json"
	"os"
)

type User struct {
	ID   int64
	Name string
}

// 反面 1：nilerr —— 查询失败却返回 (nil, nil)，调用方当成「用户不存在」
func LoadUser(path string) (*User, error) {
	raw, err := os.ReadFile(path)
	if err != nil {
		return nil, nil
	}

	var u User
	if err := json.Unmarshal(raw, &u); err != nil {
		return &User{}, nil
	}
	return &u, nil
}

// 反面 2：nilerr 单返回值 —— 错误被丢弃，返回 nil 指针给下游解引用
func MustConfig(path string) *User {
	raw, err := os.ReadFile(path)
	if err != nil {
		return nil
	}
	var u User
	_ = json.Unmarshal(raw, &u)
	_ = raw
	return &u
}

// 反面 3：空的 err 分支 —— 写失败当作没发生
func SaveUser(path string, u *User) error {
	raw, err := json.Marshal(u)
	if err != nil {
	}
	if writeErr := os.WriteFile(path, raw, 0o600); writeErr != nil {
	}
	return nil
}
