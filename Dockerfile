# syntax=docker/dockerfile:1

#------------------------------------------------------------------------------
### Manual compiling and testing
#------------------------------------------------------------------------------

# Please refer to the commands in the `README.md` file.


#------------------------------------------------------------------------------
### (1) Sources
#------------------------------------------------------------------------------

FROM ubuntu:25.04 AS base_stage

# Set the environment variable for non-interactive installation
ENV DEBIAN_FRONTEND=noninteractive

# Optional parameter for changing the time zone
ARG TZ=UTC
ENV TZ=${TZ} 


#------------------------------------------------------------------------------
### (2)
#------------------------------------------------------------------------------

FROM base_stage AS build_pcloudcc_stage

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
  libmbedtls-dev \
  && rm -rf /var/lib/apt/lists/*


# Check MbedTLS version
RUN version=$(dpkg -s libmbedtls-dev | grep Version | awk '{print $2}') && \
  major=$(echo $version | cut -d. -f1) && \
  minor=$(echo $version | cut -d. -f2) && \
  if [ "$major" -lt 3 ] || { [ "$major" -eq 3 ] && [ "$minor" -lt 6 ] ; } ; then \
    echo "ERROR: MbedTLS version 3.6 or higher required, found $version"; \
    exit 1; \
  fi

# Official website: https://github.com/pcloudcom/console-client
# Update: https://github.com/lneely/pcloudcc-lneely
ENV repoUrl="https://github.com/lneely/pcloudcc-lneely.git"
ENV repoName="pcloudcc-lneely"

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
    echo "git selects the latest version of the default branch." ; \
  fi

# Build it with the system libraries
#
RUN make
RUN make install


# If true, changes the owner and sets the SETUID flag.
ARG SETUID_ROOT="false"
ENV SETUID_ROOT="${SETUID_ROOT}"

RUN if [ "true" = "${SETUID_ROOT}" ] ; then \
    chown "root":"root" "/usr/local/bin/pcloudcc" && \
    chmod u+s "/usr/local/bin/pcloudcc" ; \
  else \
    echo "Skipping setuid setup" ; \
  fi


#------------------------------------------------------------------------------
### (3)
#------------------------------------------------------------------------------

FROM base_stage AS runtime_stage

RUN apt-get update && apt-get install -y \
  libcurl4 \
  libssl3 \
  ca-certificates \
  libboost-program-options1.83.0 \
  libfuse2 \
  libreadline8 \
  libsqlite3-0 \
  libmbedtls21 \
  libmbedx509-7 \
  libmbedcrypto16 \
  fuse \
  && rm -rf /var/lib/apt/lists/*


COPY --from=build_pcloudcc_stage /usr/local/bin/pcloudcc /usr/local/bin/pcloudcc

WORKDIR /app
COPY entrypoint.sh entrypoint.sh
RUN chmod +x entrypoint.sh 


# Optional Pramerter, it is recommended to overwrite it with the respective number of the future user.
ARG UID=1000
ENV UID="${UID}"

# Optional Pramerter, it is recommended to overwrite it with the respective number of the future user.
ARG GID=1000
ENV GID="${GID}"

# The username in the Docker container can be different; only the user and group numbers are important. 
ARG USE_USER="ubuntu"
ENV USE_USER="${USE_USER}"
ARG USE_GROUP="user"
ENV USE_GROUP="${USE_GROUP}"

ENV USER="${USE_USER}"

# Validate combination
RUN \
  if { [ "$UID" -eq 0 ] && [ "$USE_USER" != "root" ] ; } || \
     { [ "$USE_USER" = "root" ] && [ "$UID" -ne 0 ] ; } ; then \
    echo "Invalid UID/USE_USER combination"; \
    exit 1; \
  fi

# Creates a standard user or changes it based on the settings.
RUN set -eux; \
  \
  # ---------- GROUP ----------
  if getent group "${USE_GROUP}" >/dev/null ; then \
    groupmod -g "${GID}" "${USE_GROUP}" ; \
  elif getent group "${GID}" >/dev/null ; then \
    existing="$(getent group ${GID} | cut -d: -f1)" ; \
    groupmod -n "${USE_GROUP}" "$existing" ; \
  else \
    groupadd -g "${GID}" "${USE_GROUP}" ; \
  fi ; \
  \
  # ---------- USER ----------
  if id -u "${USE_USER}" >/dev/null 2>&1 ; then \
    usermod -u "${UID}" -g "${GID}" "${USE_USER}" ; \
  elif getent passwd "${UID}" >/dev/null ; then \
    existing="$(getent passwd ${UID} | cut -d: -f1)" ; \
    usermod -l "${USE_USER}" -d "/home/${USE_USER}" -m "$existing" ; \
    usermod -g "${GID}" "${USE_USER}" ; \
  else \
    useradd -m -u "${UID}" -g "${GID}" "${USE_USER}" ; \
  fi


#------------------------------------------------------------------------------
### (4)
#------------------------------------------------------------------------------

FROM runtime_stage AS final_stage

# Must be set during create.
ENV EMAIL=

# Ensure graceful shutdown
STOPSIGNAL SIGTERM

HEALTHCHECK --interval=30s --timeout=1s --retries=1 --start-period=15s \
  CMD pgrep -x pcloudcc >/dev/null 2>&1 || exit 1

WORKDIR /app
USER "${USE_USER}"
ENTRYPOINT ["./entrypoint.sh"]

