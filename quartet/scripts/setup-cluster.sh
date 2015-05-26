#!/bin/sh -e

source $(git rev-parse --show-toplevel)/quartet/scripts/defaults.sh

for i in '1' '2' '3'; do
  create_machine_with_proxy_setup "${MACHINE_NAME_PREFIX}" "${i}"
done

head_node="${MACHINE_NAME_PREFIX}-1"

for i in '2' '3'; do
  connect_to=$($DOCKER_MACHINE ip "${MACHINE_NAME_PREFIX}-${i}")
  with_machine_env ${head_node} $WEAVE connect ${connect_to}
done

swarm_dicovery_token=$(docker-swarm create)

for i in '1' '2' '3'; do
  weave_proxy_endoint="$($DOCKER_MACHINE ip ${MACHINE_NAME_PREFIX}-${i}):12375"
  with_machine_env "${MACHINE_NAME_PREFIX}-${i}" docker run -d swarm \
    join --addr "${weave_proxy_endoint}" "token://${swarm_dicovery_token}"
done

with_machine_env ${head_node} docker run -d -p 2377:2377 swarm \
  manage -H 0.0.0.0:2377 "token://${swarm_dicovery_token}"
