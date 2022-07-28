variable "bucket_name" {
    default = "terra-nodejs-docker-lambda-resizer1"
}

variable "acl_value" {
    default = "private"
}

output "resize_function" {
  value = "${aws_lambda_function.image_resizer.arn}"
}