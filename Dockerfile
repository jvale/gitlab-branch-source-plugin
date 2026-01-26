# syntax=artifacts-we1.farfetch.net/dockerio-docker-all/docker/dockerfile:1

ARG FROM_REPO_JDK
ARG FROM_REPO_JRE
ARG FROM_REPO_MAVEN
ARG FROM_TAG_JDK
ARG FROM_TAG_JRE
ARG FROM_TAG_MAVEN
ARG REGISTRY_URL
ARG RELEASE_VERSION

# ----------------------------------------------------------------------------------------------------------------------
# Base image
# ----------------------------------------------------------------------------------------------------------------------
FROM ${FROM_REPO_MAVEN}:${FROM_TAG_MAVEN} as base
# ARG FFUSER_UID
# USER root
# # Always set your shell options to avoid silient errors, but avoid using '-x'
# # so that secrets are not accidentally leaked to pipeline logs
# SHELL ["/bin/bash","-eu","-o","pipefail","-c"]
# RUN <<EOF
#   printf "# --------------------------------------------------------------------------------\n"
#   printf "# When OS package needs to be installed, always update the package manager first\n"
#   printf "# for fetching the latest OS updates and updating the \n"
#   printf "# repository sources so you install your required packages...\n"
#   printf "# --------------------------------------------------------------------------------\n"
#   printf ">>> Update OS packages...\n"
#   export DEBIAN_FRONTEND=noninteractive
#   apt-get update -y
#   printf ">>> Update OS packages...DONE\n"
#   printf "# --------------------------------------------------------------------------------\n"
#   printf "# Users are free to install/remove OS packages, but bear in mind\n"
#   printf "#  the more you install, bigger your image and the exposure to CVEs...\n"
#   printf "# --------------------------------------------------------------------------------\n"
#   printf ">>> Install/Remove OS packages...\n"
#   apt-get update -y
#   apt-get upgrade -y
#   apt-get purge -y
#   dpkg -r --force-all apt apt-get
#   dpkg -r --force-all debconf dpkg
#   printf ">>> Install/Remove OS packages...DONE\n"
# EOF

# After performing OS changes, always switch to a non-root user
USER ffuser
ARG FFUSER_UID
ARG RELEASE_VERSION
ENV RELEASE_VERSION=${RELEASE_VERSION}
WORKDIR /home/ffuser/
COPY --chown=ffuser:ffuser . /home/ffuser
SHELL ["/bin/bash","-eu","-o","pipefail","-c"]
RUN --mount=type=secret,id=art_creds_username,dst=/home/ffuser/.art_creds_username,uid=${FFUSER_UID} \
    --mount=type=secret,id=art_creds_token,dst=/home/ffuser/.art_creds_token,uid=${FFUSER_UID} \
    --mount=type=cache,target=/home/ffuser/.m2,rw,uid=${FFUSER_UID} \
    --mount=type=cache,target=/home/ffuser/.cache,rw,uid=${FFUSER_UID} \
    --mount=type=cache,target=/var/cache/apt,rw \
<<EOF
  printf "# --------------------------------------------------------------------------------\n"
  printf "# Using secret mounts, as per below helps you avoid accidentally leaking credentials,\n"
  printf "# check the link below for more information:\n"
  printf "#   - https://farfetch.atlassian.net/wiki/spaces/DeliveryPlatform/pages/13631815990/Handling+Build+Secrets\n"
  printf "#\n"
  printf "# Another tip for improving build time is using cache mounts as further described in the following doc: \n"
  printf "#   - https://farfetch.atlassian.net/wiki/spaces/DeliveryPlatform/pages/13631848512/Reduce+build+time+with+cache+mounts\n"
  printf "# --------------------------------------------------------------------------------\n"
  export REGISTRY_USERNAME=$(cat /home/ffuser/.art_creds_username)
  export REGISTRY_API_KEY=$(cat /home/ffuser/.art_creds_token)
  createSettingsXml ${REGISTRY_USERNAME} ${REGISTRY_API_KEY}
  mkdir -p /home/ffuser/.metadata
  mvn help:evaluate \
    -Dexpression=project.version \
    -q -DforceStdout \
    -f /home/ffuser/pom.xml > /home/ffuser/.metadata/project.version.info
  printf "# --------------------------------------------------------------------------------\n"
  printf "# Using unique name for your artifacts is usually the preferred approach,\n"
  printf "# as per the example below, we override the version defined at the pom.xml \n"
  printf "# with the value from the RELEASE_VERSION environment variable...\n"
  printf "# --------------------------------------------------------------------------------\n"
  mvn versions:set -DnewVersion=${RELEASE_VERSION}-SNAPSHOT
  mvn clean install -DskipTests=true
EOF


# ----------------------------------------------------------------------------------------------------------------------
# Unit Tests
# ----------------------------------------------------------------------------------------------------------------------
FROM base as unit-tests
ARG FFUSER_UID
ARG RELEASE_VERSION
ENV RELEASE_VERSION=${RELEASE_VERSION}
USER ffuser
WORKDIR /home/ffuser/
SHELL ["/bin/bash","-eu","-o","pipefail","-c"]
RUN --mount=type=secret,id=art_creds_username,dst=/home/ffuser/.art_creds_username,uid=${FFUSER_UID} \
    --mount=type=secret,id=art_creds_token,dst=/home/ffuser/.art_creds_token,uid=${FFUSER_UID} \
    --mount=type=cache,target=/home/ffuser/.m2,rw,uid=${FFUSER_UID} \
    --mount=type=cache,target=/home/ffuser/.cache,rw,uid=${FFUSER_UID} \
    --mount=type=cache,target=/var/cache/apt,rw,uid=${FFUSER_UID} \
<<EOF
  printf "# --------------------------------------------------------------------------------\n"
  printf "# Here we intentionally choose to execute tests by building the image, instead of\n"
  printf "# using ENTRYPOINT or CMD instructions, so we can leverage the cache mounts from\n"
  printf "# the previous stage, and improve even more our build time!\n"
  printf "# --------------------------------------------------------------------------------\n"
  mvn test
EOF


# ----------------------------------------------------------------------------------------------------------------------
# Packages
# ----------------------------------------------------------------------------------------------------------------------
# Packages are extracted by the pipeline shared library from image tag packages:latest
# amy package that needs publishing will have to be inside this image, for the CI system
# to extract it and perform the publishing steps
FROM scratch as packages
COPY --from=base /home/ffuser/target/*.jar .
COPY --from=base /home/ffuser/pom.xml .
COPY --from=base /home/ffuser/.metadata /home/ffuser/.metadata
CMD [ "" ]
# ----------------------------------------------------------------------------------------------------------------------
# EOF
# ----------------------------------------------------------------------------------------------------------------------
