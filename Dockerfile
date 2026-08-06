# syntax=docker/dockerfile:1.7

ARG KEYCLOAK_VERSION=26.6.3

##########################################################################
# Stage 1: fetch the two extension jars from GitHub Packages (Maven)
##########################################################################
FROM maven:3.9-eclipse-temurin-21 AS extensions

WORKDIR /build
COPY extensions/pom.xml extensions/settings.xml ./

# GH_PACKAGES_ACTOR / GH_PACKAGES_TOKEN are passed as BuildKit secrets so
# they never end up in an image layer or in `docker history`.
RUN --mount=type=secret,id=gh_actor \
    --mount=type=secret,id=gh_token \
    export GH_PACKAGES_ACTOR="$(cat /run/secrets/gh_actor)" && \
    export GH_PACKAGES_TOKEN="$(cat /run/secrets/gh_token)" && \
    mvn -B -s settings.xml \
        org.apache.maven.plugins:maven-dependency-plugin:3.6.1:copy-dependencies \
        -DoutputDirectory=/build/target/providers \
        -DexcludeTransitive=true \
        -DincludeScope=runtime

##########################################################################
# Stage 2: build the Keycloak server with the extensions installed
##########################################################################
FROM quay.io/keycloak/keycloak:${KEYCLOAK_VERSION} AS builder

COPY --from=extensions /build/target/providers/ /opt/keycloak/providers/

# Adjust to taste / move to runtime env if you prefer a non-baked config.
ENV KC_DB=postgres
RUN /opt/keycloak/bin/kc.sh build

##########################################################################
# Stage 3: final runtime image
##########################################################################
FROM quay.io/keycloak/keycloak:${KEYCLOAK_VERSION}

COPY --from=builder /opt/keycloak/ /opt/keycloak/

ENTRYPOINT ["/opt/keycloak/bin/kc.sh"]
CMD ["start"]
