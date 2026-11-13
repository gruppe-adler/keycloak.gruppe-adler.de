# syntax=docker/dockerfile:1.7

# The Keycloak version is written out in both FROM lines (not via ARG) so
# Dependabot can see and bump it. Images are pinned as tag@digest; Dependabot
# updates both. Keep the two Keycloak lines (tag and digest) in sync.

##########################################################################
# Stage 1: fetch the two extension jars from GitHub Packages (Maven)
##########################################################################
FROM maven:3.9-eclipse-temurin-26@sha256:b2c1ad85954592f9928e84327c65201f308ad9b5d8ed7d5b823717c97bf23fbb AS extensions

WORKDIR /build
COPY extensions/pom.xml extensions/settings.xml ./

# GH_PACKAGES_ACTOR / GH_PACKAGES_TOKEN are passed as BuildKit secrets so
# they never end up in an image layer or in `docker history`.
RUN --mount=type=secret,id=gh_actor \
    --mount=type=secret,id=gh_token \
    export GH_PACKAGES_ACTOR="$(cat /run/secrets/gh_actor)" && \
    export GH_PACKAGES_TOKEN="$(cat /run/secrets/gh_token)" && \
    mvn -B -s settings.xml dependency:copy-dependencies

##########################################################################
# Stage 2: build the Keycloak server with the extensions installed
##########################################################################
FROM quay.io/keycloak/keycloak:26.8.2-2@sha256:c68e286cacd87b942ac1939a0a1481461109d6acd3a57dc496969a319a76bbf0 AS builder

COPY --from=extensions /build/target/providers/ /opt/keycloak/providers/

# Adjust to taste / move to runtime env if you prefer a non-baked config.
ENV KC_DB=postgres
RUN /opt/keycloak/bin/kc.sh build

##########################################################################
# Stage 3: final runtime image
##########################################################################
FROM quay.io/keycloak/keycloak:26.8.2-2@sha256:c68e286cacd87b942ac1939a0a1481461109d6acd3a57dc496969a319a76bbf0

COPY --from=builder /opt/keycloak/ /opt/keycloak/

ENTRYPOINT ["/opt/keycloak/bin/kc.sh"]
CMD ["start", "--optimized", "--server-async-bootstrap=false"]
