resource "aws_dynamodb_table" "scores" {
  name         = local.table_name
  billing_mode = "PAY_PER_REQUEST" # scales with load, no capacity planning, ~free at demo volume

  hash_key = "pk"

  attribute {
    name = "pk"
    type = "S"
  }

  attribute {
    name = "gsi1pk"
    type = "S"
  }

  attribute {
    name = "gsi1sk"
    type = "N"
  }

  global_secondary_index {
    name            = "gsi1" # leaderboard: gsi1pk="LB", gsi1sk=best_ms (ascending)
    hash_key        = "gsi1pk"
    range_key       = "gsi1sk"
    projection_type = "ALL"
  }

  point_in_time_recovery {
    enabled = true
  }
}
