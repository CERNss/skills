// 反面教材：TypeScript 静默降级。
//
// 预期命中：
//   - silent-fallback-js-empty-catch
//   - silent-fallback-js-catch-return-default

interface Order {
  id: string;
  amount: number;
}

// 反面 1：空 catch —— 上报失败被彻底吞掉
export function reportOrder(order: Order): void {
  try {
    navigator.sendBeacon("/api/report", JSON.stringify(order));
  } catch (e) {
  }
}

// 反面 2：catch 返回默认值 —— 调用方分不清「没有订单」和「接口挂了」
export async function listOrders(uid: string): Promise<Order[]> {
  try {
    const resp = await fetch(`/api/users/${uid}/orders`);
    return (await resp.json()) as Order[];
  } catch (e) {
    return [];
  }
}

// 反面 3：可选 catch binding 的空块
export function parseConfig(raw: string): unknown {
  let parsed: unknown = null;
  try {
    parsed = JSON.parse(raw);
  } catch {
  }
  return parsed;
}

// 反面 4：catch 返回 null，凭据校验失败被当成「未登录」
export async function currentUser(): Promise<unknown> {
  try {
    const resp = await fetch("/api/me");
    return await resp.json();
  } catch (err) {
    return null;
  }
}
