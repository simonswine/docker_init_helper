
# Check if container name is set
[ -z "${CONTAINER_NAME}" ] && echo "No CONTAINER_NAME is set in env" && exit 1

# Check if bridge name is set
[ -z "${BRIDGE}" ] && echo "No BRIDGE is set in env" && exit 1

# Docker cmd wrapper
docker_cmd() {
    docker $@ ${CONTAINER_NAME} 2> /dev/null > /dev/null
    return $?
}

# Ensure docker container with name ${CONTAINTER_NAME} is removed
docker_ensure_removed() {
    # Check if container exists
    if docker_cmd inspect; then
        if docker_paused; then
            [ "$VERBOSE" != no ] && echo "Unpausing existing container"
            docker_cmd unpause
        fi
        [ "$VERBOSE" != no ] && echo "Removing existing container"
    docker_cmd rm -f
    fi

    # Remove dangling symlinks
    find -L /var/run/netns -type l -delete
}

docker_run() {
    docker run -d --net=none --name=${CONTAINER_NAME} $@ > /dev/null || exit 1
    docker_cmd pause
    docker_net
}

# Check if container is paused
docker_paused() {
    if docker_cmd inspect; then
        if [ "$(docker_inspect '{{.State.Paused}}')" = "true" ]; then
           return 0
        fi
    fi
    return 1
}

# Get pid of container
docker_get_pid(){
    CONTAINER_PID=$(docker_inspect '{{.State.Pid}}')
}

# Setup networking
docker_net() {
    docker_get_pid
    # Generate interface names
    INTF_HOST="veth$(</dev/urandom tr -dc A-Za-z0-9 | head -c 8)"
    INTF_GUEST="veth$(</dev/urandom tr -dc A-Za-z0-9 | head -c 8)"
    [ "$VERBOSE" != no ] && echo "Creating interfaces for pid=${CONTAINER_PID} host=${INTF_HOST} guest=${INTF_GUEST}"

    # create interface
    docker_net_create

    # setup ipv4/v6
    docker_net_setup_v4
    docker_net_setup_v6
}

# Create interfaces
docker_net_create() {
    # Create ns entry
    mkdir -p /var/run/netns
    ln -s /proc/${CONTAINER_PID}/ns/net /var/run/netns/${CONTAINER_PID}

    # Create a pair of "peer" interfaces ${INTF_HOST} and B,
    # bind the {$INTF_GUEST} end to the bridge, and bring it up
    ip link add ${INTF_HOST} type veth peer name ${INTF_GUEST}
    ip link set ${INTF_HOST} up

    [ "$VERBOSE" != no ] && echo "Adding interface ${INTF_HOST} to bridge ${BRIDGE}"
    brctl addif ${BRIDGE} ${INTF_HOST}

    # Place ${INTF_GUEST} inside the container's network namespace and rename to eth0
    ip link set ${INTF_GUEST} netns ${CONTAINER_PID}
    docker_net_run ip link set dev ${INTF_GUEST} name eth0
    docker_net_run ip link set eth0 up
}

# Setup ipv4
docker_net_setup_v4() {
    [ -z "${IPV4_ADDR}" ] && [ -z "${IPV4_GW}" ] && echo "No IPv4 address/gateway given" && return 0
    [ "$VERBOSE" != no ] && echo "Setup IPv4 addresses and routes"
    docker_net_run ip addr add ${IPV4_ADDR} dev eth0
    docker_net_run ip route add default via ${IPV4_GW}
}

# Setup ipv6
docker_net_setup_v6() {
    [ -z "${IPV6_ADDR}" ] && [ -z "${IPV6_GW}" ] && echo "No IPv6 address/gateway given" && return 0
    [ "$VERBOSE" != no ] && echo "Setup IPv6 addresses and routes"
    # set ip and gw
    docker_net_run ip addr add ${IPV6_ADDR} dev eth0
    docker_net_run ip route add default via ${IPV6_GW} dev eth0
    # disable autoconf / accept_ra
    docker_net_run sh -c "echo 0 > /proc/sys/net/ipv6/conf/eth0/autoconf"
    docker_net_run sh -c "echo 0 > /proc/sys/net/ipv6/conf/eth0/accept_ra"
}

# Run cmd in netns
docker_net_run() {
    ip netns exec ${CONTAINER_PID} $@
}

# Resume container
docker_resume() {
    docker_cmd unpause
}

# Resume and attach to container
docker_attach() {
    docker_resume
    docker attach --no-stdin --sig-proxy ${CONTAINER_NAME}
}

docker_inspect(){
    docker inspect -f $1 ${CONTAINER_NAME} 2> /dev/null
}

docker_existing(){
    docker_cmd inspect
    return $?
}

docker_running() {
    [ "$(docker_inspect '{{.State.Running}}')" != "true" ] && return 1
    return 0
}

docker_stop(){
    docker_cmd stop
    docker_ensure_removed
}
