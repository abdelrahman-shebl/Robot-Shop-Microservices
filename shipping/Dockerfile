# Stage 1: Build 
# We use the specific Alpine Maven image you requested.
# This is much smaller than the standard Maven image but works the same.
FROM maven:3.9.6-eclipse-temurin-17-alpine AS build

WORKDIR /opt/shipping

COPY pom.xml .

# Download dependencies
RUN mvn dependency:go-offline -B

COPY src ./src

# Build the app
RUN mvn package -DskipTests

# ---

# Stage 2: Run
# We use the specific JDK Alpine image you requested.
FROM eclipse-temurin:17-jdk-alpine-3.22

# Create non-root user with specific UID/GID
RUN addgroup -g 2000 appuser && adduser -u 1000 -G appuser -s /sbin/nologin -D appuser

WORKDIR /opt/shipping

EXPOSE 8080

ENV CART_ENDPOINT=cart:8080 \
    DB_HOST=mysql

# Copy the JAR from the builder stage
COPY --from=build /opt/shipping/target/shipping-*.jar shipping.jar

# Fix ownership
RUN chown -R appuser:appuser /opt/shipping

USER appuser

# Run the application
CMD ["java", "-Xmn256m", "-Xmx768m", "-jar", "shipping.jar"]