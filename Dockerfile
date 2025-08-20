# Build with JDK
FROM maven:3.9.8-eclipse-temurin-17 AS build
WORKDIR /app
COPY pom.xml .
RUN mvn -B -q -DskipTests dependency:go-offline
COPY src ./src
RUN mvn -B -DskipTests package

# Run with JRE
FROM eclipse-temurin:17-jre-jammy
WORKDIR /opt/app
ARG BUILD_NUMBER=0
ARG GIT_SHA=dev
ENV APP_BUILD_NUMBER=${BUILD_NUMBER} APP_GIT_SHA=${GIT_SHA} \
    JAVA_OPTS="-XX:+UseContainerSupport -XX:MaxRAMPercentage=75.0"
COPY --from=build /app/target/*SNAPSHOT*.jar app.jar
EXPOSE 8080
HEALTHCHECK --interval=30s --timeout=3s --start-period=20s --retries=3 \
  CMD wget -qO- http://127.0.0.1:8080/actuator/health || exit 1
ENTRYPOINT ["sh","-c","java $JAVA_OPTS -jar app.jar"]
