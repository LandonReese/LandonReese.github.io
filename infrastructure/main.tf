provider "aws" {
  region = "us-east-1"
}

resource "aws_dynamodb_table" "visitor_counter" {
  name           = "visitor-count"
  billing_mode   = "PROVISIONED"
  read_capacity  = 1
  write_capacity = 1
  hash_key       = "id"

  attribute {
    name = "id"
    type = "S"
  }
}

resource "aws_dynamodb_table" "rate_limiter" {
  name           = "visitor-counter-rate-limit"
  billing_mode   = "PROVISIONED"
  read_capacity  = 1
  write_capacity = 1
  hash_key       = "ip_address"

  attribute {
    name = "ip_address"
    type = "S"
  }

  ttl {
    attribute_name = "ttl"
    enabled        = true
  }
}

data "archive_file" "lambda_zip" {
  type        = "zip"
  source_file = "lambda_function.py"
  output_path = "lambda_function.zip"
}

resource "aws_lambda_function" "update_count" {
  filename      = "lambda_function.zip"
  function_name = "updateVisitorCount"
  role          = aws_iam_role.iam_for_lambda.arn
  handler       = "lambda_function.lambda_handler"
  runtime       = "python3.9"
  source_code_hash = data.archive_file.lambda_zip.output_base64sha256


  reserved_concurrent_executions = 5 
  
  timeout     = 10
  memory_size = 128
}

resource "aws_iam_role" "iam_for_lambda" {
  name = "iam_for_lambda"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
    }]
  })
}

resource "aws_iam_role_policy" "lambda_policy" {
  name = "lambda_db_policy"
  role = aws_iam_role.iam_for_lambda.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = ["dynamodb:UpdateItem", "dynamodb:GetItem", "dynamodb:PutItem", "dynamodb:DeleteItem"]
        Resource = [
          aws_dynamodb_table.visitor_counter.arn,
          aws_dynamodb_table.rate_limiter.arn
        ]
      }
    ]
  })
}

resource "aws_lambda_function_url" "test_live" {
  function_name      = aws_lambda_function.update_count.function_name
  authorization_type = "NONE"
  cors {
    allow_origins = ["*"]
    allow_methods = ["GET"]
  }
}

output "api_url" {
  value = aws_lambda_function_url.test_live.function_url
}