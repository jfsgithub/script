#!/bin/bash

# Host names and IDs (note these are NOT security IDs) for validators.

HYPERLEDGER_VALIDATOR_HOSTS=(
	"root@10.0.45.134"
	"root@10.0.45.135"
	"root@10.0.45.136"
	"root@10.0.45.137"
)
HYPERLEDGER_VALIDATOR_IDS=(
    "vp0"
    "vp1"
    "vp2"
    "vp3"
)

# IDs and passwords validators use to log into CA when security is enabled.
HYPERLEDGER_SECURITY_IDS=(
    "test_vp0"
    "test_vp1"
    "test_vp2"
    "test_vp3"
)
HYPERLEDGER_SECURITY_SECRETS=(
    "MwYpmSRjupbT"
    "5wgHK9qqYaPy"
    "vQelbRvja7cJ"
    "9LKqKH5peurL"
)

HYPERLEDGER_GOPATH="/home/appadmin/golang"
HYPERLEDGER_EXEPATH="$HYPERLEDGER_GOPATH/src/github.com/hyperledger/fabric"
HYPERLEDGER_FSPATH="/var/hyperledger/production"
HYPERLEDGER_LOGPATH="/var/log"

# Settings for OBC CA server when security is enabled.
HYPERLEDGER_CA_HOST="10.0.45.134"
HYPERLEDGER_CA_PORT="50051"
HYPERLEDGER_CA_PATH="$HYPERLEDGER_EXEPATH/membersrvc"
HYPERLEDGER_CA_BINARY="membersrvc"
HYPERLEDGER_CA_ARGUMENTS=""
HYPERLEDGER_CA_LOGFILE="$HYPERLEDGER_LOGPATH/membersrvc.log"
HYPERLEDGER_CA_PRODDB="$HYPERLEDGER_FSPATH/.membersrvc/*"

# Settings for OBC validator (aka peer).
HYPERLEDGER_PEER_ROOT="10.0.45.134"
HYPERLEDGER_PEER_PORT="30303"
HYPERLEDGER_PEER_PATH="$HYPERLEDGER_EXEPATH/peer"
HYPERLEDGER_PEER_BINARY="peer"
HYPERLEDGER_PEER_ARGUMENTS="node start"
HYPERLEDGER_PEER_LOGFILE="$HYPERLEDGER_LOGPATH/peer.log"
HYPERLEDGER_PEER_PRODDB="$HYPERLEDGER_FSPATH/*"

DOCKER_DAEMON_CMD="docker daemon -s devicemapper -H tcp://0.0.0.0:4243 -H unix:///var/run/docker.sock >/var/log/docker.log 2>&1 &"

# One of start, stop, and status is mandatory. The rest are optional and
# can come in any order.
if ! [[ "$1" =~ ^(start|stop|status)$ ]]; then
    echo "Usage: $0 {start|stop|status}"
    echo "           [#] [reset] [secure]"
    echo "           [noops|batch|classic|sieve]"
    echo "           [critical|error|warning|notice|info|debug]"
    echo
    echo "       You must specify one of start, stop, or status. The rest are optional"
    echo "       and can be specified in any order."
    echo
    echo "Options:"
    echo "        #  An integer indicating to start Hyperledger only on"
    echo "           the first # number of nodes in the list."
    echo
    echo "    reset  Clear all Hyperledger states to start afresh."
    echo
    echo "   secure  Enable security and privacy."
    echo
    echo "    noops| Set consensus protocol to noops (the default) or pbft"
    echo "    batch|"
    echo "  classic| Specify one of batch, classic, or sieve for the desired"
    echo "    sieve  pbft mode."
    echo
    echo " critical| Set log level to the specific level. Default is info."
    echo "    error|"
    echo "  warning| Note that if you specify arguments in the same category"
    echo "   notice| multiple times, e.g., critical warning debug, then the"
    echo "     info| last one will be taken, i.e., log level will be debug"
    echo "    debug  in the example above."
    exit
fi
action=$1
shift

