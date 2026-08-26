<?php
/**
 * 反面教材：PHP 静默降级。
 *
 * 预期命中：
 *   - silent-fallback-php-empty-catch
 *   - silent-fallback-php-error-suppression
 *
 * 注意：下面这行 docblock 里的 @method 不应该被 @ 抑制符规则命中（低误报验证点）。
 * @method array listOrders(string $uid)
 */

namespace Examples;

class OrderRepository
{
    // 反面 1：空 catch —— 数据库异常被吞掉，返回值假装一切正常
    public function save(array $order): bool
    {
        try {
            $this->db->insert('orders', $order);
        } catch (\Throwable $e) {
        }

        return true;
    }

    // 反面 2：@ 抑制符 —— 文件读不到时拿不到任何原因
    public function loadTemplate(string $path): string
    {
        $raw = @file_get_contents($path);

        return $raw === false ? '' : $raw;
    }

    // 反面 3：@ 抑制符 + 静默默认值
    public function cleanup(string $path): void
    {
        @unlink($path);
    }
}
