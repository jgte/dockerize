#!/bin/bash

DIR=$(cd $(dirname $BASH_SOURCE);pwd)
APPDIR=$($DIR/dockerize.sh app-dir)
IODIR=$($DIR/dockerize.sh io-dir)

if [ $# -eq 0 ]
then
  $BASH_SOURCE help
  exit
fi

case "$1" in
  sh) #run the shell instead of an app
    exec /bin/bash -i
  ;;
  modes) #shows all available modes
    grep ') #' $BASH_SOURCE \
      | grep -v grep \
      | grep -v sed \
      | sed 's_) #_ : _g' \
      | column -t -s\:
  ;;
  apps) #slows all avalable apps
    find $APPDIR -name \*sh -or -name \*py
  ;;
  test-*) #tests an app; some may not yet have a test
    exec $APPDIR/test/${1%.sh}.sh --outdir $IODIR ${@:2}
  ;;
  example-*) #shows the test script of an app
    exec cat $APPDIR/test/test-${1/example-}
  ;;
  help) #show the help string
    echo "\
Possible arguments:
- mode
- app-name app-args

mode is one of:
$($BASH_SOURCE modes)

app-name is one of:
$($BASH_SOURCE apps)

Any sequence of commands that does not start with one of the modes is passed transparently to the container.
"
  ;;
  *) #transparently pass all other arguments to the container
    exec $@
  ;;
esac