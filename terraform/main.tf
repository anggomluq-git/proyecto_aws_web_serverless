provider "aws" {
  region = "eu-north-1"
}

# ============================================================
# DYNAMODB: tabla con el contador de visitas
# ============================================================
resource "aws_dynamodb_table" "Cuenta_Visitas_tf" {
  name         = "Cuenta_Visitas_tf"
  billing_mode = "PAY_PER_REQUEST" # pago por uso, sin capacidad reservada
  hash_key     = "id"

  attribute {
    name = "id"
    type = "S"
  }
}

# Item inicial del contador (empieza en 0)
resource "aws_dynamodb_table_item" "item_tf" {
  table_name = aws_dynamodb_table.Cuenta_Visitas_tf.name
  hash_key   = aws_dynamodb_table.Cuenta_Visitas_tf.hash_key

  item = <<ITEM
{
  "id": {"S": "cuenta_visitas"},
  "num_visitas": {"N": "0"}
}
ITEM

  # La Lambda modifica num_visitas en cada visita, asi que Terraform
  # no debe tratarlo como un cambio ni volver a ponerlo a 0.
  lifecycle {
    ignore_changes = [item]
  }
}

# ============================================================
# IAM: rol de ejecucion de la Lambda
# ============================================================

# 1. Permite que el servicio Lambda asuma el rol
data "aws_iam_policy_document" "assume_role" {
  statement {
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }

    actions = ["sts:AssumeRole"]
  }
}

# 2. El rol, usando la politica de confianza anterior
resource "aws_iam_role" "funcion_lambda_contador-role-tf" {
  name               = "lambda_execution_role-tf"
  assume_role_policy = data.aws_iam_policy_document.assume_role.json
}

# 3. Permiso minimo: solo UpdateItem y solo sobre esta tabla
data "aws_iam_policy_document" "dynamodb_access" {
  statement {
    effect    = "Allow"
    actions   = ["dynamodb:UpdateItem"]
    resources = [aws_dynamodb_table.Cuenta_Visitas_tf.arn]
  }
}

# 4. Asocia ese permiso al rol
resource "aws_iam_role_policy" "dynamodb_access" {
  name   = "dynamodb_access"
  role   = aws_iam_role.funcion_lambda_contador-role-tf.id
  policy = data.aws_iam_policy_document.dynamodb_access.json
}

