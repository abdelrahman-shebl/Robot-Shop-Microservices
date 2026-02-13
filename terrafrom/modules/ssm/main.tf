resource "aws_ssm_parameter" "mysql_creds" {
  name      = "/prod/mysql/credentials"
  type      = "SecureString"
  overwrite = true
  value = jsonencode({
    # MySQL Root Credentials
    MYSQL_ROOT_PASSWORD = var.MYSQL_ROOT_PASSWORD

    # Shipping MySQL Credentials
    SHIPPING_MYSQL_USER     = var.SHIPPING_MYSQL_USER
    SHIPPING_MYSQL_PASSWORD = var.SHIPPING_MYSQL_PASSWORD
    SHIPPING_MYSQL_DATABASE = var.SHIPPING_MYSQL_DATABASE

    # Ratings MySQL Credentials
    RATINGS_MYSQL_USER     = var.RATINGS_MYSQL_USER
    RATINGS_MYSQL_PASSWORD = var.RATINGS_MYSQL_PASSWORD
    RATINGS_MYSQL_DATABASE = var.RATINGS_MYSQL_DATABASE

  })
}

resource "aws_ssm_parameter" "mongo_creds" {
  name      = "/prod/mongo/credentials"
  type      = "SecureString"
  overwrite = true
  value = jsonencode({

    # MongoDB Root Credentials
    MONGO_INITDB_ROOT_USERNAME = var.MONGO_INITDB_ROOT_USERNAME
    MONGO_INITDB_ROOT_PASSWORD = var.MONGO_INITDB_ROOT_PASSWORD

    # Catalog MongoDB Credentials
    CATALOGUE_MONGO_USER     = var.CATALOGUE_MONGO_USER
    CATALOGUE_MONGO_PASSWORD = var.CATALOGUE_MONGO_PASSWORD
    CATALOGUE_MONGO_DATABASE = var.CATALOGUE_MONGO_DATABASE

    # Users MongoDB Credentials
    USER_MONGO_USER     = var.USER_MONGO_USER
    USER_MONGO_PASSWORD = var.USER_MONGO_PASSWORD
    USER_MONGO_DATABASE = var.USER_MONGO_DATABASE
  })
}

resource "aws_ssm_parameter" "dojo_creds" {
  name      = "/prod/dojo/credentials"
  type      = "SecureString"
  overwrite = true
  value = jsonencode({

    # Dojo Credentials
    DD_ADMIN_USER     = var.DD_ADMIN_USER
    DD_ADMIN_PASSWORD = var.DD_ADMIN_PASSWORD
  })
}
