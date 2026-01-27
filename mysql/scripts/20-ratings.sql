CREATE DATABASE ratings
DEFAULT CHARACTER SET 'utf8';

USE ratings;

CREATE TABLE ratings (
    sku varchar(80) NOT NULL,
    avg_rating DECIMAL(3, 2) NOT NULL,
    rating_count INT NOT NULL,
    PRIMARY KEY (sku)
) ENGINE=InnoDB;

-- FIX: MySQL 8.0 requires creating the user first, then granting permissions
CREATE USER IF NOT EXISTS 'ratings'@'%' IDENTIFIED BY 'iloveit';
GRANT ALL ON ratings.* TO 'ratings'@'%';