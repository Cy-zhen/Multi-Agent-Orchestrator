# API 设计规范

## 核心规则

### RESTful 设计
- URL 用名词复数：`/api/v1/users`，不用动词
- HTTP 方法语义：GET 查询 / POST 创建 / PUT 全量更新 / PATCH 部分更新 / DELETE 删除
- 状态码准确：200 成功 / 201 创建 / 400 客户端错误 / 401 未认证 / 403 无权限 / 404 不存在 / 500 服务错误
- 分页格式统一：`?page=1&limit=20`，响应包含 `total` / `page` / `limit`

### 统一响应格式
```json
{
  "code": 0,
  "message": "success",
  "data": {},
  "timestamp": 1711234567
}
```

### 输入校验
- 所有外部输入必须校验（类型、长度、范围、格式）
- 校验失败返回 400 + 具体字段错误信息
- 不要信任客户端传来的任何数据

### 错误处理
- 全局错误中间件，不在每个 handler 里 try/catch
- 区分 业务错误（用 code）和 系统错误（用 HTTP 500）
- 错误日志包含 request_id 用于追踪

### 安全
- 敏感字段（密码/token）不出现在日志
- API Key / JWT 校验放中间件，不要在 handler 里重复
- 速率限制：公共 API 100 req/min，认证 API 1000 req/min

### 禁止
- ❌ 在 handler 里直接写 SQL（用 Repository 模式）
- ❌ 硬编码密钥/配置（用环境变量）
- ❌ 返回 200 + `{"error": "..."}` 的假成功
