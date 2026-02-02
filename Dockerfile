# syntax=artifacts-we1.farfetch.net/dockerio-docker-all/docker/dockerfile:1

ARG FROM_REPO_MAVEN
ARG FROM_TAG_MAVEN

FROM ${FROM_REPO_MAVEN}:${FROM_TAG_MAVEN} AS build

ARG RELEASE_VERSION
ARG REGISTRY_USERNAME
ARG REGISTRY_API_KEY
RUN createSettingsXml ${REGISTRY_USERNAME} ${REGISTRY_API_KEY}

RUN mkdir -p /home/ffuser/app
COPY --chown=ffuser:ffuser pom.xml /home/ffuser/app/pom.xml
COPY --chown=ffuser:ffuser src /home/ffuser/app/src
WORKDIR /home/ffuser/app

RUN mvn --no-transfer-progress versions:set -DnewVersion=${RELEASE_VERSION} && \
    mvn --no-transfer-progress clean install -DskipTests=true


# ----------------------------------------------------------------------------------------------------------------------
# Unit Tests
# ----------------------------------------------------------------------------------------------------------------------
FROM build AS unit-tests
WORKDIR /home/ffuser/app
RUN mvn test


# ----------------------------------------------------------------------------------------------------------------------
# Packages
# ----------------------------------------------------------------------------------------------------------------------
# Packages are extracted by the pipeline shared library from image tag packages:latest
# any package that needs publishing will have to be inside this image, for the CI system
# to extract it and perform the publishing steps
FROM scratch AS packages

ARG ARTIFACT_NAME
ARG RELEASE_VERSION

COPY --from=build /home/ffuser/app/target/${ARTIFACT_NAME}.hpi ${ARTIFACT_NAME}-${RELEASE_VERSION}.hpi
COPY --from=build /home/ffuser/app/pom.xml .
CMD [ "" ]
# ----------------------------------------------------------------------------------------------------------------------
# EOF
# ----------------------------------------------------------------------------------------------------------------------
