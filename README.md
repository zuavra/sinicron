# sinicron

sinicron is a Docker image designed to be used as a base for other projects that need service management ("init") and optionally a process scheduler ("cron") and sudo capability.

sinicron was designed with the following goals:

* Small – based on an Alpine image.
* Includes tzdata.
* Runs as a non-privileged user (configurable at build-time).
* Entrypoint is a service manager that does signal handling and orphan reaping.
* Optionally include a process scheduler with a classic crontab format.
* Optionally include passwordless sudo capability for the designated user.

**Content:**

<!-- TOC depthfrom:2 -->

- [1. Quick start](#1-quick-start)
- [2. Using the image](#2-using-the-image)
  - [2.1. Common characteristics](#21-common-characteristics)
  - [2.2. Using the service manager](#22-using-the-service-manager)
  - [2.3. Using the process scheduler](#23-using-the-process-scheduler)
  - [2.4. Using sudo](#24-using-sudo)
  - [2.5. Security considerations](#25-security-considerations)
- [3. Building your own image](#3-building-your-own-image)
  - [3.1. Build arguments](#31-build-arguments)
  - [3.2. An example for extending the base image](#32-an-example-for-extending-the-base-image)

<!-- /TOC -->

## 1. Quick start

There are always 4 flavors of the image, combinations of with/without cron and sudo.

These are the current latest tags:

* [latest-sudo-nocron](https://github.com/users/zuavra/packages/container/sinicron/1510700299?tag=latest-sudo-nocron)
* [latest-sudo-cron](https://github.com/users/zuavra/packages/container/sinicron/1510699938?tag=latest-sudo-cron)
* [latest-nosudo-nocron](https://github.com/users/zuavra/packages/container/sinicron/1510699240?tag=latest-nosudo-nocron)
* [latest-nosudo-cron](https://github.com/users/zuavra/packages/container/sinicron/1510677637?tag=latest-nosudo-cron)

You can also use an exact version (e.g. `1.2.3-nosudo-nocron`), or a minor version shortcut to the latest version of that minor (e.g. `1.2-nosudo-nocron`).

## 2. Using the image

### 2.1. Common characteristics

All image flavors run as designated user `1000:1000` by default (name/group `somebody`/`somebody` inside the image). This is what the service manager, the process scheduler and all processes started by them run as. This is also the user that has access to passwordless sudo in the relevant images.

All image flavors provide the service manager as PID 1.

### 2.2. Using the service manager

The service manager being used by `sinicron` is [dinit](https://davmac.org/projects/dinit/).

> NOT to be confused with [tozd/dinit](https://gitlab.com/tozd/docker/dinit), which is a different project, which I have considered briefly before realizing that the manager dies if any of the processes managed by it die... which is an interesting option but should have been an option, not mandatory.

* `dinit` is PID 1 and handles signals and sub-process reaping.
* `dinit` also manages the process scheduler if installed.
* See the `Dockerfile` for the exact parameters to `dinit`.

By default `dinit` is set to use `/etc/dinit.d` as the service definition dir. This dir holds the definitions for the required `boot` internal target and for the scheduler (if present).

In order to add your own services to the manager you have to write a service definition file. There are two approaches you can take:

1. Add your definitions to `/etc/dinit.d` and symlink each definition file from `/etc/dinit.d/boot.d` to make it start by default.
   * Please keep in mind that you must keep the `boot` and `cron` definitions and symlinks, so you cannot remap the entire `/etc/dinit.d` dir.
2. Add your definitions elsewhere and use entrypoint options to indicate the location to `dinit` and to tell it which services to start. You can add multiple definition dirs. Example:
   ```
   command: ["--services-dir", "/home/somebody/.config/dinit.d", "--service", "foo", "bar", "bla"]
   ```

See below for an example of a service definition file. See [DINIT-SERVICE(5)](https://davmac.org/projects/dinit/man-pages-html/dinit-service.5.html) for the full definition file specification. 

```
type = process
command = /usr/bin/tail -f /dev/null
options = shares-console
restart = true
```

> Please note that by default `dinit` will give up on services that have restarted 3 times within 10 seconds. See the `restart-` definition directives for tweaking this behavior. 

### 2.3. Using the process scheduler

The process scheduler used by `sinicron` is [supercronic](https://github.com/aptible/supercronic), a simple, container-friendly cron implementation.

Important things to note about `supercronic`:

* It runs as a `dinit` service.
* See `Dockerfile` for the exact parameters it runs with.
   * If you'd like to change or append parameters you can either rebuild the image or overwrite `/etc/dinit.d/cron`. 
* Unlike most other cron implementations, it does NOT clear env vars for the scheduled processes. This means your processes can take advantage of the container environment normally.
* It runs as the designated container user and runs all scheduled processes as that user.
* It CAN NOT run processes as any other user; however, if you are running a `-sudo` image you can use `/usr/bin/sudo` to execute commands as `root`.

To add your own schedule definitions you use `/etc/supercronic/crontab` which has the familiar format. **The crontab file MUST exist otherwise `supercronic` won't start.** By default it contains nothing important so you can safely remap the file or the entire dir.

### 2.4. Using sudo

If you're running from a `-sudo` image, the designated user can run `/usr/bin/sudo` without a password to elevate to root.

Unfortunately sometimes sudo is necessary as a last resort. But consider whether other methods can achieve what you need to do:

* Adding specific capabilities with `cap_add`.
* Becoming a member of specific groups with `group_add`. This can help you for example access some devices such as `/dev/dri` for graphical acceleration.

### 2.5. Security considerations

If you are using any of the following container restrictions (you should!) please note the caveats:

* **Running as a non-privileged user:**
  * You don't have to set `user:` if it's the same one built inside the image, it would be redundant.
  * You _can_ however explicitly set `user: "0:0"` or to another UID:GID than the one inside the image.
  * Setting `user:` will cause the service manager and the process scheduler and all processes started by them to run as that UID:GID.
* **Dropping all caps:**
  * Please note that if you intend to make use of `sudo` you need to:
    * Re-add capabilities `SETGID` and `SETUID`.
    * Either don't set `no-new-privileges` in `security_opts:` or set it to `no-new-privileges:false`.
* **Running with root filesystem read-only:**
  * Please note that the service manager needs to create a socket file. By default that's set to be `/tmp/dinitctl`. So if you are using `read-only: true` you have to do one of the following:
    * Map `/tmp` to a writable volume (either bind mount or named volume).
    * Map `/tmp` to a RAM disk via `tmpfs:`, for example:
        ```
        tmpfs:
          - /tmp:mode=770,uid=1000,gid=1000,size=10M
        ```
    * If you have another writable location somewhere that you'd like to use, you can append an option to the entrypoint to tell the manager where to put the socket. Remember that it needs to be specified as the full path _and_ the file name:
        ```
        command: ["--socket-path", "/other/path/socketfilename"]
        ```

## 3. Building your own image

### 3.1. Build arguments

* `USERNAME`: determines the name of the designated user inside the image and their `/home` dir. Defaults to `somebody`.
* `GROUPNAME`: determines the group name of the designated user. This is the only group that the user belongs to. Defaults to the value of `$USERNAME`.
* `PUID`: determines the UID of the designated user. Don't set it to one of the pre-existing users on Alpine (see `/etc/passwd`). Defaults to `1000`.
* `PGID`: determines the GID of the desingated user. Same as above, see `/etc/group` (and keep in mind that `999` is group `ping` by default on Alpine). Defaults to the value of `$PUID`.
* `SINICRON_VERSION` is mainly used so it will be an env var inside the image for easy verification.
* The above build arguments are all propagated as env vars inside the container. **You can also make use of them inside your own Dockerfile.**
* `SUDO`: determines whether the resulting image has sudo capability enabled for the designated user. Valid values are `sudo` or `nosudo`. Defaults to `sudo`.
* `CRON`: determines whether the resulting image will have the process scheduler installed and running. Valid values are `cron` and `nocron`. Defaults to `cron`.

### 3.2. An example for extending the base image

```
FROM ghcr.io/zuavra/sinicron:1-sudo-cron

USER root
RUN apk add hdparm

USER ${USERNAME}
```

The most important thing to remember is that the base `sinicron` images are set to the non-privileged user, so you have to switch explicitly to `root` in order to do things like install packages.

If you'd like your image to maintain running as the non-privileged user you should switch back to it at the end.

Remember that you can use the variables `$USERNAME`, `$GROUPNAME`, `$PUID`, `$PGID` and `$SINICRON_VERSION` if you need to.

And here's how to generate specific image combinations:

```
$ docker build --build-arg SINICRON_VERSION=custom \
--build-arg SUDO=nosudo --build-arg CRON=nocron \
--tag=local/sinicron:${SINICRON_VERSION}-nosudo-nocron
```