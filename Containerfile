FROM registry.access.redhat.com/ubi9/openjdk-21-runtime:latest

USER 0
WORKDIR /deployments
COPY target/customer-rule-poc.jar /deployments/application.jar
RUN chgrp -R 0 /deployments && chmod -R g=u /deployments

USER 1001
EXPOSE 8080 8081
ENTRYPOINT ["java", "-Djava.io.tmpdir=/tmp", "-jar", "/deployments/application.jar"]
