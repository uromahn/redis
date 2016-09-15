#!/bin/bash
set -e

# first arg is `-f` or `--some-option`
# or first arg is `something.conf`
if [ "${1#-}" != "$1" ] || [ "${1%.conf}" != "$1" ]; then
	set -- redis-server "$@"
fi

# allow the container to be started with `--user`
if [ "$1" = 'redis-server' -a "$(id -u)" = '0' ]; then
	chown -R redis .
	exec gosu redis "$0" "$@"
fi

if [ "$1" = 'redis-server' ]; then
	# Disable Redis protected mode [1] as it is unnecessary in context
	# of Docker. Ports are not automatically exposed when running inside
	# Docker, but rather explicitely by specifying -p / -P.
	# [1] https://github.com/antirez/redis/commit/edd4d555df57dc84265fdfb4ef59a4678832f6da
	doProtectedMode=1
	configFile=
	if [ -f "$2" ]; then
		configFile="$2"
		if grep -q '^protected-mode' "$configFile"; then
			# if a config file is supplied and explicitly specifies "protected-mode", let it win
			doProtectedMode=
		fi
	fi
	if [ "$doProtectedMode" ]; then
		shift # "redis-server"
		if [ "$configFile" ]; then
			shift
		fi
		set -- --protected-mode no "$@"
		if [ "$configFile" ]; then
			set -- "$configFile" "$@"
		fi
		set -- redis-server "$@" # redis-server [config file] --protected-mode no [other options]
		# if this is supplied again, the "latest" wins, so "--protected-mode no --protected-mode yes" will result in an enabled status
	fi
fi

if [ "$1" = 'redis-cluster' ]; then
	# Disable Redis protected mode [1] as it is unnecessary in context
	# of Docker. Ports are not automatically exposed when running inside
	# Docker, but rather explicitely by specifying -p / -P.
	# [1] https://github.com/antirez/redis/commit/edd4d555df57dc84265fdfb4ef59a4678832f6da
	doProtectedMode=1
	configFile=
	if [ -f "$2" ]; then
		configFile="$2"
		if grep -q '^protected-mode' "$configFile"; then
			# if a config file is supplied and explicitly specifies "protected-mode", let it win
			doProtectedMode=
		fi
	fi
	if [ "$doProtectedMode" ]; then
		shift # "redis-cluster"
		if [ "$configFile" ]; then
			shift
		fi
		set -- --protected-mode no "$@"
		if [ "$configFile" ]; then
			set -- "$configFile" "$@"
		fi
		set -- redis-server "$@" --cluster-enabled yes --appendonly yes # redis-server [config file] --protected-mode no [other options] --cluster-enabled yes --appendonly yes 
		# if this is supplied again, the "latest" wins, so "--protected-mode no --protected-mode yes" will result in an enabled status
	fi
fi

if [ "$1" = 'cluster-create' ]; then
  shift # "cluster-create"
  commandLine="--replicas"
  count=1
  for arg in "$@"
  do
    # The first parameter is expected to be the replicas count
    if [ "$count" -eq 1 ]
    then
      commandLine="$commandLine $arg"
      count=$((count+1))
      continue
    fi
    # Now parse the hosts
    arg2=${arg//[:]/ }
    host=($arg2)
    # we need to determine the ip address from the given hostname now
    hostname="${host[0]}"
    port="${host[1]}"
    hostIp=$(getent hosts $hostname | awk '{ print $1 }')
    # concatenate the hostIp and port for our final command line
    hostPort="$hostIp:$port"
    # But test if the host is available first
    wait-for-it.sh --timeout=10 "$hostPort"
    testResult="$?"
    if [ "$?" -gt 0 ]
    then
      echo "Node " "$hostPort" " unavailable - aborting cluster creation!"
      exit 1
    fi
    commandLine="$commandLine $hostPort"
  done
  set -- redis-trib.rb create $commandLine
  echo "Creating cluster with: " "$@"
fi

exec "$@"
