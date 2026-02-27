package com.instana.robotshop.shipping;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import javax.sql.DataSource;
import org.springframework.boot.jdbc.DataSourceBuilder;
import org.springframework.context.annotation.Configuration;
import org.springframework.context.annotation.Bean;

@Configuration
public class JpaConfig {
    private static final Logger logger = LoggerFactory.getLogger(JpaConfig.class);

    @Bean
    public DataSource getDataSource() {
        String host = System.getenv("MYSQL_HOST");
        String user = System.getenv("MYSQL_USER");
        String password = System.getenv("MYSQL_PASSWORD");
        String database = System.getenv("MYSQL_DATABASE");
        
        if (host == null || user == null || password == null || database == null) {
            throw new RuntimeException("MYSQL_HOST, MYSQL_USER, MYSQL_PASSWORD, and MYSQL_DATABASE environment variables are required");
        }
        
        String JDBC_URL = String.format("jdbc:mysql://%s:3306/%s?useSSL=false&autoReconnect=true", host, database);

        logger.info("jdbc url {}", JDBC_URL);

        DataSourceBuilder bob = DataSourceBuilder.create();
        bob.driverClassName("com.mysql.jdbc.Driver");
        bob.url(JDBC_URL);
        bob.username(user);
        bob.password(password);

        return bob.build();
    }
}
