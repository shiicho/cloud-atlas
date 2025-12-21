# count-demo.tf
# count 示例（反模式演示）
#
# 警告：本文件演示 count 的 Index Shift 问题！
# 生产环境中应优先使用 for_each。

# -----------------------------------------------------------------------------
# count 基本用法
# -----------------------------------------------------------------------------
# count = N 会创建 N 个资源实例
# 使用 count.index 访问索引（0, 1, 2...）

# 取消注释以启用 count 演示
# resource "aws_iam_user" "team_count" {
#   count = length(var.users)
#   name  = "count-demo-${var.users[count.index]}"
#
#   tags = {
#     Index = count.index
#   }
# }

# -----------------------------------------------------------------------------
# Index Shift 问题演示
# -----------------------------------------------------------------------------
#
# 初始状态：var.users = ["alice", "bob", "charlie"]
#
#   aws_iam_user.team_count[0] = "alice"
#   aws_iam_user.team_count[1] = "bob"
#   aws_iam_user.team_count[2] = "charlie"
#
# 在中间插入 david：var.users = ["alice", "david", "bob", "charlie"]
#
#   aws_iam_user.team_count[0] = "alice"    ✓ 不变
#   aws_iam_user.team_count[1] = "david"    ✗ bob → david（重建！）
#   aws_iam_user.team_count[2] = "bob"      ✗ charlie → bob（重建！）
#   aws_iam_user.team_count[3] = "charlie"  + 新建
#
# 灾难：bob 和 charlie 会被删除重建！
#       如果这些用户有关联资源（Role, Policy），都会受影响。
# -----------------------------------------------------------------------------

# -----------------------------------------------------------------------------
# for_each 对比
# -----------------------------------------------------------------------------
# 使用 for_each 避免 Index Shift

resource "aws_iam_user" "team_foreach" {
  for_each = var.users_set
  name     = "foreach-demo-${each.key}"

  tags = {
    Method = "for_each"
  }
}

# -----------------------------------------------------------------------------
# for_each 的稳定性
# -----------------------------------------------------------------------------
#
# 初始状态：var.users_set = ["alice", "bob", "charlie"]
#
#   aws_iam_user.team_foreach["alice"]
#   aws_iam_user.team_foreach["bob"]
#   aws_iam_user.team_foreach["charlie"]
#
# 添加 david：var.users_set = ["alice", "bob", "charlie", "david"]
#
#   aws_iam_user.team_foreach["alice"]    ✓ 不变
#   aws_iam_user.team_foreach["bob"]      ✓ 不变
#   aws_iam_user.team_foreach["charlie"]  ✓ 不变
#   aws_iam_user.team_foreach["david"]    + 新建
#
# 完美：只有 david 被创建，其他用户不受影响！
# -----------------------------------------------------------------------------

# -----------------------------------------------------------------------------
# count 的正确使用场景
# -----------------------------------------------------------------------------
#
# count 适合：
# 1. 条件创建（count = var.enabled ? 1 : 0）
# 2. 完全相同的资源（没有区分需求）
# 3. 数量固定，不会在中间增删
#
# 示例：条件创建
# resource "aws_cloudwatch_log_group" "app" {
#   count = var.enable_logging ? 1 : 0
#   name  = "/app/logs"
# }
# -----------------------------------------------------------------------------
