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
        String JDBC_URL = System.getenv("SPRING_DATASOURCE_URL");
        if (JDBC_URL == null || JDBC_URL.isEmpty()) {
            throw new RuntimeException("SPRING_DATASOURCE_URL environment variable is required");
        }

        logger.info("jdbc url {}", JDBC_URL);

        DataSourceBuilder bob = DataSourceBuilder.create();
        bob.driverClassName("com.mysql.jdbc.Driver");
        bob.url(JDBC_URL);

        return bob.build();
    }
}
