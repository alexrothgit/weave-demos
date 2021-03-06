---
title: Multi-host Docker deployment with Swarm and Compose using Weave 0.11
published: true
tags: docker, docker-machine, docker-swarm, docker-compose, guide, automation, command-line
---

> ***This is an outdate guide, please find latest version on our website now!***  
> http://weave.works/guides/weave-and-docker-platform/index.html


In this post I'd like to show how easily one can get up-and-running using [Weave](https://github.com/weaveworks/weave) with all the latest and greatest Docker tools - [Machine](https://github.com/docker/machine), [Swarm](https://github.com/docker/swarm) and [Compose](https://github.com/docker/compose). This was made especially simple with two recent release of Weave ([_v0.10_](https://github.com/weaveworks/weave/releases/tag/v0.10.0) & [_v0.11_](https://github.com/weaveworks/weave/releases/tag/v0.11.0)).

> Since my last [blog post](http://blog.weave.works/2015/05/06/using-docker-machine-and-swarm-with-weave-0-10/), the Weaveworks team had been busy working on [new _v0.11_ release](https://github.com/weaveworks/weave/releases/tag/v0.11.0), that includes a number of great new features, one of which is [a proxy](http://docs.weave.works/weave/latest_release/proxy.html) that allows our users to simply call `docker run` (or the remote API) without needing to use `weave run`. This release also introduces [automatic IP address management](http://docs.weave.works/weave/latest_release/ipam.html), which Bryan has [blogged about yesterday](http://blog.weave.works/2015/05/26/let-weave-allocate-ip-addresses-for-you/).

This guide builds on what was learned from two previous posts where I showed how one can use [Machine with a single VM](http://blog.weave.works/2015/04/22/using-docker-machine-with-weave-0-10/) and [Swarm with 3 VMs](http://blog.weave.works/2015/05/06/using-docker-machine-and-swarm-with-weave-0-10/). In those two posts I used Weave CLI agains remote Docker host(s), leveraging features introduced in _v0.10_. With [proxy](http://docs.weave.works/weave/latest_release/proxy.html) being introduced in _v0.11_, one can use Docker CLI or API (via Compose) directly. Additionally, automatic IP allocation will be also used behind the scenes, lifting the burden of manual IP address assignment, which had been [a long awaited feature](https://github.com/weaveworks/weave/issues/22).

### What you will do?

This guide is design to get you started with Docker toolchain and Weave right out of the box, deploy and scale your application across multiple hosts in a very simple and absolutely transparent manner.

1.  Setup a cluster of 3 VMs with Swarm and Weave configured by means of [a shell script](https://github.com/errordeveloper/weave-demos/blob/a90d959638948e796ab675e3dd0e1f98390ae3d0/quartet/scripts/setup-cluster.sh)
2. Deploy a simple 2-tier web application using Docker Compose
3. Scale the application from 1 web servers to 3

> I will post later on with details on how exactly this kind of setup works, for those who might like to reproduce it in a different environment, perhaps without using Docker Machine and VirtualBox, so you would see how it can work in an existing infrastructure.

To follow this guide you will need to obtain the binaries for

- [***`docker`***](https://docs.docker.com/installation/#installation) _(at least the client)_
- [***`docker-machine`***](http://docs.docker.com/machine/#installation)
- [***`docker-compose`***](http://docs.docker.com/compose/install/)
- [***`docker-swarm`***](http://docs.docker.com/swarm/#install-swarm) _(optional, see below)_
- [**VirtualBox**](https://www.virtualbox.org/wiki/Downloads)

If you are using OS X, then you can install these tools with Homebrew, via

    brew install docker docker-machine docker-swarm docker-compose

You will need to download and install VirtualBox manually as well, if you haven't done it yet. Please be sure to install latest version of Machine (_v0.2.0_), as there are some bugs in the previous release. You also want to use latest `boot2docker` VM image; you will get it if you haven't used Docker Machine previously on your computer, otherwise you should delete the cached ISO image located in ***`~/.docker/machine/cache/boot2docker.iso`*** before you proceed.

> If you don't find a `docker-swarm` binary for your OS, and have Docker daemon available locally, you can set `DOCKER_SWARM_CREATE` like shown below before you proceed.
> ```
> export DOCKER_SWARM_CREATE="docker run --rm swarm create | tail -1"`
> ```
> Alternatively, it may be easier to just use `curl`:
> ```
> export DOCKER_SWARM_CREATE="curl -XPOST https://discovery-stage.hub.docker.com/v1/clusters"
>```

## Let's go!

First, we need a few scripts. To get them, run

    git clone https://github.com/errordeveloper/weave-demos
    cd weave-demos/quartet

Now, we'll provision a cluster of 3 VMs. The following script will make sure all 3 VMs join the Swarm, and sets up the Weave network and WeaveDNS.

> If you've followed one of my previous guides, you'll need to clear the VMs you've previously created. Check the output of `docker-machine ls`, and delete them with `docker-machine rm -f <vm-name>`.

    ./scripts/setup-cluster.sh


Once the cluster is up, you want to do the following

#### 1. go into app's directory
`cd app/`
#### 2. build images on each host
`./build.sh` (This makes it quicker to scale)
#### 3. setup the environment
`eval $(docker-machine env --swarm dev-1)`
#### 4. deploy
`docker-compose up -d`
#### 5. test, scale, test

We have just deployed a standard Compose demo, which consists of a Python Flask app that uses Redis as its database. Our `docker-compose.yml` file differs slightly from the original, it simply sets `hostname: redis.weave.local` and `hostname: hello.weave.local` instead of using Docker links ([**see diff**](https://github.com/errordeveloper/weave-demos/commit/4874be9943b41d1ad5352cf580ed95c608577ecf?diff=split)). These hostnames are picked up by WeaveDNS and can be resolved from any container on the Weave network. WeaveDNS records also survive container restarts, unlike Docker's built-in links.

```
> docker-compose ps
   Name                  Command               State               Ports              
-------------------------------------------------------------------------------------
app_redis_1   /home/weavewait/weavewait  ...   Up      6379/tcp                       
app_web_1     /home/weavewait/weavewait  ...   Up      192.168.99.102:32773->5000/tcp 
```

From the above, you can see that the app can be accessed on `192.168.99.102:5000`, let's test this now.

```
> curl 192.168.99.102:32773
Hello World! I have been seen 1 times.
> curl 192.168.99.102:32773
Hello World! I have been seen 2 times.
> curl 192.168.99.102:32773
Hello World! I have been seen 3 times.
```

Amazing, it worked!

Of course, one server is not enough, if we have 3 VMs to our disposal. Let's scale this up!

```
> docker-compose scale web=3
Creating app_web_2...
Creating app_web_3...
Starting app_web_2...
Starting app_web_3...

> docker-compose ps
   Name                  Command               State               Ports              
-------------------------------------------------------------------------------------
app_redis_1   /home/weavewait/weavewait  ...   Up      6379/tcp                       
app_web_1     /home/weavewait/weavewait  ...   Up      192.168.99.102:32773->5000/tcp 
app_web_2     /home/weavewait/weavewait  ...   Up      192.168.99.100:32771->5000/tcp 
app_web_3     /home/weavewait/weavewait  ...   Up      192.168.99.101:32771->5000/tcp 
```

To verify it is working, we must test each of the new instances now.
```
> curl 192.168.99.100:32771
Hello World! I have been seen 4 times.
> curl 192.168.99.101:32771
Hello World! I have been seen 5 times.
```

All working well, 3 web server instance running on different host, connected with Weave and no manual IP assignment required, neither [Docker links limitations](https://github.com/docker/compose/issues/608) get in our way.

## What's next?

You can easily move the entire setup to run on a public cloud, with any of the many providers already available with Docker Machine.

For example, you can follow part of the [Azure guide](https://azure.microsoft.com/en-us/documentation/articles/virtual-machines-docker-machine/#create-the-certificate-and-key-files-for-docker-machine-and-azure) (setup steps 1, 2, and 3), and then set `DOCKER_MACHINE_DRIVER` like this:

    export DOCKER_MACHINE_DRIVER=" \
        --driver azure \
        --azure-subscription-id=SubscriptionID \
        --azure-subscription-cert=mycert.pem \
    "

Clean-up your local VMs, and re-run the cluster setup.

    docker-machine rm -f dev-1 dev-2 dev-3
    ./scripts/setup-cluster.sh


_Now repeat steps 1-5 show earlier._

You can deploy a different app, if you'd like. You don't have to reuse all of my scripts for this purpose, although you certainly might like to take a look at how [Weave proxy is launched](https://github.com/errordeveloper/weave-demos/blob/597a0d78a7d00fd6652c1df8b8562cd0023310f1/quartet/scripts/setup-cluster.sh#L30-L40) and how [Swarm agents](https://github.com/errordeveloper/weave-demos/blob/597a0d78a7d00fd6652c1df8b8562cd0023310f1/quartet/scripts/setup-cluster.sh#L48-L56) and [master](https://github.com/errordeveloper/weave-demos/blob/597a0d78a7d00fd6652c1df8b8562cd0023310f1/quartet/scripts/setup-cluster.sh#L62-L66) are setup agains it.

## Summary

We have just tested out a full setup with Weave integrated into Docker toolchain. We have first setup 3 VMs locally on VirtualBox, then deployed a very simple 2-tier web application. In the upcoming guide, we will take a look into more details on how exactly this works and how you can reproduce an effectively identical setup on a different infrastructure, using only Swarm and Compose agains Docker hosts you would setup yourself.

Follow [@weaveworks](https://twitter.com/weaveworks), so you don't miss any new posts. And you can always drop us a few lines at [team@weave.works](mailto:team@weave.works), to let us know what you think about Weave.