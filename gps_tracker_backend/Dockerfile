# Build stage
FROM maven:3.9-eclipse-temurin-17 AS build
WORKDIR /app
COPY pom.xml .
# Download dependencies in a separate layer for faster caching
RUN mvn dependency:go-offline -B
COPY src ./src
RUN mvn clean package -DskipTests

# Runtime stage
FROM eclipse-temurin:17-jre-jammy
WORKDIR /app
COPY --from=build /app/target/tracker-*.jar app.jar

# Expose Netty TCP (GPS JT808) & Spring Boot HTTP/WebSocket
EXPOSE 8000
EXPOSE 8081

ENTRYPOINT ["java", "-jar", "app.jar"]
