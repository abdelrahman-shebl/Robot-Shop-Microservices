#!/bin/bash
set -e

# Create shipping database and user from environment variables
mysql -u root -p"${MYSQL_ROOT_PASSWORD}" <<-EOSQL
    CREATE DATABASE IF NOT EXISTS ${SHIPPING_MYSQL_DATABASE} DEFAULT CHARACTER SET 'utf8';
    CREATE USER IF NOT EXISTS '${SHIPPING_MYSQL_USER}'@'%' IDENTIFIED WITH mysql_native_password BY '${SHIPPING_MYSQL_PASSWORD}';
    GRANT ALL ON ${SHIPPING_MYSQL_DATABASE}.* TO '${SHIPPING_MYSQL_USER}'@'%';
EOSQL

# Create ratings database and user from environment variables
mysql -u root -p"${MYSQL_ROOT_PASSWORD}" <<-EOSQL
    CREATE DATABASE IF NOT EXISTS ${RATINGS_MYSQL_DATABASE} DEFAULT CHARACTER SET 'utf8';
    
    CREATE USER IF NOT EXISTS '${RATINGS_MYSQL_USER}'@'%' IDENTIFIED BY '${RATINGS_MYSQL_PASSWORD}';
    GRANT ALL ON ${RATINGS_MYSQL_DATABASE}.* TO '${RATINGS_MYSQL_USER}'@'%';
    
    USE ${RATINGS_MYSQL_DATABASE};
    
    CREATE TABLE IF NOT EXISTS ratings (
        sku varchar(80) NOT NULL,
        avg_rating DECIMAL(3, 2) NOT NULL,
        rating_count INT NOT NULL,
        PRIMARY KEY (sku)
    ) ENGINE=InnoDB;
EOSQL

echo "Shipping and Ratings databases and users created successfully"
