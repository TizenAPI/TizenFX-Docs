#!/bin/bash -e
SCRIPT_DIR=$(dirname $(readlink -f $0))

VERSIONS="API4 API5 API6 API7 API8 API9 API10 API11 API12 API13 API14 API15"
BRANCH_API15=main
STABLE="API14"

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
        # --format sln forces classic .sln on SDK >= 9 (which defaults to .slnx);
        # SDK 8 does not have the option but already defaults to .sln
        if ! dotnet new sln -n $TEMP_SLN_NAME --format sln 2>/dev/null; then
          dotnet new sln -n $TEMP_SLN_NAME
        fi
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
  
  local DOCFX_EXE=${DOCFX:-docfx}
  if [ -z "$DOCFX" ] && [ -f "$HOME/.dotnet/tools/docfx" ]; then
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
      # Extract metadata one version at a time, in separate docfx processes.
      #
      # Running a single `docfx metadata` over all 13 metadata entries makes every
      # class's "Derived" list accumulate the same derived types once per tree that
      # was already processed in that same process -- DocFX does not reset its
      # derived-type index between metadata entries. Because the entries in
      # docfx_tizen_docs.json are ordered API15 -> API4, the repeat count comes out
      # as "number of trees processed up to and including this one": API15 gets 1
      # copy, API14 gets 2, ... API4 gets 12.
      #
      # Measured on the published tizen-docs-pages output for
      # Tizen.Applications.ComponentBased.Common.BaseComponent: a 30-sample check of
      # the Derived entries matches that model 30/30, including WidgetComponent
      # capping at 7 because it only exists in API9-API15. Downstream this shows up
      # as 20,122 duplicated entries across 814 published pages.
      local count=$(jq '.metadata | length' $DOCFX_FILE)
      for ((i=0; i<$count; i++)); do
          local api_dest=$(jq -r ".metadata[$i].dest" $DOCFX_FILE)
          local v=$(echo $api_dest | cut -d'/' -f2)
          echo "Generating metadata for $v ..."
          jq ".metadata = [.metadata[$i]]" $DOCFX_FILE > docfx_metadata_temp.json
          $DOCFX_EXE metadata docfx_metadata_temp.json
          rm -f docfx_metadata_temp.json
      done
  fi

  # Regenerate per-version landing pages from the generated metadata so
  # the namespace lists always match the actual API surface.
  generate_landing_pages "$target_v"

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
  # keep the commit hashes with the site so split build/deploy jobs can carry it as an artifact
  cp -f $COMMIT_HASH_FILE $SITE_DIR/ || true
  rm -f docfx_build_temp.json
}

generate_landing_pages() {
  local target_v=$1
  for v in $VERSIONS; do
    if [ ! -z "$target_v" ] && [ "$v" != "$target_v" ]; then
      continue
    fi
    local toc="$OBJ_DIR/$v/api/toc.yml"
    local spec_dir="$SCRIPT_DIR/specs/$v/api"
    if [ ! -f "$toc" ] || [ ! -d "$spec_dir" ]; then
      continue
    fi
    # top-level (column 0) uids in the metadata toc are the namespaces
    local namespaces=$(grep -E '^- uid: ' "$toc" | sed 's/^- uid: //' | sort -f)
    local ns_count=$(echo "$namespaces" | grep -c .)
    if [ "$ns_count" -lt 10 ]; then
      echo "Skip landing page regen for $v: only $ns_count namespaces in metadata"
      continue
    fi
    {
      echo "## TizenFX API Level ${v#API}"
      echo ""
      echo "$namespaces" | sed 's/^/* <xref:/; s/$/>/'
    } > "$spec_dir/index.md"
    echo "Regenerated landing page for $v ($ns_count namespaces)"
  done
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
  ln -s main devel
  popd
}

build_index() {
  command node --max-old-space-size=4096 $SCRIPT_DIR/build-index2.js
  rm -f $SITE_DIR/index.json
  create_links
}

# Guard against silently deploying an empty/broken site:
# every version must have a reasonable number of generated API pages.
verify_site() {
  local failed=0
  for v in $VERSIONS internals; do
    # internals has a small API surface (a handful of projects); API levels are large
    local min=100
    if [ "$v" == "internals" ]; then
      min=10
    fi
    local count=$(find $SITE_DIR/$v/api -name '*.html' 2>/dev/null | wc -l)
    echo "$v: $count generated api pages"
    if [ "$count" -lt $min ]; then
      echo "ERROR: $v looks empty or missing (only $count pages, expected >= $min)"
      failed=1
    fi
    # page counts alone cannot detect category-wide losses (e.g. a filter
    # bug once dropped every class); require a well-known class page too
    if [ "$v" != "internals" ] && [ ! -f "$SITE_DIR/$v/api/Tizen.NUI.BaseComponents.View.html" ]; then
      echo "ERROR: $v is missing landmark class page Tizen.NUI.BaseComponents.View"
      failed=1
    fi
  done
  return $failed
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
  links) create_links ;;
  verify) verify_site ;;
  clean) clean ;;
  purge) purge ;;
  "") build_full ;;
  *) echo "invalid arguments" && exit 1 ;;
esac
