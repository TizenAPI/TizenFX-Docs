#!/bin/bash -e
SCRIPT_DIR=$(dirname $(readlink -f $0))

VERSIONS="API4 API5 API6 API7 API8 API9 API10 API11 API12 API13 API14"
BRANCH_API14=main
STABLE="API12"

GIT_URL="https://github.com/Samsung/TizenFX.git"
REPO_DIR="$SCRIPT_DIR/repos"
OBJ_DIR="$SCRIPT_DIR/obj"
SITE_DIR="$SCRIPT_DIR/_site"

if [ -z "$DOCFX_FILE" ]; then
  DOCFX_FILE=$SCRIPT_DIR/docfx.json
fi
COMMIT_HASH_FILE=$REPO_DIR/commits

branchname() {
  local version=$1
  local branchvar="BRANCH_$version"
  local branch=${!branchvar}
  if [ -z "$branch" ]; then
    echo $version
  else
    echo $branch
  fi
}

pushd() {
  command pushd "$@" > /dev/null
}

popd() {
  command popd "$@" > /dev/null
}

clone_repos() {
  local target_v=$1
  if [ ! -d $REPO_DIR ]; then
    mkdir -p $REPO_DIR
  fi

  rm -f $COMMIT_HASH_FILE

  local targets=$VERSIONS
  if [ ! -z "$target_v" ]; then
    targets="$target_v"
  fi

  for v in $targets; do
    if [ "$v" == "internals" ]; then
      continue
    fi
    echo "Retrieving $v ..."
    local branch=$(branchname $v)
    if [ -d "$REPO_DIR/$v/.git" ]; then
      pushd $REPO_DIR/$v
      git fetch origin
      git reset --hard origin/$branch
      ## resolve dependency
      echo "Replace csproj file..."
      rm -rf $REPO_DIR/$v/src/Tizen.NUI.Design
      rm -rf $REPO_DIR/$v/src/Tizen.NUI.Components.Design
      rm -rf $REPO_DIR/$v/src/Tizen.NUI.XamlBuild
      rm $REPO_DIR/$v/src/Tizen.NUI/Tizen.NUI.csproj
      cp ../../csproj/Tizen.NUI-$v.csproj $REPO_DIR/$v/src/Tizen.NUI/Tizen.NUI.csproj
      popd
    else
      pushd $REPO_DIR
      git clone $GIT_URL --branch $branch --single-branch --depth 1 $v
      ## resolve dependency
      echo "Replace csproj file..."
      rm -rf $REPO_DIR/$v/src/Tizen.NUI.Design
      rm -rf $REPO_DIR/$v/src/Tizen.NUI.Components.Design
      rm -rf $REPO_DIR/$v/src/Tizen.NUI.XamlBuild
      rm $REPO_DIR/$v/src/Tizen.NUI/Tizen.NUI.csproj
      cp ../csproj/Tizen.NUI-$v.csproj $REPO_DIR/$v/src/Tizen.NUI/Tizen.NUI.csproj
      popd
    fi

    commit=$(git --git-dir=$REPO_DIR/$v/.git rev-parse HEAD)
    echo "$v:$commit" >> $COMMIT_HASH_FILE
  done
}

TEMP_SLN_NAME="_tizenfx_public"
TEMP_SLN_FILE="$TEMP_SLN_NAME.sln"

restore_repos() {
  local target_v=$1
  local targets=$VERSIONS
  if [ ! -z "$target_v" ]; then
    targets="$target_v"
  fi

  for v in $targets; do
    if [ "$v" == "internals" ]; then
      continue
    fi
    echo "Restoring $v ..."
    if [ -d "$REPO_DIR/$v" ]; then
      pushd $REPO_DIR/$v
      if [ ! -f $TEMP_SLN_FILE ]; then
        dotnet new sln -n $TEMP_SLN_NAME -f sln
        ls
        dotnet sln $TEMP_SLN_FILE add src/**/*.csproj
        if [ -d internals/src ]; then
          dotnet sln $TEMP_SLN_FILE add internals/src/**/*.csproj
        fi
      fi
      dotnet restore $TEMP_SLN_FILE
      popd
    else
      echo "No repository to restore : [$v]"
      exit 1
    fi
  done
}

