# sinicron

sinicron is a Docker image designed to be used as a base for projects that need service management ("init") and optionally a process scheduler ("cron") and sudo capability.

sinicron was designed with the following features:

* Small (based on official Alpine images).
* Includes tzdata and a couple of other small utils.
* Runs as a non-privileged user (overwritable at build- or run-time).
* Entrypoint is a service manager that does signal handling and orphan reaping.
* Optionally includes a process scheduler with a classic crontab format.
* Optionally includes passwordless sudo capability for the designated user.

**Content:**

<!-- TOC depthfrom:2 -->

- [1. Quick start](#1-quick-start)
- [2. Using the image](#2-using-the-image)
  - [2.1. Common characteristics](#21-common-characteristics)
  - [2.2. Using the service manager](#22-using-the-service-manager)
    - [2.2.1. About the manager](#221-about-the-manager)
    - [2.2.2. Writing service definitions](#222-writing-service-definitions)
    - [2.2.3. Enabling services](#223-enabling-services)
  - [2.3. Using the process scheduler](#23-using-the-process-scheduler)
    - [2.3.1. About the scheduler](#231-about-the-scheduler)
    - [2.3.2. Adding your own tasks to the scheduler](#232-adding-your-own-tasks-to-the-scheduler)
  - [2.4. Using sudo](#24-using-sudo)
  - [2.5. Security considerations](#25-security-considerations)
- [3. Building your own image](#3-building-your-own-image)
  - [3.1. Build arguments](#31-build-arguments)
  - [3.2. An example for extending the base image](#32-an-example-for-extending-the-base-image)
- [4. Frequently asked questions and tips](#4-frequently-asked-questions-and-tips)
  - [4.1. Misc topics](#41-misc-topics)
  - [4.2. Dinit topics](#42-dinit-topics)

<!-- /TOC -->

## 1. Quick start

There are always 4 flavors of the image, combinations of with/without cron and sudo.

These are the current latest tags:

* [latest-sudo-nocron](https://github.com/users/zuavra/packages/container/sinicron/1545318556?tag=latest-sudo-nocron)
* [latest-sudo-cron](https://github.com/users/zuavra/packages/container/sinicron/1545320347?tag=latest-sudo-cron)
* [latest-nosudo-nocron](https://github.com/users/zuavra/packages/container/sinicron/1545319279?tag=latest-nosudo-nocron)
* [latest-nosudo-cron](https://github.com/users/zuavra/packages/container/sinicron/1545313350?tag=latest-nosudo-cron)

You can also use an exact version (e.g. `1.2.3-nosudo-nocron`), or a minor version shortcut to the latest version of the minor (e.g. `1.2-nosudo-nocron`), or the major (e.g. `1-nosudo-nocron`).

## 2. Using the image

### 2.1. Common characteristics

All image flavors run as designated user `1000:1000` by default (name/group `somebody`/`somebody` inside the image). This is what the service manager, the process scheduler and all processes spawned by them will start as as.

That is also the user that has access to passwordless sudo in the relevant images.

### 2.2. Using the service manager

#### 2.2.1. About the manager

The service manager being used by `sinicron` is [dinit](https://davmac.org/projects/dinit/).

> NOT to be confused with [tozd/dinit](https://gitlab.com/tozd/docker/dinit), which is a different project, which I have considered briefly before realizing that the manager dies if any of the processes managed by it die... which is an interesting option but should have been an option, not mandatory.

* `dinit` is PID 1 and handles signals and sub-process reaping.
* Normally runs as PID 1 but it won't complain if it's made to run as another PID.
* `dinit` also manages the process scheduler if installed.
* See the `Dockerfile` for the exact parameters to `dinit`.

#### 2.2.2. Writing service definitions

By default `dinit` is set to use `/etc/dinit.d` as the service definition dir. This dir holds the definitions for the required `boot` internal target and for the scheduler (if present).

In order to add your own services to the manager you first have to write a service definition file. See below for a simple example. See [DINIT-SERVICE(5)](https://davmac.org/projects/dinit/man-pages-html/dinit-service.5.html) for the full spec. 

```
type = process
command = tail -f /dev/null
options = shares-console
restart = true
```

#### 2.2.3. Enabling services

Next thing to do is to use the definition to make the service run. There are two approaches you can take:

1. Add definition files to `/etc/dinit.d` and symlink each one from `/etc/dinit.d/boot.d` to make it start by default.
   > Careful about remapping the entire `/etc/dinit.d` dir so as not to lose the `boot` and `cron` service definitions. `boot` is not essential as long as you add another service dir and enable at least one service in it (see approach 2), but if you want to get rid of cron it's best to use an image flavor without it.
2. Add your definitions elsewhere and use entrypoint options to indicate those location dirs to `dinit` and to tell it which services to start. You can define multiple locations. Example:
   ```
   command: ["--services-dir", "/home/somebody/.config/dinit.d", "--service", "foo", "bar", "bla"]
   ```

> Please note that by default `dinit` will give up on services that have restarted 3 times within 10 seconds. See the `restart-` definition directives for tweaking this behavior. 

### 2.3. Using the process scheduler

#### 2.3.1. About the scheduler

The process scheduler used by `sinicron` is [supercronic](https://github.com/aptible/supercronic), a simple, container-friendly cron implementation.

Important things to note about `supercronic`:

* It runs as a `dinit` service.
* See `Dockerfile` for the exact parameters it runs with.
   * If you'd like to change or append parameters you can either rebuild the image or overwrite `/etc/dinit.d/cron`. 
* Unlike most other cron implementations, it does NOT clear env vars for the scheduled processes. This means your processes can take advantage of the container environment and exec paths.
* It runs as the designated container user and starts all scheduled processes as that user.
* It CAN NOT run processes as any other user; however, if you are running a `-sudo` image you can use `/usr/bin/sudo` to execute commands as `root`.
* It attempts to detect changes to the crontab file with inotify and will reload definitions when that happens.

#### 2.3.2. Adding your own tasks to the scheduler

To add your own schedule definitions you use `/etc/supercronic/crontab` which has the classic format.

By default it contains nothing important so you can safely remap the file or the entire dir.

> Please note that the crontab file MUST always exist and have valid format otherwise `supercronic` won't start (or will die when the file is changed to something invalid).

### 2.4. Using sudo

If you're running from a `-sudo` image, the designated user can run `/usr/bin/sudo` without a password to elevate to root.

Unfortunately sometimes sudo is necessary as a last resort. But consider whether other methods can achieve what you need to do:

* Adding specific capabilities with `cap_add`.
* Becoming a member of specific groups with `group_add`. This can help you for example access some devices such as `/dev/dri` for graphical acceleration.

### 2.5. Security considerations

If you are using any of the following container restrictions (and you should) please note the caveats:

* **Running as a non-privileged user:**
  * You don't have to set `user:` if it's the same one built inside the image, it would be redundant.
  * You _can_ however explicitly set `user: "0:0"` or to another UID:GID than the one inside the image.
  * Setting `user:` will cause the service manager and the process scheduler and all processes started by them to run as that UID:GID.
* **Dropping all caps:**
  * If you want to use `sudo` you need to:
    * Re-add capabilities `SETGID` and `SETUID`.
    * Either don't set `no-new-privileges` in `security_opts:` or set it to `no-new-privileges:false`.
* **Running with root filesystem read-only:**
  * The service manager needs to create a socket file. By default that's set to be `/tmp/dinitctl`. So if you are using `read-only: true` you have to do one of the following:
    * Map `/tmp` to a writable volume (either bind mount or named volume).
    * Map `/tmp` to a RAM disk via `tmpfs:`, for example:
        ```
        tmpfs:
          - /tmp:mode=770,uid=1000,gid=1000,size=10M
        ```
    * If you have another writable location somewhere that you'd like to use you can append an option to the entrypoint to tell the manager where to put the socket. Remember that it needs to be specified as the full path _and_ the file name:
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

## 4. Frequently asked questions and tips

### 4.1. Misc topics

* I've added the designated user to several groups in my custom image but I don't have them anymore in the running container, why?
  * Are you using `user:` in your compose? If it specifies a GID it will overwrite the group membership in the image.
    * If you want to overwrite an earlier `user:` directive and render it inactive, you can use `user: ""` (with the blank string). This will leave the image specifications untouched.
    * If you want to re-add groups manually in compose you can use `group_add:`.

### 4.2. Dinit topics

* I'm getting no output in the container log from any dinit services.
  * By default dinit captures and suppresses all output from all services and only outputs service status changes.
  * Add `options = shares-console` to each service definition to make their output appear in dinit output.
* I'm making a dinit service for a daemon that insists on writing logs to files, how can I see them in the container output?
  * You can make another dinit service that uses `tail` to read and output the log files.
  * Consider using `depends-ms:` if you want the daemon service and the log reader service start in a certain order.
* My service doesn't prefix output timestamps and/or doesn't tag its log lines so they get mixed with other services.
  * Pipe the command output to the `/usr/bin/ts` to prefix it with [strftime(3)](https://www.man7.org/linux/man-pages/man3/strftime.3.html) macros or free text.
    ```
    # instead of using:
    command = /my/daemon
    
    # use:
    command = sh -c "/my/daemon | ts '%F %T [mydaemon]'"
    ```
  * If you dislike running the command via `sh` you can use dinit's ability to force a service to output into a pipe which can be consumed by another service:
    ```
    # /etc/init.d/daemon
    type = process
    command = /my/daemon
    log-type = pipe

    # /etc/init.d/daemon-prefix
    type = process
    command = ts '%F %T [mydaemon]'
    consumer-of = daemon
    options = shares-console
    ```
