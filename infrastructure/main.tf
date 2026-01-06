# infrastructure/main.tf
provider "aws" {
  region = "us-east-1"
}

# --- 1. The Database ---
resource "aws_dynamodb_table" "visitor_counter" {
  name           = "visitor-count"
  billing_mode   = "PAY_PER_REQUEST"
  hash_key       = "id"

  attribute {
    name = "id"
    type = "S"
  }
}

# --- 2. The Python Code Packaging ---
data "archive_file" "lambda_zip" {
  type        = "zip"
  source_file = "lambda_function.py"
  output_path = "lambda_function.zip"
}

# --- 3. The Lambda Function ---
resource "aws_lambda_function" "update_count" {
  filename      = "lambda_function.zip"
  function_name = "updateVisitorCount"
  role          = aws_iam_role.iam_for_lambda.arn
  handler       = "lambda_function.lambda_handler"
  runtime       = "python3.9"
  
  # Hashing ensures it only updates when code changes
  source_code_hash = data.archive_file.lambda_zip.output_base64sha256
}

# --- 4. Permissions (IAM) ---
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
  name = "lambda_dynamo_policy"
  role = aws_iam_role.iam_for_lambda.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = ["dynamodb:UpdateItem", "dynamodb:GetItem"]
      Resource = aws_dynamodb_table.visitor_counter.arn
    }]
  })
}

# --- 5. The Public URL ---
resource "aws_lambda_function_url" "test_live" {
  function_name      = aws_lambda_function.update_count.function_name
  authorization_type = "NONE"

  cors {
    allow_origins = ["*"] # Allows your GitHub page to access it
    allow_methods = ["GET"]
  }
}

# Output the URL so you can copy-paste it into JS
output "api_url" {
  value = aws_lambda_function_url.test_live.function_url
}