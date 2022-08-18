#!/bin/sh
#$env:DOCKER_BUILDKIT=1
#-----------------------------------------------------------------------------------------
# CI/CD Shell Script
# Decription: The purpose of this script is assit in bootstrapping the CICD needs and 
# create a layer of abstraction so the user doesn't need to remember all commands. It also
# allows the user to run both locally and remotely. A user should be able to run a too at
# any time.
#-----------------------------------------------------------------------------------------
# DELETE
#-----------------------------------------------------------------------------------------
# Globals and init
# Description: Global variables.
#-----------------------------------------------------------------------------------------
# Supported Container Builders
readonly CONTAINER_BUILDER_DOCKER="docker"
readonly CONTAINER_BUILDER_BUILDKIT="buildkit"
# Defaults
readonly DEFAULT_CONTAINER_REGISTRY="ghcr.io"
readonly DEFAULT_CONTAINER_REGISTRY_REPO="nick-zuchlewski"
readonly DEFAULT_GOLANG_BASE_IMAGE="golang:1.19.0-bullseye"
readonly DEFAULT_PROTOBUF_IMAGE_NAME="auredia-protobuf"
readonly DEFAULT_PROTOBUF_IMAGE_VERSION="v1.0.0" # TODO: This needs to be auto
# Globals
CONTAINER_REGISTRY=$DEFAULT_CONTAINER_REGISTRY
CONTAINER_REGISTRY_REPO=$DEFAULT_CONTAINER_REGISTRY_REPO
CONTAINER_BUILDER=$CONTAINER_BUILDER_BUILDKIT
GOLANG_BASE_IMAGE=$DEFAULT_GOLANG_BASE_IMAGE
SHA=""
SHORT_SHA=""
OS_INFO=""
DOCKER_VERSION=""
GOLANG_VERSION=""
PROTOBUF_IMAGE_NAME=$DEFAULT_PROTOBUF_IMAGE_NAME
PROTOBUF_IMAGE_VERSION=$DEFAULT_PROTOBUF_IMAGE_VERSION
PROTOBUF_IMAGE_FULL=""

init()
{
    # Check if local or action...
    # This is janky but it does the job
    ACTION=true
    if [ -z "${GITHUB_RUN_NUMBER}" ]; #Check for env
    then 
        ACTION=false
    fi
    # set based on build enviroment
    if [ $ACTION = true ]
    then # Action
        SHA=${GITHUB_SHA}
        SHORT_SHA=$(git rev-parse --short=4 ${GITHUB_SHA})
    else # Local
        SHA=$(git log -1 --format=%H)
        SHORT_SHA=$(git log -1 --pretty=format:%h)
    fi
    # set the ncs image name 
    # the tag always reflects the SDK revision
    PROTOBUF_IMAGE_FULL="$PROTOBUF_IMAGE_NAME:$PROTOBUF_IMAGE_VERSION"
    # check if there is a registry
    if [ ! -z "$CONTAINER_REGISTRY" ]; 
    then
        PROTOBUF_IMAGE_FULL="$CONTAINER_REGISTRY/$CONTAINER_REGISTRY_REPO/$PROTOBUF_IMAGE_FULL"
    fi
    # Get the versions of required tools and enviroment
    # Note: Some of these maybe should be pulled from the dockerfile instead of the host
    # or have seperate variables.
    OS_INFO=$(uname -a)
    DOCKER_VERSION=$(docker --version 2>/dev/null | cut -d " " -f 3 | cut -d "," -f 1)
    GO_VERSION=$(go version 2>/dev/null | cut -d " " -f 3 )
}

#-----------------------------------------------------------------------------------------
# about
# Description: Use to exit on failed code.
#-----------------------------------------------------------------------------------------
about()
{
    # log
    echo "[Git]"
    echo "SHA: $SHA"
    echo "SHORT_SHA: $SHORT_SHA"
    echo "IN_ACTION: $ACTION"
    echo ""
    echo "[Enviroment]" 
    echo "OS_INFO: $OS_INFO"
    echo "DOCKER_VERSION: $DOCKER_VERSION"
    echo "GO_VERSION: $GO_VERSION"
    echo ""
    echo "[Container]"
    echo "CONTAINER_REGISTRY: $CONTAINER_REGISTRY"
    echo "CONTAINER_REGISTRY_REPO: $CONTAINER_REGISTRY_REPO"
    echo "CONTAINER_BUILDER: $CONTAINER_BUILDER"
    echo "PROTOBUF_IMAGE_NAME: $PROTOBUF_IMAGE_NAME"
    echo "PROTOBUF_IMAGE_VERSION $PROTOBUF_IMAGE_VERSION"
    echo "PROTOBUF_IMAGE_FULL: $PROTOBUF_IMAGE_FULL"
    echo ""
}

