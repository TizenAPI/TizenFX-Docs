#!/bin/bash

SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )

# the code to be executed inside of the docker container
function build_inner() {
  TIZENFX_DIR=/tizenfx
  TEMP_SLN_NAME="_tizenfx_public"
  TEMP_SLN_FILE="$TEMP_SLN_NAME.sln"
  DOCFX_FILE="docfx_local.json"

  pushd $TIZENFX_DIR

  git config --global --add safe.directory /tizenfx
  git config --global --add safe.directory /d

  if [ ! -f "$TIZENFX_DIR/$TEMP_SLN_FILE" ] ; then
    dotnet new sln -n "$TEMP_SLN_NAME"
    dotnet sln "$TEMP_SLN_FILE" add src/**/*.csproj
    if [ -d internals/src ]; then
      dotnet sln $TEMP_SLN_FILE add internals/src/**/*.csproj
    fi
  fi
  dotnet restore "$TEMP_SLN_FILE"

  popd

  mkdir -p repos
  ln -s /tizenfx repos/API13

  docfx "$DOCFX_FILE"

  rm repos/API13
  [ ! -L _site/stable ] && ln -s API13 _site/stable
}

if [ -z "$1" ] ; then
  echo "This script builds API reference documentation for the given TizenFX directory."
  echo "ERROR: please specify the TizenFX directory"
  exit 1
elif [ "$1" = "--INNER" ] ; then
  build_inner
  exit $?
elif [ "$1" = "clean" ] ; then
  echo ">  rm -rf _site obj"
  rm -rf "$SCRIPT_DIR/_site" "$SCRIPT_DIR/obj"
  exit $?
elif [ ! -f "$1/src/Tizen.Log/Tizen.Log.sln" ] ; then
  echo "ERROR: the given directory is not a TizenFX repo (does not contain src/Tizen.Log/Tizen.Log.sln)"
  exit 1
fi

docker run --rm -it -v "$SCRIPT_DIR":/d -v "$1":/tizenfx -w /d tizendotnet/tizenfx-build-worker /d/build-local.sh --INNER
echo "Serving the site. Visit http://localhost:8081/stable/api/"
(cd _site; python3 -m http.server 8081)
