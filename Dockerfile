ARG SUDO=sudo
ARG CRON=cron

###################################################################################
FROM alpine:3.24.2@sha256:294b683cb724975bec92580e1e685676bd4b50bda910ddb8c51d4cabeaec77e6 AS base
USER root
###-----------------------------------------------------------------------------###

## SET UP TIMEKEEPING AND TZ ENV VAR SUPPORT
RUN apk add tzdata

###################################################################################
FROM base AS user
USER root
###-----------------------------------------------------------------------------###

### SET THE DEFAULT USER AND GROUP
ARG USERNAME=somebody
ARG GROUPNAME=${USERNAME}
ARG PUID=1000
ARG PGID=${PUID}
ARG SINICRON_VERSION=undefined

### CREATE THE UNPRIVILEGED USER
RUN addgroup -g ${PGID} ${GROUPNAME}
RUN adduser -S -D -s /bin/sh -h /home/${USERNAME} -g ${GROUPNAME} -G ${GROUPNAME} -u ${PUID} ${USERNAME}

### VARS TO BE INHERITED IN OTHER IMAGES
ENV USERNAME=${USERNAME}
ENV GROUPNAME=${GROUPNAME}
ENV PUID=${PUID}
ENV PGID=${PGID}
ENV SINICRON_VERSION=${SINICRON_VERSION}

###################################################################################
FROM user AS nosudo
FROM nosudo AS sudo
USER root
###-----------------------------------------------------------------------------###

### ENABLE PASSWORDLESS SUDO CAPABILITY FOR THE USER
RUN apk add sudo
RUN echo "${USERNAME} ALL=(ALL) NOPASSWD: ALL" >> /etc/sudoers

###################################################################################
ARG SUDO
FROM $SUDO AS init
USER root
###-----------------------------------------------------------------------------###

### INSTALL INIT
RUN apk add dinit

### SET UP BASIC INIT
RUN mkdir -p /etc/dinit.d/boot.d/
COPY <<"EOT" /etc/dinit.d/boot
type = internal
waits-for.d: boot.d
EOT
RUN chown ${PUID}:${PGID} /etc/dinit.d/ -R

###################################################################################
FROM init AS nocron
FROM nocron AS cron
USER root
###-----------------------------------------------------------------------------###

### INSTALL CRON
RUN apk add supercronic

### SET UP BASIC CRONTAB
RUN mkdir -p /etc/supercronic/
COPY <<"EOT" /etc/supercronic/crontab
# min   hour    day     month   weekday command
EOT
RUN chown ${PUID}:${PGID} /etc/supercronic/ -R

### SET UP INIT TO RUN CRON
COPY <<"EOT" /etc/dinit.d/cron
type = process
command = /usr/bin/supercronic -no-reap -passthrough-logs -overlapping -json -inotify /etc/supercronic/crontab
options = shares-console
restart = true
restart-delay = 59
EOT
RUN ln -s /etc/dinit.d/cron /etc/dinit.d/boot.d/cron
RUN chown ${PUID}:${PGID} /etc/dinit.d/ -R

###################################################################################
ARG CRON
FROM $CRON AS entrypoint
USER ${USERNAME}
###-----------------------------------------------------------------------------###

### RUN INIT
WORKDIR /home/${USERNAME}/
ENTRYPOINT [ "/usr/bin/dinit", "--container", "--console-level", "debug", "--socket-path", "/tmp/dinitctl", "--services-dir", "/etc/dinit.d/"]
