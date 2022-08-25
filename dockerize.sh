#!/bin/bash -ue

#This script intends to make it easier to build containers. There are 3 directories of relevance:
# - DIR            : the directory this script is run
# - DIR/dockerize  : dir where this repo is cloned
# - <app-repo>     : dir with the software to be dockerized or github URL
#
# The procedure is:
# - git close this repo inside DIR, so that you'll have a new 'dockerize' sub-dir
# - link the DIR/dockerize/dockerize.sh script into DIR
# - copy the DIR/dockerize/dockerize.par file into DIR; edit it as needed
# - copy the DIR/dockerize/entrypoint.sh file into DIR; change if necessary
# - run the relevant commands in this script, e.g.:
#   - ./dockerize.sh build sh
#
# The relevant directores in the container are:
# - /iodir      : points to DIR (static value, must be in agreement with entrypoint.sh)
# - /<app-name> : contains the contents of DIR/<app-repo>, is set as the WORKDIR in the container

DIR=$(cd $(dirname $BASH_SOURCE);pwd)
AUTO_GIT_CI=false

if [ $# -eq 0 ]
then
  $BASH_SOURCE help
  exit
fi

MODE="$(echo "$1"| tr '[:upper:]' '[:lower:]')"
case "$MODE" in
  modes|help|-h) #shows all available modes
    grep ') #' $BASH_SOURCE \
      | grep -v grep \
      | sed 's:)::g' \
      | column -t -s\#
  ;;
  author|dockerhub-user|app-repo|app-name|base-image-name|base-image-com|base-image-dockerfile|image-run-more) #get app parameters from dockerize.par
    if ! grep -q "$MODE" $DIR/dockerize.par
    then
      echo "ERROR: need file $DIR/dockerize.par to contain the entry '$MODE' followed by a valid value" 1>&2
      exit 3
    fi
    awk '/^'$MODE' / {if (NF==2) {print $2} else {for (i=2; i<=NF; i++) printf("%s ",$i); printf("\n")}}' $DIR/dockerize.par
  ;;
  app-dir) #shows the directory where the app will be sitting inside the container
    echo /$($BASH_SOURCE app-name)
  ;;
  io-dir) #shows the directory where the files will be save to inside the container
    echo /iodir
  ;;
  version) #shows the latest version of the git repo (to be used as tag for the docker image)
    git -C $DIR log --pretty=format:%ad --date=short | head -n1
  ;;
  pwd) #shows the current directory
    echo $DIR
  ;;
  is-docker-running) #checks if the docker deamon is running
    docker ps -a > /dev/null && exit 0 || exit 1
  ;;
  base-image|base-images) #shows all images relevant to this app
    $BASH_SOURCE is-docker-running || exit 1
    BASE_IMAGE=$($BASH_SOURCE base-image-name); BASE_IMAGE=${BASE_IMAGE%:*}
    if ! docker images | grep $BASE_IMAGE
    then
      echo "NOTICE: image $($BASH_SOURCE base-image-name) missing, pulling it:" 1>&2
      docker pull $($BASH_SOURCE base-image-name)  1>&2
      $BASH_SOURCE base-image
    fi
  ;;
  base-dockerfile) #shows the dockerfile of the base image
    BASE_IMAGE_DOCKERFILE="$($BASH_SOURCE base-image-dockerfile)"
    if [ -z "$BASE_IMAGE_DOCKERFILE" ]
    then
      echo "FROM alpine:3.9.6"
    else
      if [ -e "$BASE_IMAGE_DOCKERFILE" ]
      then
        cat "$BASE_IMAGE_DOCKERFILE"
      elif [[ ! "${BASE_IMAGE_DOCKERFILE/ubuntu}" == "$BASE_IMAGE_DOCKERFILE" ]]
      then
        echo "FROM $BASE_IMAGE_DOCKERFILE"
        echo "ENV DEBIAN_FRONTEND=noninteractive"
      elif [[ ! "${BASE_IMAGE_DOCKERFILE/alpine}" == "$BASE_IMAGE_DOCKERFILE" ]]
      then
        echo "FROM $BASE_IMAGE_DOCKERFILE"
      elif [[ ! "${BASE_IMAGE_DOCKERFILE/https}" == "$BASE_IMAGE_DOCKERFILE" ]]
      then
        BDF=/tmp/$(basename $BASH_SOURCE).$($BASH_SOURCE app-name).base_dockerfile.$$
        wget "$BASE_IMAGE_DOCKERFILE" -O "$BDF"
        cat "$BDF"
        rm -f "$BDF"
        echo "#NOTE: the lines below have been added by user $($BASH_SOURCE author) to build docker image '$($BASH_SOURCE url)'"
      else
        echo "ERROR: cannot handle base-image-dockerfile with value '$BASE_IMAGE_DOCKERFILE'."
        exit 3
      fi
    fi
    $BASH_SOURCE base-image-com
  ;;
  base-pull) #pull the base image
    docker pull $($BASH_SOURCE base-image-name)
  ;;
  base-push) #push the base image
    docker push $($BASH_SOURCE base-image-name)
  ;;
  base-rebuild|base-build) #build the base image (slow, should not change significantly)
    $BASH_SOURCE is-docker-running || exit 1
    BASE_IMAGE=$($BASH_SOURCE base-image-name)
    #check if this base image is owned by dockerhub-user
    if [[ ! "${BASE_IMAGE/$($BASH_SOURCE dockerhub-user)}" == "$BASE_IMAGE" ]]
    then
      #build and push the base image
      IDs=$(echo "$BASE_IMAGE" | awk '{print $3}')
      [ -z "$IDs" ] || docker rmi -f $IDs
      $BASH_SOURCE base-dockerfile | docker build -t $BASE_IMAGE -
    else
      echo "WARNING: the base image ($BASE_IMAGE) is not owned by user $($BASH_SOURCE dockerhub-user) and it cannot be rebuilt. Ignoring..."
    fi
  ;;
  base-sh) #spins up a new container and starts an interactive shell in it
    $BASH_SOURCE is-docker-running || exit 1
    LOCAL_MNT=/tmp/$($BASH_SOURCE app-name)
    CONTN_MNT=$($BASH_SOURCE io-dir)
    mkdir -p $LOCAL_MNT
    docker run -v $LOCAL_MNT:$CONTN_MNT -it --rm $($BASH_SOURCE base-image-name) /bin/bash
  ;;
  image-name) #shows the image name
    echo $($BASH_SOURCE dockerhub-user)/$($BASH_SOURCE app-name):$($BASH_SOURCE version)
  ;;
  url) #shows the docker image URL
    echo docker://$($BASH_SOURCE image-name)
  ;;
  dockerfile) #show the dockerfile
    APPREPO=$($BASH_SOURCE app-repo)
    RUN_MORE="$($BASH_SOURCE image-run-more)"
    #handle implicit keywords
    case $APPREPO in
      pwd) APPREPO="$PWD" ;;
    esac
    #handle different app source
    if [ -d "$APPREPO" ]
    then
      GITCOM="COPY $APPREPO ."
    elif [[ ! "${APPREPO/github}" == "${APPREPO}" ]]
    then
      GITCOM="RUN git clone --recurse-submodules $APPREPO . && rm -fr .git"
    else
      echo "ERROR: cannot handle parameter app-repo with value '$APPREPO'"
      exit 3
    fi
    [ -z "$RUN_MORE" ] || GITCOM+="
