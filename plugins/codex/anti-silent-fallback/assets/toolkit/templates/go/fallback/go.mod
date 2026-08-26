// 占位 module —— 只为了让 `go build ./...` / `go vet ./...` 能在工具包内独立跑通自测。
//
// 接入宿主仓库时：删除本文件，把 fallback.go 放到宿主 module 里
// （例如 internal/fallback/fallback.go），import 路径随宿主 module 走。
module example.com/PLACEHOLDER/fallback

go 1.21