#-----------------------------------------------------------------------------------------
# usage
# Description: Provides the usages of the shell.
#-----------------------------------------------------------------------------------------
usage() 
{
    echo "##############################################################################" 
    echo "Usage" 
    echo "-h for help"
    echo "-a for About - Logs meta info std out"
    echo "-x for Build - Builds the image"
    echo "-l for lint - Will lint the proto file(s)"    
    echo "-z for Login - Log into container registry"
    echo "-g for Pull - Pull image"
    echo "-r for Push - Push image"
    echo "-g for Golang - Generates Golang"
    echo "-d for Dart - Generates Dart"
    echo "-c for Clean - Removes the images and any dangling images"
    echo "##############################################################################" 
}

#-----------------------------------------------------------------------------------------
# status_check
# Description: Use to exit on failed code.
# Yes...I know about set -e. I just perfer to have more control.
# Usage: status_check $?
#-----------------------------------------------------------------------------------------
status_check()
{
    if [ $1 -ne 0 ]
    then
    echo "Terminating"
    exit 1
    fi
}

# -----------------------------------------------------------------------------------------
# build
# Description: Calls the build dockerfile
# TODO: --platform linux/amd64,linux/arm64,linux/arm/v7
# -----------------------------------------------------------------------------------------
build() 
{
    echo "Prepped for: $PROTOBUF_IMAGE_FULL"
    # build
    case $CONTAINER_BUILDER in
        "$CONTAINER_BUILDER_BUILDKIT" ) # For Buildkit
            echo "Using Buildkit"
            docker buildx build . -f ./docker/Dockerfile.protobuf -t $PROTOBUF_IMAGE_FULL \
                --progress=plain \
                --build-arg GIT_COMMIT="$SHORT_SHA" \
                --build-arg VERSION="$PROTOBUF_IMAGE_VERSION" \
            ;;
        "$CONTAINER_BUILDER_DOCKER" ) # For Docker
            echo "Using Docker"
            docker build . -f ./docker/Dockerfile.protobuf -t $PROTOBUF_IMAGE_FULL \
                --build-arg GIT_COMMIT="$SHORT_SHA" \
                --build-arg VERSION="$PROTOBUF_IMAGE_VERSION" \
            ;;
        * )
            echo "No Container builder is set or not supported"
            status_check 2 
            ;;
    esac
    status_check $?
    echo "" 
}

# -----------------------------------------------------------------------------------------
# login
# Description: Currently only login to GHR.
# https://docs.github.com/en/authentication/keeping-your-account-and-data-secure/creating-a-personal-access-token
# https://docs.github.com/en/packages/working-with-a-github-packages-registry/working-with-the-container-registry
# https://docs.docker.com/engine/reference/commandline/login/
# ------------------------------------------------------------------------------------
login()
{
    echo "Docker Login"
    if [ $ACTION = true ]
    then # Action
        # TODO check if this will even work...lol
        echo "${secrets.GITHUB_TOKEN}" | docker login -u ${github.repository_owner} ghcr.io --password-stdin
        status_check $?
    else # Local
        echo $CR_PAT | docker login ghcr.io -u USERNAME --password-stdin 
    fi
    status_check $?
    echo ""
}

#-----------------------------------------------------------------------------------------
# push
# Description: Will push the images to a registry
#-----------------------------------------------------------------------------------------
push()
{
    echo "Pushing image"
    # Push the image to the registry
    docker push $PROTOBUF_IMAGE_FULL
    status_check $?
    echo ""
}

