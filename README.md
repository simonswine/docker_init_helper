Docker init helpers
=====================

Shell helper functions for launching docker containers via supervisors.


Features:
--------------

- Bridged networking for container with dedicated IPv4/IPv6
- Create container from scratch everytime
- Examples for supervisors:
-- Traditional init.d
-- Upstart


Usage (tested with Ubuntu 14.04)
--------------

Clone this repo to `/usr/local/docker_init_helper/`

Disable the restart feature of the Docker daemon in `/etc/default/docker`:

```shell
DOCKER_OPTS="-r=false"
```

Create a Upstart service defintion for the docker container (e.g. in `/etc/init/docker-example.conf`). This container would have a dedicated IPv4/IPv6 address, as specified in the enviroment variables:

```shell
description "Docker container example"
author "Christian Simon <simon@swine.de>"
start on filesystem and started docker
stop on runlevel [!2345]
respawn
env CONTAINER_NAME=example-upstart
env BRIDGE=vmbr0
env IPV4_ADDR=172.20.64.42/24
env IPV4_GW=172.20.64.254
env IPV6_ADDR=2001:db8::42/64
env IPV6_GW=fe80::1
env PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:/usr/games:/usr/local/games
script
  # Load docker extensions
  . /usr/local/docker_init_helper/docker_init_helper.sh    
  docker_ensure_removed

  # Change docker_run according your needs
  docker_run \
    -u 1000 \
    -v /tmp/my_volume:/data \
    busybox \
    nc -l -p 1234
    
  # Setup some special things (e.g. firewall rules)
  ## Redirect privileged ports
  docker_net_run iptables -t nat -A PREROUTING -i eth0 -p tcp --dport 50 -j REDIRECT --to-ports 1234

  # Go!
  docker_attach
end script
post-stop script
  # Load docker extensions
  . /usr/local/docker_init_helper/docker_init_helper.sh    
  
  # Stop and remove container
  docker_stop
end script
```

Now you can use the container with the standard upstart commands:

```
start docker-example
stop docker-example
status docker-example
restart docker-example
```


Examples
-----------

- [init.d](examples/container-initd)
- [Upstart](examples/container-upstart.conf)



Author
------

[Christian Simon](https://github.com/simonswine)

