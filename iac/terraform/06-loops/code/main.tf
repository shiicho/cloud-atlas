# main.tf
# for_each 示例
#
# 演示使用 for_each 批量创建资源。
# 相比 count，for_each 使用 key 而不是 index，更加稳定。

# -----------------------------------------------------------------------------
# Random ID
# -----------------------------------------------------------------------------

resource "random_id" "suffix" {
  byte_length = 4
}

# -----------------------------------------------------------------------------
# S3 Buckets - 使用 for_each
# -----------------------------------------------------------------------------
# for_each 接受 map 或 set
# 每个元素创建一个资源实例
# 资源地址格式：aws_s3_bucket.apps["key"]

resource "aws_s3_bucket" "apps" {
  for_each = var.app_buckets

  # each.key = map 的 key（"api", "web", "data"）
  bucket = "${var.project}-${each.key}-${random_id.suffix.hex}"

  tags = {
    App         = each.key
    Environment = var.environment
  }
}

# -----------------------------------------------------------------------------
# S3 Bucket Versioning - 引用 for_each 资源
# -----------------------------------------------------------------------------

resource "aws_s3_bucket_versioning" "apps" {
  for_each = var.app_buckets

  # 引用对应的 bucket
  bucket = aws_s3_bucket.apps[each.key].id

  versioning_configuration {
    # each.value = map 的 value（整个 object）
    status = each.value.versioning ? "Enabled" : "Disabled"
  }
}

# -----------------------------------------------------------------------------
# for_each 优势演示
# -----------------------------------------------------------------------------
#
# 初始状态（3 个 bucket）：
#   aws_s3_bucket.apps["api"]
#   aws_s3_bucket.apps["web"]
#   aws_s3_bucket.apps["data"]
#
# 添加新 bucket（添加 "logs" key）：
#   aws_s3_bucket.apps["logs"] will be created
#   其他 bucket 不受影响！
#
# 删除 bucket（删除 "web" key）：
#   aws_s3_bucket.apps["web"] will be destroyed
#   其他 bucket 不受影响！
#
# 对比 count：
#   如果使用 count + index，删除中间元素会导致后续元素重建
# -----------------------------------------------------------------------------
