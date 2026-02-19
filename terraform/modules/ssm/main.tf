resource "aws_ssm_parameter" "mysql_creds" {
  name      = "/prod/mysql/credentials"
  type      = "SecureString"
  overwrite = true
  value = jsonencode({
    # MySQL Root Credentials
    MYSQL_ROOT_PASSWORD = var.secrets_map.MYSQL_ROOT_PASSWORD

    # Shipping MySQL Credentials
    SHIPPING_MYSQL_USER     = var.secrets_map.SHIPPING_MYSQL_USER
    SHIPPING_MYSQL_PASSWORD = var.secrets_map.SHIPPING_MYSQL_PASSWORD
    SHIPPING_MYSQL_DATABASE = var.secrets_map.SHIPPING_MYSQL_DATABASE

    # Ratings MySQL Credentials
    RATINGS_MYSQL_USER     = var.secrets_map.RATINGS_MYSQL_USER
    RATINGS_MYSQL_PASSWORD = var.secrets_map.RATINGS_MYSQL_PASSWORD
    RATINGS_MYSQL_DATABASE = var.secrets_map.RATINGS_MYSQL_DATABASE

  })
}

resource "aws_ssm_parameter" "mongo_creds" {
  name      = "/prod/mongo/credentials"
  type      = "SecureString"
  overwrite = true
  value = jsonencode({

    # MongoDB Root Credentials
    MONGO_INITDB_ROOT_USERNAME = var.secrets_map.MONGO_INITDB_ROOT_USERNAME
    MONGO_INITDB_ROOT_PASSWORD = var.secrets_map.MONGO_INITDB_ROOT_PASSWORD

    # Catalog MongoDB Credentials
    CATALOGUE_MONGO_USER     = var.secrets_map.CATALOGUE_MONGO_USER
    CATALOGUE_MONGO_PASSWORD = var.secrets_map.CATALOGUE_MONGO_PASSWORD
    CATALOGUE_MONGO_DATABASE = var.secrets_map.CATALOGUE_MONGO_DATABASE

    # Users MongoDB Credentials
    USER_MONGO_USER     = var.secrets_map.USER_MONGO_USER
    USER_MONGO_PASSWORD = var.secrets_map.USER_MONGO_PASSWORD
    USER_MONGO_DATABASE = var.secrets_map.USER_MONGO_DATABASE
    
    MONGODB_URI = "mongodb://${var.secrets_map.MONGO_INITDB_ROOT_USERNAME}:${var.secrets_map.MONGO_INITDB_ROOT_PASSWORD}@mongodb:27017/admin?authSource=admin"
  })
}

resource "aws_ssm_parameter" "dojo_creds" {
  name      = "/prod/dojo/credentials"
  type      = "SecureString"
  overwrite = true
  value = jsonencode({

    # Dojo Credentials
    DD_ADMIN_PASSWORD             = var.secrets_map.DD_ADMIN_PASSWORD
    METRICS_HTTP_AUTH_PASSWORD    = var.secrets_map.METRICS_HTTP_AUTH_PASSWORD
    DD_SECRET_KEY                 = var.secrets_map.DD_SECRET_KEY
    DD_CREDENTIAL_AES_256_KEY     = var.secrets_map.DD_CREDENTIAL_AES_256_KEY
  })
}