hyperledger_nhosts=${#HYPERLEDGER_VALIDATOR_HOSTS[@]}
hyperledger_consensus="pbft"
hyperledger_loglevel="info"

# Process all the optional arguments.
while test ${#} -gt 0; do
    # If it's an integer, it's the number of hosts/VMs we want to start Hyperledger on.
    if [ "$1" -eq "$1" ] 2>/dev/null; then
	hyperledger_nhosts="$1"
    # Turn on secure flag.
    elif [ "$1" = "secure" ]; then
	hyperledger_secure="true"
    # Turn on reset flag.
    elif [ "$1" = "reset" ]; then
	hyperledger_reset="true"
    # Set consensus protocol.
    elif [[ "$1" =~ ^(noops|batch|classic|sieve)$ ]]; then
	if [ "$1" = "noops" ]; then
	    hyperledger_consensus="noops"
	else
	    hyperledger_consensus="pbft"
	    hyperledger_mode=$1
	fi
    # Set log level.
    elif [[ "$1" =~ ^(critical|error|warning|notice|info|debug)$ ]]; then
	hyperledger_loglevel=$1
    fi
    shift
done

i=0
if [ "$action" = "status" ]; then
    # Loop until we reach the max number of hosts or the number specified.
    if [ "$hyperledger_secure" = "true" ]; then
	vhost=$HYPERLEDGER_CA_HOST
	vipaddr=`ssh $vhost "hostname -i 2>/dev/null"`
	vipaddr=${vipaddr:-0.0.0.0}
	echo ========== $vhost [$vipaddr] ==========
	ssh $vhost "ps ax|grep 'membersrvc'|grep -v grep"
    fi
    
    while [ "${HYPERLEDGER_VALIDATOR_HOSTS[i]}" != "" ] && [ "$i" -lt "$hyperledger_nhosts" ]; do
	vhost=${HYPERLEDGER_VALIDATOR_HOSTS[i]}
	vipaddr=`ssh $vhost "hostname -i 2>/dev/null"`
	vipaddr=${vipaddr:-0.0.0.0}
	echo ========== $vhost [$vipaddr] ==========
	ssh $vhost "ps ax|grep '\./$HYPERLEDGER_PEER_BINARY\|docker'|grep -v grep"
	if [ "`ssh $vhost pidof docker`" != "" ]; then
	    echo ----------
	    ssh $vhost "docker ps -a"
	    echo ----------
	    ssh $vhost "docker images"
	fi
	echo
	(( i += 1))
    done
elif [ "$action" = "start" ]; then
    # Start membersrvc
    if [ "$hyperledger_secure" = "true" ]; then
	if [ "`ssh $HYPERLEDGER_CA_HOST pidof $HYPERLEDGER_CA_BINARY`" != "" ]; then
	    echo "$HYPERLEDGER_CA_BINARY already running on $HYPERLEDGER_CA_HOST"
	else
	    if [ "$hyperledger_reset" = "true" ]; then
		echo "Reset $HYPERLEDGER_CA_HOST:$HYPERLEDGER_CA_PRODDB"
		ssh $HYPERLEDGER_CA_HOST "rm -rf $HYPERLEDGER_CA_PRODDB"
	    fi

	    cmd=""
	    cmd="$cmd GOPATH=$HYPERLEDGER_GOPATH"
	    cmd="$cmd ./$HYPERLEDGER_CA_BINARY $HYPERLEDGER_CA_ARGUMENTS <&- >$HYPERLEDGER_CA_LOGFILE 2>&1 &"
	    echo "Start $HYPERLEDGER_CA_BINARY on $HYPERLEDGER_CA_HOST"
	    ssh $HYPERLEDGER_CA_HOST "cd $HYPERLEDGER_CA_PATH; $cmd"
	fi
    fi

    # Start validators
    while [ "${HYPERLEDGER_VALIDATOR_HOSTS[i]}" != "" ] && [ "$i" -lt "$hyperledger_nhosts" ]; do
	vhost=${HYPERLEDGER_VALIDATOR_HOSTS[i]}
	vid=${HYPERLEDGER_VALIDATOR_IDS[i]}
	sid=${HYPERLEDGER_SECURITY_IDS[i]}
	secret=${HYPERLEDGER_SECURITY_SECRETS[i]}

	vipaddr=`ssh $vhost "hostname -i 2>/dev/null"`
	vipaddr=${vipaddr:-0.0.0.0}
	
	echo ========== $vhost [$vipaddr] ==========
	if [ "`ssh $vhost pidof $HYPERLEDGER_PEER_BINARY`" != "" ]; then
	    echo "$HYPERLEDGER_PEER_BINARY already running on $vhost"
	    (( i += 1))
	else
	    if [ "`ssh $vhost pidof docker`" = "" ]; then
		echo "docker daemon not running...starting"
		ssh $vhost "$DOCKER_DAEMON_CMD"
		sleep 2
	    fi
	    
	    if [ "$hyperledger_reset" = "true" ]; then
		echo "Reset $vhost:$HYPERLEDGER_PEER_PRODDB"
		ssh $vhost "rm -rf $HYPERLEDGER_PEER_PRODDB"

		echo "Reset docker containers and images"
		ssh $vhost "docker rm \`docker ps -a --no-trunc|grep 'sha256\|dev-$vid'|awk '{print \$1}'\` >/dev/null 2>&1"
		ssh $vhost "docker rmi \`docker images|grep 'none\|dev-$vid'|awk '{print \$3}'\` >/dev/null 2>&1"
	    fi

	    # Set all the env variables that will override settings in openchain.yaml.
	    cmd=""
	    # Set rootnode for all the validators except the root node itself.
	    if [ $i -ne 0 ]; then
		cmd="CORE_PEER_DISCOVERY_ROOTNODE=$HYPERLEDGER_PEER_ROOT:$HYPERLEDGER_PEER_PORT"
	    fi
	    cmd="$cmd CORE_PEER_ID=$vid"
	    #cmd="$cmd CORE_PEER_ADDRESSAUTODETECT=false"
	    #cmd="$cmd CORE_PEER_LISTENADDRESS=0.0.0.0:$HYPERLEDGER_PEER_PORT"
	    cmd="$cmd CORE_PEER_ADDRESS=$vipaddr:$HYPERLEDGER_PEER_PORT"
	    cmd="$cmd CORE_LOGGING_LEVEL=$hyperledger_loglevel"
	    #cmd="$cmd CORE_LOGGING_LEVEL=debug"
            cmd="$cmd CORE_LOGGING_CRYPTO=$hyperledger_loglevel"
            cmd="$cmd CORE_PEER_VALIDATOR_CONSENSUS_PLUGIN=$hyperledger_consensus"
	    if [ "$hyperledger_consensus" = "pbft" ]; then
		cmd="$cmd CORE_PBFT_GENERAL_N=$hyperledger_nhosts"
		cmd="$cmd CORE_PBFT_GENERAL_MODE=$hyperledger_mode"
	    fi
	    if [ "$hyperledger_secure" = "true" ]; then
		cmd="$cmd CORE_PEER_PKI_ECA_PADDR=$HYPERLEDGER_CA_HOST:$HYPERLEDGER_CA_PORT"
		cmd="$cmd CORE_PEER_PKI_TCA_PADDR=$HYPERLEDGER_CA_HOST:$HYPERLEDGER_CA_PORT"
		cmd="$cmd CORE_PEER_PKI_TLSCA_PADDR=$HYPERLEDGER_CA_HOST:$HYPERLEDGER_CA_PORT"
		cmd="$cmd CORE_SECURITY_ENABLED=true"
		cmd="$cmd CORE_SECURITY_PRIVACY=false"
		cmd="$cmd CORE_SECURITY_ENROLLID=$sid"
		cmd="$cmd CORE_SECURITY_ENROLLSECRET=$secret"
	    fi
	    cmd="$cmd GOPATH=$HYPERLEDGER_GOPATH"
	    cmd="$cmd ./$HYPERLEDGER_PEER_BINARY $HYPERLEDGER_PEER_ARGUMENTS <&- >$HYPERLEDGER_PEER_LOGFILE 2>&1 &"
	    echo "Start $HYPERLEDGER_PEER_BINARY on $vhost"
	    #echo cmd=$cmd
	    ssh $vhost "cd $HYPERLEDGER_PEER_PATH; $cmd"

	    # Increment the index. Wait for 2 seconds before starting the next validator.
	    (( i += 1))
	    if [ $i -lt 4 ]; then
		sleep 2
	    fi
	fi
    done
elif [ "$action" = "stop" ]; then
    # Stop validators
    while [ "${HYPERLEDGER_VALIDATOR_HOSTS[i]}" != "" ] && [ "$i" -lt "$hyperledger_nhosts" ]; do
	vhost=${HYPERLEDGER_VALIDATOR_HOSTS[i]}
	vid=${HYPERLEDGER_VALIDATOR_IDS[i]}

	vipaddr=`ssh $vhost "hostname -i 2>/dev/null"`
	vipaddr=${vipaddr:-0.0.0.0}
	
	echo ========== $vhost [$vipaddr] ==========
	if [ "`ssh $vhost pidof $HYPERLEDGER_PEER_BINARY`" = "" ]; then
	    echo $HYPERLEDGER_PEER_BINARY not running on $vhost
	else
	    echo Stop $HYPERLEDGER_PEER_BINARY on $vhost
	    ssh $vhost "killall $HYPERLEDGER_PEER_BINARY >/dev/null 2>&1"
	fi
	
	if [ "$hyperledger_reset" = "true" ]; then
	    echo "Reset $vhost:$HYPERLEDGER_PEER_PRODDB"
	    ssh $vhost "rm -rf $HYPERLEDGER_PEER_PRODDB"
	    
	    if [ "`ssh $vhost pidof docker`" = "" ]; then
		echo "docker daemon not running...starting"
		ssh $vhost "$DOCKER_DAEMON_CMD"
	    fi
	    echo "Reset docker containers and images"
	    ssh $vhost "docker rm \`docker ps -a --no-trunc|grep 'sha256\|dev-$vid'|awk '{print \$1}'\` >/dev/null 2>&1"
	    ssh $vhost "docker rmi \`docker images|grep 'none\|dev-$vid'|awk '{print \$3}'\` >/dev/null 2>&1"
	fi
	
	(( i += 1))
    done

    # Stop membersrvc
    if [ "$hyperledger_secure" = "true" ]; then
	if [ "`ssh $HYPERLEDGER_CA_HOST pidof $HYPERLEDGER_CA_BINARY`" = "" ]; then
	    echo "$HYPERLEDGER_CA_BINARY not running on $HYPERLEDGER_CA_HOST"
	else
	    echo "Stop $HYPERLEDGER_CA_BINARY on $HYPERLEDGER_CA_HOST"
	    ssh $HYPERLEDGER_CA_HOST "killall $HYPERLEDGER_CA_BINARY >/dev/null 2>&1"
	fi
	
	if [ "$hyperledger_reset" = "true" ]; then
	    echo "Reset $HYPERLEDGER_CA_HOST:$HYPERLEDGER_CA_PRODDB"
	    ssh $HYPERLEDGER_CA_HOST "rm -rf $HYPERLEDGER_CA_PRODDB"
	fi
    fi
fi
