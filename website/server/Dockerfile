FROM maven:3.9.9-eclipse-temurin-17 AS build
WORKDIR /workspace
COPY pom.xml .
RUN mvn -q -DskipTests dependency:go-offline
COPY src src
RUN mvn -q -DskipTests package

FROM eclipse-temurin:17-jre
RUN useradd --system --uid 10001 --create-home nookflow
USER nookflow
WORKDIR /app
COPY --from=build /workspace/target/license-server-1.0.0.jar app.jar
EXPOSE 8787
ENTRYPOINT ["java", "-XX:MaxRAMPercentage=70", "-XX:InitialRAMPercentage=20", "-XX:+ExitOnOutOfMemoryError", "-jar", "/app/app.jar"]