# 5. Permite a la Lambda escribir logs en CloudWatch
resource "aws_iam_role_policy_attachment" "lambda_logs" {
  role       = aws_iam_role.funcion_lambda_contador-role-tf.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

# Permite que API Gateway invoque la Lambda
resource "aws_lambda_permission" "api_gateway" {
  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.funcion_lambda_contador_tf.function_name
  principal     = "apigateway.amazonaws.com"
}

# ============================================================
# LAMBDA: funcion que incrementa el contador
# ============================================================

# Empaqueta el codigo Python en un zip
data "archive_file" "archivo_lambda" {
  type        = "zip"
  source_file = "${path.module}/../lmbda/lambda_function.py"
  output_path = "${path.module}/../lmbda/lambda_function.zip"
}

resource "aws_lambda_function" "funcion_lambda_contador_tf" {
  filename         = data.archive_file.archivo_lambda.output_path
  function_name    = "funcion_lambda_contador_tf"
  role             = aws_iam_role.funcion_lambda_contador-role-tf.arn
  handler          = "lambda_function.lambda_handler"
  source_code_hash = data.archive_file.archivo_lambda.output_base64sha256 # redespliega si cambia el codigo

  runtime = "python3.13"
}

# ============================================================
# API GATEWAY (HTTP API): expone la Lambda mediante GET /visitas
# ============================================================
resource "aws_apigatewayv2_api" "http_api_cuenta_visitas_tf" {
  name          = "http_api_cuenta_visitas_tf"
  protocol_type = "HTTP"
}

# Stage por defecto, con despliegue automatico de cambios
resource "aws_apigatewayv2_stage" "default" {
  api_id      = aws_apigatewayv2_api.http_api_cuenta_visitas_tf.id
  name        = "$default"
  auto_deploy = true
}

# Conecta la API con la Lambda (integracion proxy)
resource "aws_apigatewayv2_integration" "integracion_tf" {
  api_id                 = aws_apigatewayv2_api.http_api_cuenta_visitas_tf.id
  integration_type       = "AWS_PROXY"
  integration_method     = "POST"
  integration_uri        = aws_lambda_function.funcion_lambda_contador_tf.invoke_arn
  payload_format_version = "2.0"
}

# Ruta: las peticiones GET /visitas van a la Lambda
resource "aws_apigatewayv2_route" "ruta_tf" {
  api_id    = aws_apigatewayv2_api.http_api_cuenta_visitas_tf.id
  route_key = "GET /visitas"
  target    = "integrations/${aws_apigatewayv2_integration.integracion_tf.id}"
}

# ============================================================
# S3: bucket privado con los archivos del frontend
# ============================================================
variable "bucket_name" {
  default = "web-bucket-tf"
}

resource "aws_s3_bucket" "s3-static-website" {
  bucket        = var.bucket_name
  force_destroy = true # permite borrar el bucket aunque tenga archivos
}

# Bloquea todo acceso publico: solo CloudFront podra leer el bucket
resource "aws_s3_bucket_public_access_block" "static_site_bucket_public_access" {
  bucket = aws_s3_bucket.s3-static-website.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

data "aws_s3_bucket" "selected_bucket" {
  bucket = aws_s3_bucket.s3-static-website.id
}

# ============================================================
# CLOUDFRONT: unico punto de entrada (frontend + API)
# ============================================================

# OAC: CloudFront firma sus peticiones a S3 para poder leer el bucket privado
resource "aws_cloudfront_origin_access_control" "cf-s3-oac" {
  name                              = "CloudFront S3 OAC"
  description                       = "CloudFront S3 OAC"
  origin_access_control_origin_type = "s3"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
}

# Politicas gestionadas por AWS (se buscan por nombre)
data "aws_cloudfront_cache_policy" "caching_disabled" {
  name = "Managed-CachingDisabled"
}

data "aws_cloudfront_origin_request_policy" "all_viewer_except_host" {
  name = "Managed-AllViewerExceptHostHeader"
}

resource "aws_cloudfront_distribution" "cf-dist" {
  enabled             = true
  default_root_object = "index.html"

  # Origen 1: S3 (frontend)
  origin {
    domain_name              = aws_s3_bucket.s3-static-website.bucket_regional_domain_name
    origin_id                = aws_s3_bucket.s3-static-website.id
    origin_access_control_id = aws_cloudfront_origin_access_control.cf-s3-oac.id
  }

  # Origen 2: API Gateway (backend)
  origin {
    origin_id   = "api-gateway"
    domain_name = replace(aws_apigatewayv2_api.http_api_cuenta_visitas_tf.api_endpoint, "https://", "")

    custom_origin_config {
      http_port              = 80
      https_port             = 443
      origin_protocol_policy = "https-only"
      origin_ssl_protocols   = ["TLSv1.2"]
    }
  }

  # Por defecto, todo va a S3 con 24 horas de cache
  default_cache_behavior {
    allowed_methods        = ["GET", "HEAD"]
    cached_methods         = ["GET", "HEAD"]
    target_origin_id       = aws_s3_bucket.s3-static-website.id
    cache_policy_id        = "658327ea-f89d-4fab-a63d-7e88639e58f6" # 24 horas de cache
    viewer_protocol_policy = "redirect-to-https"
  }

  # /visitas va a la API sin cache, para que el contador sea siempre en vivo
  ordered_cache_behavior {
    path_pattern             = "/visitas"
    target_origin_id         = "api-gateway"
    viewer_protocol_policy   = "https-only"
    allowed_methods          = ["GET", "HEAD"]
    cached_methods           = ["GET", "HEAD"]
    cache_policy_id          = data.aws_cloudfront_cache_policy.caching_disabled.id
    origin_request_policy_id = data.aws_cloudfront_origin_request_policy.all_viewer_except_host.id
  }

  price_class = "PriceClass_100" 

  # Solo se permite el acceso desde España
  restrictions {
    geo_restriction {
      restriction_type = "whitelist"
      locations        = ["ES"]
    }
  }

  # Certificado HTTPS por defecto de cloudfront.net
  viewer_certificate {
    cloudfront_default_certificate = true
  }
}

# ============================================================
# Politica del bucket: solo esta distribucion de CloudFront puede leer
# ============================================================
data "aws_iam_policy_document" "s3_bucket_policy" {
  statement {
    actions   = ["s3:GetObject"]
    resources = ["${aws_s3_bucket.s3-static-website.arn}/*"]

    principals {
      type        = "Service"
      identifiers = ["cloudfront.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "AWS:SourceArn"
      values   = [aws_cloudfront_distribution.cf-dist.arn]
    }
  }
}

resource "aws_s3_bucket_policy" "static_site_bucket_policy" {
  bucket = aws_s3_bucket.s3-static-website.id
  policy = data.aws_iam_policy_document.s3_bucket_policy.json
}

# ============================================================
# PARAMETER STORE: valores que lee el workflow del frontend
# ============================================================
resource "aws_ssm_parameter" "frontend_bucket" {
  name  = "/proyecto_aws_web/frontend_bucket"
  type  = "String"
  value = aws_s3_bucket.s3-static-website.bucket
}

resource "aws_ssm_parameter" "cloudfront_id" {
  name  = "/proyecto_aws_web/cloudfront_id"
  type  = "String"
  value = aws_cloudfront_distribution.cf-dist.id
}