$RUN_MORE"
    #shortcuts
    APP_DIR=$($BASH_SOURCE app-dir)
    #build dockerfile
  echo "\
FROM $($BASH_SOURCE base-image-name)
VOLUME $($BASH_SOURCE io-dir)
WORKDIR $($BASH_SOURCE app-dir)
$GITCOM
COPY entrypoint.sh $APP_DIR/
ENTRYPOINT [\"$APP_DIR/entrypoint.sh\"]
CMD [\"help\"]
RUN chmod -R a+rX $APP_DIR/*.sh $APP_DIR/*.pl $APP_DIR/*.rb $APP_DIR/*.py || true
$(for i in Author; do echo "LABEL $i \"$($BASH_SOURCE $i)\""; done)
"
  ;;
  ps-a) #shows all containers IDs for the latest version of the image
    $BASH_SOURCE is-docker-running || exit 1
    docker ps -a | grep $($BASH_SOURCE image-name) | awk '{print $1}'
  ;;
  ps-exited) #shows all containers IDs for the latest version of the image that have exited
    $BASH_SOURCE is-docker-running || exit 1
    docker ps -a | grep $($BASH_SOURCE image-name) | awk '/Exited \(/ {print $1}'
  ;;
  image|images) #shows all images relevant to this app
    $BASH_SOURCE is-docker-running || exit 1
    docker images | grep $($BASH_SOURCE dockerhub-user)/$($BASH_SOURCE app-name)
  ;;
  clean-none|clear-none) #removes all images with tag '<none>' as well as the corresponding containers
    $BASH_SOURCE is-docker-running || exit 1
    for i in $(docker images | awk '/<none>/ {print $3}')
    do
      IDs=$(docker ps -a |awk '/'$i'/ {print $1}')
      [ -z "$IDs" ] || docker rm $IDs
      docker rmi $i
    done
  ;;
  clean-exited|clear-exited) #removes all exited containers for the latest version of the image
    $BASH_SOURCE is-docker-running || exit 1
    IDs=$($BASH_SOURCE ps-exited)
    [ -z "$IDs" ] || docker rm $IDs
  ;;
  clean-images) #removes all images relevant to this app
    $BASH_SOURCE is-docker-running || exit 1
    IDs=$($BASH_SOURCE images | awk '{print $3}')
    [ -z "$IDs" ] || docker rmi -f $IDs
  ;;
  clean-all|clear-all) #removes all relevant images and containers
    for i in clean-exited clean-images clean-none
    do
      $BASH_SOURCE $i
    done
  ;;
  git-push) #git adds, commits and pushes all new changes
    cd $DIR/dockerize && ./git.sh
    cd $DIR && ./git.sh
  ;;
  push) #pushes images to dockerhub
    $BASH_SOURCE is-docker-running || exit 1
    docker push $($BASH_SOURCE image-name)
  ;;
  ready-to-build) #does some basic sanity checks
    #update the entry point, unless that has already been done (contemplates tweaking this file)
    [ ! -s $DIR/entrypoint.sh ] && \
      cat $DIR/dockerize/entrypoint.sh \
      | sed 's:{APP-NAME}:'$($BASH_SOURCE  app-dir)':g' \
      > $DIR/entrypoint.sh
    chmod u+x $DIR/entrypoint.sh
    #make sure necessary files exist
    for i in dockerize.par
    do
      if [ ! -s $DIR/$i ]; then
        echo "ERROR: missing: $DIR/$i"
        exit 3
      fi
    done
    #make sure all necessary variables are set
    for i in base-image dockerhub-user app-name app-repo
    do
      if [ -z "$($BASH_SOURCE $i)" ]
      then
        echo "ERROR: value of parameter '$i' is unset"
        exit 3
      fi
    done
  ;;
  build) #build the docker image
    $BASH_SOURCE is-docker-running || exit 1
    $BASH_SOURCE ready-to-build
    $BASH_SOURCE clean-images
    $AUTO_GIT_CI && $BASH_SOURCE git-push
    $BASH_SOURCE dockerfile > $DIR/dockerfile
    cd $DIR && docker build . -t $($BASH_SOURCE image-name) -f dockerfile && rm -fv dockerfile && cd -
  ;;
  rebuild) #same as clean-exited clean-images build
    for i in clean-all build
    do
      $BASH_SOURCE $i || exit $?
    done
  ;;
  sh) #spins up a new container and starts an interactive shell in it
    $BASH_SOURCE is-docker-running || exit 1
    [ -z "$($BASH_SOURCE images)" ] && $BASH_SOURCE build
    docker run -it --rm --volume=$PWD:$($BASH_SOURCE io-dir) $($BASH_SOURCE image-name) sh
  ;;
  run) #spins up a new container and passes all aditional arguments to it
    $BASH_SOURCE is-docker-running || exit 1
    [ -z "$($BASH_SOURCE images)" ] && $BASH_SOURCE build
    docker run --rm --volume=$PWD:$($BASH_SOURCE io-dir) $($BASH_SOURCE image-name) ${@:2}
  ;;
  # ---------- TACC stuff ---------
  s-module) #load singularity module in tacc
    if which module
    then
      module load tacc-singularity
    else
      echo "WARNING: cannot load module, possibly this is not a TACC machine?"
      exit 3
    fi
  ;;
  s-image) #return the name of the singularity image file
    echo $DIR/$($BASH_SOURCE app-name)_$($BASH_SOURCE version).sif
  ;;
  s-pull) #pulls the singularity image from docker hub
    $BASH_SOURCE s-module || true
    singularity pull --name $($BASH_SOURCE s-image) docker://$($BASH_SOURCE image-name)
  ;;
  s-sh) #spins up a new singularity container and starts an interactive shell in it
    $BASH_SOURCE s-module || true
    [ -e $($BASH_SOURCE s-image) ] || $BASH_SOURCE s-pull
    singularity shell -B $PWD:$($BASH_SOURCE io-dir) --cleanenv $($BASH_SOURCE s-image)
  ;;
  s-shw) #spins up a new writable singularity container and starts an interactive shell in it
    $BASH_SOURCE s-module || true
    [ -e $($BASH_SOURCE s-image)w ] || singularity build --sandbox $($BASH_SOURCE s-image)w docker://$($BASH_SOURCE image-name)
    singularity shell -B $PWD:$($BASH_SOURCE io-dir) --cleanenv $($BASH_SOURCE s-image)w
  ;;
  s-com) #shows the command used to run the app it the singularity container
   echo singularity exec -B $PWD:/$($BASH_SOURCE io-dir) --cleanenv $($BASH_SOURCE s-image) $($BASH_SOURCE app-dir)/entrypoint.sh ${@:2}
  ;;
  s-run) #spins up a new singularity container and passes all aditional arguments to it
    $BASH_SOURCE s-module || true
    [ -e $($BASH_SOURCE s-image) ] || $BASH_SOURCE s-pull
    $($BASH_SOURCE s-com) ${@:2}
  ;;
  s-slurm-script) #shows the slurm script used to commit an instance of the app to the grace-serial queue
    echo "\
#!/bin/bash

#SBATCH -J $($BASH_SOURCE app-name)
#SBATCH -o $($BASH_SOURCE app-name).o.%j
#SBATCH -e $($BASH_SOURCE app-name).e.%j
#SBATCH -p grace-serial
#SBATCH -N 1
#SBATCH -n 1
#SBATCH -t 00:01:00
#SBATCH -A A-byab

module load tacc-singularity

$($BASH_SOURCE s-com) $(for i in "${@:2}"; do echo -n "\"$i\" "; done)
"
  ;;
  s-submit) #submits a job with a call to the app to the grace-queue
    $BASH_SOURCE s-slurm-script "${@:2}" > $PWD/$($BASH_SOURCE app-name).slurm
    sbatch $PWD/$($BASH_SOURCE app-name).slurm
  ;;
  *)
    echo "ERROR: cannot handle input argument '$1'"
    exit 3
  ;;
esac
