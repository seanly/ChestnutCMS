#!/bin/bash
# vim: set ft=sh:

CURDIR=`dirname $0`

# --// options
set -ex

EXITCODE=0
PROGRAM=`basename $0`
VERSION=0.0.1

# --// functions 
error()
{
  echo "$@" 1>&2
  usage_and_exit 1
}

usage()
{
  echo "Usage:buildx.sh [-o local|registry|docker] [-f docker-compose.yml] [--platform linux/arm64,linux/amd64] svc_name"
}

usage_and_exit()
{
  usage
  exit $1
}

version()
{
  echo "$PROGRAM version $VERSION"
}

warning()
{
  echo "$@" 1>&2
  EXITCODE=`expr $EXITCODE + 1`
}

debug_watch()
{
  if [ -z ${DEBUG} ]; then
    return
  fi

  if [[ $1 == $2 ]]; then
    debug
  fi
}

debug()
{
  if [ -z ${DEBUG} ]; then
    return
  fi
  echo "#############|  Entering DEBUG mode  |####################";
  CMD=""
  while [[ $CMD != "exit" ]]; do
    read -p "> " CMD
    case $CMD in
      vars)
        ( set -o posix ; set )
        ;;
      exit)
        ;;
      * ) eval $CMD;;
    esac
  done
  echo "#############|  End of DEBUG mode |####################";
}
# --// main 

_OUTPUT=docker
_COMPOSE_FILE=docker-compose.yml
_PLATFORM= # linux/amd64,linux/arm64

while test $# -gt 0
do
  case $1 in
    -o)
      shift
      if [ ! x$1 == x'' ]; then
        _OUTPUT=$1
      else
        error "Unrecognized option $1"
      fi
      ;;
    -f)
      shift
      if [ ! x$1 == x'' ]; then
        _COMPOSE_FILE=$1
      else
        error "Unrecognized option $1"
      fi
      ;;

    --platform)
      shift
      if [ ! x$1 == x'' ]; then
        _PLATFORM=--platform=$1
      else
        error "Unrecognized option $1"
      fi
      ;;
       
    --debug)
      DEBUG=true
      ;;
    --help | --hel | --he | --h | '--?' | -help | -h | '-?')
      usage_and_exit 0
      ;;
    --version | -v )
      version
      exit 0
      ;;
    -*)
      error "Unrecognized option $1"
      ;;
    *)
      break
      ;;
  esac
  shift
done

_SVC_NAME=$1

if [ "${_PLATFORM}" != "" ]; then

    BUILDER_NAME=opsbox-builder
    if ! $(docker buildx ls |grep -q ${BUILDER_NAME}); then
    docker buildx create --name ${BUILDER_NAME}
    fi

    docker buildx use ${BUILDER_NAME}
    docker buildx inspect --bootstrap

fi


function docker_buildx_svc() {
  _image=$(docker-compose -f ${_COMPOSE_FILE} config |yq ".services|to_entries|.[]| select(.key==\"${_SVC_NAME}\")|.value.image")
  
  if [ "${_image}" == "" ]; then
    echo "--//ERR: image is empty"
    exit 1;
  fi

  _context=$(docker-compose -f ${_COMPOSE_FILE} config |yq ".services|to_entries|.[]| select(.key==\"${_SVC_NAME}\")|.value.build.context")

  _build_args=$(docker-compose -f ${_COMPOSE_FILE} config |yq ".services|to_entries|.[]| select(.key==\"${_SVC_NAME}\")|.value.build.args")
  _build_target=$(docker-compose -f ${_COMPOSE_FILE} config |yq ".services|to_entries|.[]| select(.key==\"${_SVC_NAME}\")|.value.build.target")
  IFS=$'\n'
  _buildx_build_args=
  if [ "x${_build_args}" != "xnull" ]; then
    for _build_arg in ${_build_args}
    do
      _arg_str=$(echo ${_build_arg}|sed -e 's/: /=/')
      _buildx_build_args="${_buildx_build_args} --build-arg ${_arg_str}"
    done
  fi

  if [ "x${_build_target}" != "xnull" ]; then
    _buildx_build_args="--target ${_build_target}"
  fi

  IFS=' ' read -ra _buildx_build_args_arr <<< "$_buildx_build_args"

  if [ "$_OUTPUT" == "registry" ];then
    docker buildx build ${_PLATFORM} -t ${_image} ${_context} --pull --progress=plain ${_buildx_build_args_arr[@]} ${_build_opts} -o type=registry
  elif [ "$_OUTPUT" == "local" ];then
    docker buildx build ${_PLATFORM} -t ${_image} ${_context} --pull --progress=plain ${_buildx_build_args_arr[@]} ${_build_opts} -o type=local,dest=.
  else
    docker buildx build ${_PLATFORM} -t ${_image} ${_context} --pull --progress=plain ${_buildx_build_args_arr[@]} ${_build_opts} -o type=docker
  fi
}

if [ -n "$_SVC_NAME" ]; then
  docker_buildx_svc
  exit 0
else
  for svc in $(docker-compose -f ${_COMPOSE_FILE} config |yq '.services|to_entries|.[]|.key')
  do
    docker_buildx_svc ${svc}
  done
fi
