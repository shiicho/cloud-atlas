# functions.tf
# 常用函数示例
#
# Terraform 提供丰富的内置函数用于数据处理。
# 完整列表：https://developer.hashicorp.com/terraform/language/functions

locals {
  # -------------------------------------------------------------------------
  # 字符串函数
  # -------------------------------------------------------------------------

  # format - 格式化字符串
  formatted_name = format("%s-%s-%s", var.project, var.environment, "app")

  # join - 连接列表元素
  joined_users = join(", ", var.users)

  # split - 分割字符串
  split_demo = split("-", "a-b-c")  # ["a", "b", "c"]

  # upper / lower - 大小写转换
  upper_name = upper(var.project)
  lower_name = lower(var.project)

  # replace - 替换字符
  replaced = replace("hello-world", "-", "_")  # "hello_world"

  # trimprefix / trimsuffix - 去除前后缀
  trimmed = trimprefix("Mr. John", "Mr. ")  # "John"

  # -------------------------------------------------------------------------
  # 集合函数
  # -------------------------------------------------------------------------

  # length - 获取长度
  users_count = length(var.users)

  # concat - 连接列表
  all_users = concat(var.users, ["extra1", "extra2"])

  # distinct - 去重
  unique_items = distinct(["a", "b", "a", "c"])  # ["a", "b", "c"]

  # flatten - 扁平化嵌套列表
  flattened = flatten([["a", "b"], ["c", "d"]])  # ["a", "b", "c", "d"]

  # keys / values - 获取 map 的键/值
  bucket_names = keys(var.app_buckets)      # ["api", "data", "web"]
  bucket_configs = values(var.app_buckets)  # [{versioning = true}, ...]

  # lookup - 安全获取 map 值（带默认值）
  found_value = lookup(var.app_buckets, "api", { versioning = false })

  # merge - 合并 maps
  merged_tags = merge(
    { Project = var.project },
    { Environment = var.environment }
  )

  # contains - 检查元素是否存在
  has_alice = contains(var.users, "alice")  # true

  # -------------------------------------------------------------------------
  # 类型转换函数
  # -------------------------------------------------------------------------

  # tolist / toset / tomap
  users_as_set = toset(var.users)

  # tonumber / tostring / tobool
  string_number = tostring(42)  # "42"

  # try - 尝试表达式，失败返回默认值
  safe_value = try(var.app_buckets["nonexistent"].versioning, false)

  # coalesce - 返回第一个非空值
  first_nonempty = coalesce("", "default")  # "default"

  # -------------------------------------------------------------------------
  # 编码函数
  # -------------------------------------------------------------------------

  # jsonencode / jsondecode
  json_string = jsonencode({
    name    = var.project
    version = "1.0"
  })

  # yamlencode
  yaml_string = yamlencode({
    name    = var.project
    version = "1.0"
  })

  # base64encode / base64decode
  encoded = base64encode("hello")  # "aGVsbG8="

  # -------------------------------------------------------------------------
  # 文件函数
  # -------------------------------------------------------------------------

  # file - 读取文件内容
  # readme = file("${path.module}/README.md")

  # fileexists - 检查文件是否存在
  # has_readme = fileexists("${path.module}/README.md")

  # templatefile - 渲染模板
  # config = templatefile("${path.module}/config.tpl", {
  #   db_host = var.db_host
  # })

  # -------------------------------------------------------------------------
  # 数学函数
  # -------------------------------------------------------------------------

  # min / max
  min_value = min(1, 2, 3)  # 1
  max_value = max(1, 2, 3)  # 3

  # abs - 绝对值
  absolute = abs(-5)  # 5

  # ceil / floor - 向上/向下取整
  ceiling = ceil(4.3)  # 5
  floored = floor(4.7)  # 4

  # -------------------------------------------------------------------------
  # for 表达式
  # -------------------------------------------------------------------------

  # List → List（转换）
  upper_users = [for user in var.users : upper(user)]

  # List → Map（转换）
  user_emails = { for user in var.users : user => "${user}@example.com" }

  # List → List（带过滤）
  long_names = [for user in var.users : user if length(user) > 3]

  # Map → Map（转换 values）
  versioning_status = {
    for key, config in var.app_buckets : key => config.versioning ? "Enabled" : "Disabled"
  }
}

# -----------------------------------------------------------------------------
# 输出函数结果（用于验证）
# -----------------------------------------------------------------------------

output "function_demos" {
  value = {
    formatted_name  = local.formatted_name
    joined_users    = local.joined_users
    users_count     = local.users_count
    upper_users     = local.upper_users
    user_emails     = local.user_emails
    long_names      = local.long_names
    bucket_names    = local.bucket_names
  }
}