build_docs() {
  local target_v=$1
  echo "Use $DOCFX_FILE"
  
  local DOCFX_EXE=docfx
  if [ -f "$HOME/.dotnet/tools/docfx" ]; then
    DOCFX_EXE="$HOME/.dotnet/tools/docfx"
  fi

  # 1. Generate Metadata for ALL versions (usually memory-safe)
  echo "Generating metadata for all versions..."
  if [ ! -z "$target_v" ]; then
      # If target_v is specified, we only have one repo.
      # But to resolve xrefs, we'd need others. 
      # For now, if we are in a matrix-like environment, we just build what we have.
      local count=$(jq '.metadata | length' $DOCFX_FILE)
      for ((i=0; i<$count; i++)); do
          local api_dest=$(jq -r ".metadata[$i].dest" $DOCFX_FILE)
          local v=$(echo $api_dest | cut -d'/' -f2)
          if [ "$v" == "$target_v" ]; then
              jq ".metadata = [.metadata[$i]]" $DOCFX_FILE > docfx_metadata_temp.json
              $DOCFX_EXE metadata docfx_metadata_temp.json
              rm -f docfx_metadata_temp.json
              break
          fi
      done
  else
      # Build all metadata
      $DOCFX_EXE metadata $DOCFX_FILE
  fi

  # 2. Build Documentation (Sequential)
  local count=$(jq '.metadata | length' $DOCFX_FILE)
  
  # If we have all repos, we can build everything.
  # If we only have one (due to matrix), we only build one.
  
  for ((i=0; i<$count; i++)); do
    local api_dest=$(jq -r ".metadata[$i].dest" $DOCFX_FILE)
    local v=$(echo $api_dest | cut -d'/' -f2) # APIx or internals
    
    if [ ! -z "$target_v" ] && [ "$v" != "$target_v" ]; then
      continue
    fi
    
    echo "[$((i+1))/$count] Building documentation for $v ..."
    
    # Render version-specific content AND root files
    # We include ALL metadata to allow xref resolution
    jq ".build.force = true |
        .build.content = ([.build.content[] | select(.version == \"$v\" or .version == null)] | unique) | 
        .build.overwrite = ([.build.overwrite[] | select(.version == \"$v\")] | unique) |
        .build.dest = \"$SITE_DIR\"" $DOCFX_FILE > docfx_build_temp.json
    
    $DOCFX_EXE build docfx_build_temp.json || echo "Warning: build failed for $v, ignoring..."
    
    # Preserve the search index for this version
    if [ -f "$SITE_DIR/index.json" ]; then
       mv "$SITE_DIR/index.json" "$SITE_DIR/index-$v.json"
       echo "Saved index-$v.json"
    fi
  done
  cp -rf $SCRIPT_DIR/images $SITE_DIR/ || true
  cp -rf $SCRIPT_DIR/templates $SITE_DIR/ || true
  rm -f docfx_build_temp.json
}

create_links() {
  echo "Generating symlinks in $SITE_DIR ..."
  cp -f $COMMIT_HASH_FILE $SITE_DIR || true
  cp -rf $SCRIPT_DIR/images $SITE_DIR/ || true
  cp -rf $SCRIPT_DIR/templates $SITE_DIR/ || true

  # generate symlinks
  pushd $SITE_DIR
  rm -fr stable latest devel master
  ln -s $STABLE stable
  ln -s stable latest
  for v in $VERSIONS; do
    local branch=$(branchname $v)
    if [[ $branch != $v ]]; then
      ln -s $v $branch
    fi
  done
  ln -s master devel
  popd
}

build_index() {
  command node --max-old-space-size=4096 $SCRIPT_DIR/build-index2.js
  rm -f $SITE_DIR/index.json
  create_links
}

build_full() {
  clone_repos
  restore_repos
  build_docs
  build_index
}

clean() {
  rm -fr $OBJ_DIR/.cache
  rm -fr $SITE_DIR
}

purge() {
  clean
  rm -fr $OBJ_DIR
  rm -fr $REPO_DIR
}

CMD=$1
PARAM=$2
case "$CMD" in
  clone) clone_repos "$PARAM" ;;
  restore) restore_repos "$PARAM" ;;
  build) build_docs "$PARAM" ;;
  index) build_index ;;
  clean) clean ;;
  purge) purge ;;
  "") build_full ;;
  *) echo "invalid arguments" && exit 1 ;;
esac
