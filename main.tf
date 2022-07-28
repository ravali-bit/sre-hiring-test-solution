data "archive_file" "lambda_image_resizer" {
  type = "zip"

  source_dir  = "${path.module}/image-resizer"
  output_path = "${path.module}/image-resizer.zip"
}

resource "aws_s3_bucket" "lambda_image_resizer" {
    bucket = "${var.bucket_name}"
    acl = "${var.acl_value}"
}

resource "aws_s3_object" "lambda_image_resizer" {
  bucket = aws_s3_bucket.lambda_image_resizer.id

  key    = "image-resizer.zip"
  source = data.archive_file.lambda_image_resizer.output_path

  etag = filemd5(data.archive_file.lambda_image_resizer.output_path)
}

resource "aws_lambda_function" "image_resizer" {
  function_name = "image_resizer"

  s3_bucket = aws_s3_bucket.lambda_image_resizer.id
  s3_key    = aws_s3_object.lambda_image_resizer.key

  runtime = "nodejs12.x"
  handler = "hello.handler"

  source_code_hash = data.archive_file.lambda_image_resizer.output_base64sha256

  role = aws_iam_role.iam_img_resize_role.arn
}

resource "aws_cloudwatch_log_group" "image_resizer" {
  name = "/aws/lambda/${aws_lambda_function.image_resizer.function_name}"

  retention_in_days = 30
}

resource "aws_iam_role" "iam_img_resize_role" {
  name = "iam_img_resize_role"
  assume_role_policy = jsonencode({
  "Version": "2012-10-17",
  "Statement": [
    {
      "Action": "sts:AssumeRole",
      "Principal": {
        "Service": "lambda.amazonaws.com"
      },
      "Effect": "Allow",
      "Sid": ""
    }
  ]
 })
}

resource "aws_iam_policy" "iam_img_resize_policy" {
  name = "iam_img_resize_policy"

  policy = jsonencode({
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "logs:CreateLogGroup",
        "logs:CreateLogStream",
        "logs:PutLogEvents"
      ],
      "Resource": "arn:aws:logs:*:*:*"
    },
    {
      "Effect": "Allow",
      "Action": [
        "s3:GetObject",
        "s3:PutObject"
      ],
      "Resource": "arn:aws:s3:::${var.bucket_name}/*"
    }
  ]
})
}

resource "aws_iam_role_policy_attachment" "iam_img_resize_role-attach" {
  role       = aws_iam_role.iam_img_resize_role.name
  policy_arn = aws_iam_policy.iam_img_resize_policy.arn
}


resource "aws_apigatewayv2_api" "lambda" {
  name          = "serverless_lambda_gw"
  protocol_type = "HTTP"
}

resource "aws_apigatewayv2_stage" "lambda" {
  api_id = aws_apigatewayv2_api.lambda.id

  name        = "serverless_lambda_stage"
  auto_deploy = true

  access_log_settings {
    destination_arn = aws_cloudwatch_log_group.api_gw.arn

    format = jsonencode({
      requestId               = "$context.requestId"
      sourceIp                = "$context.identity.sourceIp"
      requestTime             = "$context.requestTime"
      protocol                = "$context.protocol"
      httpMethod              = "$context.httpMethod"
      resourcePath            = "$context.resourcePath"
      routeKey                = "$context.routeKey"
      status                  = "$context.status"
      responseLength          = "$context.responseLength"
      integrationErrorMessage = "$context.integrationErrorMessage"
      }
    )
  }
}

resource "aws_apigatewayv2_integration" "image_resizer" {
  api_id = aws_apigatewayv2_api.lambda.id

  integration_uri    = aws_lambda_function.image_resizer.invoke_arn
  integration_type   = "AWS_PROXY"
  integration_method = "POST"
}

resource "aws_apigatewayv2_route" "image_resizer" {
  api_id = aws_apigatewayv2_api.lambda.id

  route_key = "POST /image"
  target    = "integrations/${aws_apigatewayv2_integration.image_resizer.id}"
}

resource "aws_cloudwatch_log_group" "api_gw" {
  name = "/aws/api_gw/${aws_apigatewayv2_api.lambda.name}"

  retention_in_days = 30
}

resource "aws_lambda_permission" "api_gw" {
  statement_id  = "AllowExecutionFromAPIGateway"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.image_resizer.function_name
  principal     = "apigateway.amazonaws.com"

  source_arn = "${aws_apigatewayv2_api.lambda.execution_arn}/*/*"
}
