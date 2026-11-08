# Stage 1: Build the application
FROM maven:3.9.9-eclipse-temurin-21-alpine AS builder
WORKDIR /app
# Copy service files
COPY services/station-service/pom.xml ./
COPY services/station-service/src ./src
# Build
RUN mvn clean package -DskipTests
# Extract layers for better caching
RUN mkdir -p extracted && \
    java -Djarmode=layertools -jar target/*.jar extract --destination extracted
# Stage 2: Runtime image
FROM eclipse-temurin:21-jre-alpine
WORKDIR /app
# Install curl for health checks
RUN apk add --no-cache curl
# Non-root runtime user (fixed UID/GID). logs/ is writable for logback file appenders.
RUN addgroup -S -g 10001 app && \
    adduser -S -D -H -u 10001 -G app app && \
    mkdir -p /app/logs && \
    chown app:app /app/logs
# Copy layers
COPY --from=builder /app/extracted/dependencies/ ./
COPY --from=builder /app/extracted/spring-boot-loader/ ./
COPY --from=builder /app/extracted/snapshot-dependencies/ ./
COPY --from=builder /app/extracted/application/ ./
# Size the heap from the container memory limit (ECS task memory)
ENV JAVA_TOOL_OPTIONS="-XX:MaxRAMPercentage=75"
USER 10001:10001
EXPOSE 4004
ENTRYPOINT ["java", "org.springframework.boot.loader.launch.JarLauncher"]
