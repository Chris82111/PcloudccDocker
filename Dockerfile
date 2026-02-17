# syntax=docker/dockerfile:1

#------------------------------------------------------------------------------
### Manual compiling and testing
#------------------------------------------------------------------------------

#------------------------------------------------------------------------------
### (1) Sources
#------------------------------------------------------------------------------

FROM ubuntu:25.04 AS base_stage

# Official linked website: https://github.com/pcloudcom/console-client
# Update: https://github.com/lneely/pcloudcc-lneely
ENV repoUrl="https://github.com/lneely/pcloudcc-lneely.git"

ENV repoName="pcloudcc-lneely"

# --build-arg TZ=UTC
ARG TZ=UTC

# Set the environment variable for non-interactive installation
ENV DEBIAN_FRONTEND=noninteractive

# Set the timezone by given argument
ENV TZ=${TZ} 


#------------------------------------------------------------------------------
### (2)
#------------------------------------------------------------------------------

FROM base_stage AS build_stage

ENV EMAIL=

RUN apt-get update && apt-get install -y \
  git \
  build-essential \
  zlib1g-dev \
  libboost-system-dev \
  libboost-program-options-dev \
  libpthread-stubs0-dev \
  libudev-dev \
  libfuse-dev \
  libsqlite3-dev \
  libreadline-dev \
  && rm -rf /var/lib/apt/lists/*


# Ubuntu 26.04 uses: 3.6.5-0.1ubuntu2
RUN apt-get update && apt-get install -y \
  libmbedtls-dev \
  && rm -rf /var/lib/apt/lists/*

# Check MbedTLS version
RUN version=$(dpkg -s libmbedtls-dev | grep Version | awk '{print $2}') && \
  major=$(echo $version | cut -d. -f1) && \
  minor=$(echo $version | cut -d. -f2) && \
  if [ "$major" -lt 3 ] || { [ "$major" -eq 3 ] && [ "$minor" -lt 6 ]; }; then \
    echo "ERROR: MbedTLS version 3.6 or higher required, found $version"; \
    exit 1; \
  fi

RUN apt-get update && apt-get install -y \
  fuse \
  && rm -rf /var/lib/apt/lists/*

WORKDIR /build
RUN git clone ${repoUrl}
WORKDIR /build/${repoName}

# The TAG build parameter can be used to select a specific tag from the repository.
ARG TAG=
ENV TAG="${TAG}"

RUN if [ -n "${TAG}" ] ; then \
    git fetch --tags ; \
    git checkout "${TAG}" ; \
  else \
    echo "git selects the latest version of the default branch."; \
  fi

# Build it with the system libraries
#
RUN make
RUN make install


# # Build it your own (works with 24.02):
#
# # https://github.com/lneely/pcloudcc-lneely/blob/main/doc/MBEDTLS-3.x.md
# RUN apt-get update && apt-get install -y \
#   python3 python3-pip python3-venv cmake \
#   && rm -rf /var/lib/apt/lists/*
#   
# WORKDIR /build
# RUN git clone https://github.com/Mbed-TLS/mbedtls.git
# WORKDIR /build/mbedtls
# RUN git checkout tags/v3.6.2
# RUN git submodule update --init
# RUN python3 -m venv ./venv \
#   && . ./venv/bin/activate \
#   && python3 -m pip install -r scripts/basic.requirements.txt \
#   && cmake -S . -B build \
#     -DMBEDTLS_VERSION_C=ON \
#     -DENABLE_TESTING=OFF \
#     -DENABLE_PROGRAMS=OFF
# RUN cmake --build build
# RUN cmake --install build
# RUN ln -s /usr/local/include/mbedtls/ /usr/local/include/mbedtls3
# 
# WORKDIR /build/test
# RUN set -eux; \
# cat > /tmp/check_mbedtls.c <<'EOF'
# #include <stdio.h>
# #include <mbedtls/version.h>
# 
# int main(void) {
#     char string[32];
#     mbedtls_version_get_string(string);
#     printf("%s\n", string);
#     return 0;
# }
# EOF
# 
# RUN gcc -I/usr/local/include -L/usr/local/lib /tmp/check_mbedtls.c -o /tmp/check_mbedtls -lmbedtls -lmbedcrypto -lmbedx509&& \
#   version=$(/tmp/check_mbedtls) && \
#   major=$(echo "$version" | cut -d. -f1) && \
#   minor=$(echo "$version" | cut -d. -f2) && \
#   if [ "$major" -lt 3 ] || { [ "$major" -eq 3 ] && [ "$minor" -lt 6 ]; }; then \
#     echo "ERROR: mbedTLS version 3.6 or higher required, found $version"; \
#     exit 1; \
#   fi
# 
# WORKDIR /build
# RUN git clone ${repoUrl}
# WORKDIR /build/${repoName}
# 
# # run from the source root directory (e.g., pcloudcc-lneely)
# RUN sed -i 's/-lmbedtls/-l:libmbedtls.a/;s/-lmbedcrypto/-l:libmbedcrypto.a/;s/-lmbedx509/-l:libmbedx509.a/' Makefile
# RUN sed -i '5s/$/ -I\/usr\/local\/include/' Makefile
# RUN sed -i '10s/$/ -L\/usr\/local\/lib\//' Makefile
# RUN find . -type f -name "*.[ch]" -exec sed -i 's/#include <mbedtls/#include <mbedtls3/' {} +
# RUN make clean all
# 
# RUN make
# RUN make install

# Change rights
ARG SETUID_ROOT="false"
ENV SETUID_ROOT="${SETUID_ROOT}"

RUN if [ "true" = "${SETUID_ROOT}" ] ; then \
      chown "root":"root" "/usr/local/bin/pcloudcc" && \
      chmod u+s "/usr/local/bin/pcloudcc" ; \
  else \
      echo "Skipping setuid setup"; \
  fi

# Ensure graceful shutdown
STOPSIGNAL SIGTERM

HEALTHCHECK --interval=30s --timeout=1s --retries=1 --start-period=15s \
  CMD pgrep -x pcloudcc >/dev/null 2>&1 || exit 1

# Create a standard user
# RUN groupadd --gid 1001 ubuntu && useradd --uid 1000 --gid 1001 -m user

ARG UID=1000
ARG GID=1000
ARG UNAME="ubuntu"
ARG GNAME="user"

ENV USER="${UNAME}"
ENV UID="${UID}"
ENV GID="${GID}"

RUN set -eux; \
  \
  # ---------- GROUP ----------
  if getent group "${GNAME}" >/dev/null; then \
      groupmod -g "${GID}" "${GNAME}"; \
  elif getent group "${GID}" >/dev/null; then \
      existing="$(getent group ${GID} | cut -d: -f1)"; \
      groupmod -n "${GNAME}" "$existing"; \
  else \
      groupadd -g "${GID}" "${GNAME}"; \
  fi; \
  \
  # ---------- USER ----------
  if id -u "${UNAME}" >/dev/null 2>&1; then \
      usermod -u "${UID}" -g "${GID}" "${UNAME}"; \
  elif getent passwd "${UID}" >/dev/null; then \
      existing="$(getent passwd ${UID} | cut -d: -f1)"; \
      usermod -l "${UNAME}" -d "/home/${UNAME}" -m "$existing"; \
      usermod -g "${GID}" "${UNAME}"; \
  else \
      useradd -m -u "${UID}" -g "${GID}" "${UNAME}"; \
  fi

WORKDIR /app
COPY entrypoint.sh entrypoint.sh
RUN chmod +x entrypoint.sh 

USER "${UNAME}"
ENTRYPOINT ["./entrypoint.sh"]