#-----------------------------------------------------------------------------------------
# push
# Description: Will push the images to a registry
#-----------------------------------------------------------------------------------------
pull()
{
    echo "Pulling image"
    # Push the image to the registry
    docker pull $PROTOBUF_IMAGE_FULL
    status_check $?
    echo ""
}

#-----------------------------------------------------------------------------------------
# lint
# Description: Will generate the artifacts from the image
# Official: https://grpc.io/docs/languages/go/basics/
#-----------------------------------------------------------------------------------------
lint()
{
    echo "linting proto file(s)"

    # build
    docker run --rm \
        -v $(pwd)/protos:/protos \
        -exec $PROTOBUF_IMAGE_FULL bash -c \
        "protoc --version \
        && protoc --lint_out=. protos/*.proto"
    status_check $?

    echo ""
}


#-----------------------------------------------------------------------------------------
# golang
# Description: Will generate the artifacts from the image
# Official: https://grpc.io/docs/languages/go/basics/
#-----------------------------------------------------------------------------------------
golang()
{
    echo "Generating Golang from container"

    # clean the dir
    mkdir -p $(pwd)/src/golang/pb/
    rm -f $(pwd)/src/golang/pb/*
    status_check $?

    # build
    docker run --rm \
        -v $(pwd)/protos:/protos \
        -v $(pwd)/src/golang:/src/golang \
        -exec $PROTOBUF_IMAGE_FULL bash -c \
        "protoc --version \
        && protoc -I=/protos \
        --go_out=./src/golang/pb --go_opt=paths=source_relative \
        --go-grpc_out=./src/golang/pb --go-grpc_opt=paths=source_relative \
        /protos/helloworld.proto"
    status_check $?

    # Go module
    docker run --rm \
        -v $(pwd)/src/golang:/src/golang \
        -exec $PROTOBUF_IMAGE_FULL bash -c \
        "cd /src/golang ; go mod tidy &&  go mod vendor"
    status_check $?

    echo ""
}

#-----------------------------------------------------------------------------------------
# dart
# Description: Will generate the artifacts from the image
# Official: https://grpc.io/docs/languages/dart/quickstart/
#-----------------------------------------------------------------------------------------
dart()
{
    echo "Generating Dart from container"

    # clean the dir
    mkdir -p $(pwd)/src/dart/lib
    rm -f $(pwd)/src/dart/lib/*
    status_check $?

    # build
    docker run --rm \
        -v $(pwd)/protos:/protos \
        -v $(pwd)/src/dart:/src/dart \
        -exec $PROTOBUF_IMAGE_FULL bash -c \
        "protoc --version \
        && protoc -I=protos protos/helloworld.proto \
        --dart_out=grpc:/src/dart/lib/ "
    status_check $?

    # pub get 
    docker run --rm \
        -v $(pwd)/src/dart:/src/dart \
        -exec $PROTOBUF_IMAGE_FULL bash -c \
        "cd /src/dart ; dart pub get"
    status_check $?

    echo ""
}

#-----------------------------------------------------------------------------------------
# clean
# Description: Remove dangling images.
# REVIEW: https://docs.docker.com/config/pruning/
#-----------------------------------------------------------------------------------------
clean()
{
    # TODO: remove old files

    # Remove dangling images
    # This might a little risky since it will delete ALL dangling images
    # but you shouldn't have x number of <none>...
    echo "Performing cleanup"
    yes | docker builder prune # https://docs.docker.com/engine/reference/commandline/image_prune/
    yes | docker image prune # https://docs.docker.com/engine/reference/commandline/image_prune/
    yes | docker rmi -f $(docker images -f "dangling=true" -q)
    echo ""
}

#-----------------------------------------------------------------------------------------
# Entry Point
#-----------------------------------------------------------------------------------------

# init
init

# Parse arguements and run
while getopts ":hacxlprgd" options; do
    case $options in
        h ) usage ;;        # usage (help)
        a ) about ;;        # about
        c ) clean ;;        # clean
        x ) build ;;        # builds the image
        l ) lint ;;         # lint the proto
        z ) login ;;        # login into registry
        p ) push ;;         # pull image
        r ) pull ;;         # push image
        g ) golang ;;       # generates Golang
        d ) dart ;;         # generates Dart
        * ) usage ;;        # default (help)
    esac
done
