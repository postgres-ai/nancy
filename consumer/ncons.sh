#!/bin/bash
#
# description: Postila Consumers Demon
# processname: node
# pidfile: ./run/pcdem.pid
# logfile: ./log/pcdem.log
#
# To use it as service on Ubuntu:
#
# Then use commands:
# service poauth <command (start|stop|etc)>

NAME=ncons                               # Unique name for the application
SOURCE_DIR=./                            # Location of the application source
COMMAND=node                             # Command to run
SOURCE_NAME=ncons.js                     # Name os the applcation entry point script
USER=$USER                               # User for process running
#NODE_ENVIROMENT=production              # Node environment
NODE_ENVIROMENT=development              # Node environment

#logfile=/var/log/$NAME.log
CUR_DIR=`pwd`
pidfile=/var/tmp/$NAME.pid
logfile=/var/log/$NAME/$NAME.log
forever=forever

if [ $NODE_ENVIROMENT == "development" ]; then
    logfile=$CUR_DIR/log/$NAME.log
    pidfile=$CUR_DIR/run/$NAME.pid
fi

start() {
    if [ -s ${pidfile} ] && kill -0 `cat ${pidfile}` 2>/dev/null; then
        echo "$NAME already started";
        exit;
    fi

    export NODE_ENV=$NODE_ENVIROMENT
    echo "Starting $NAME node instance : "

    touch $logfile
    chown $USER $logfile

    touch $pidfile
    chown $USER $pidfile

    # sudo -H -u $USER 
    cd $SOURCE_DIR; $forever start --pidFile $pidfile -l $logfile -a --sourceDir $SOURCE_DIR -c $COMMAND $SOURCE_NAME; cd -

    RETVAL=$?
}

restart() {
    echo -n "Restarting $NAME node instance : "
    # sudo -H -u $USER 
    $forever restart $SOURCE_NAME
    RETVAL=$?
}

status() {
    echo "Status for $NAME:"
    # sudo -H -u $USER 
    $forever list
    RETVAL=$?
}

stop() {
    echo -n "Shutting down $NAME node instance : "
    # sudo -H -u $USER 
    $forever stop $SOURCE_NAME
}

case "$1" in
    start)
        start
        ;;
    stop)
        stop
        ;;
    status)
        status
        ;;
    restart)
        restart
        ;;
    *)
        echo "Usage:  {start|stop|status|restart}"
        exit 1
        ;;
esac
exit $RETVAL
