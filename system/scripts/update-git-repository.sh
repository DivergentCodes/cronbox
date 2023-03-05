#!/bin/bash


remote_path="/srv/git"
local_path="$HOME/git"

if [[ ! -d $local_path ]]; then
  echo -e "Creating local repo path $local_path\n"
  mkdir -p "$local_path"
fi


# Clone each repo if it doesn't exist.
for remote_repo in $(ls $remote_path); do

  # Strip the extension for local cloning.
  local_repo="$(echo $remote_repo | sed 's/.git$//g')"

  if [[ ! -f "$local_path/$local_repo" ]]; then
    echo -e "\nCloning $remote_repo to $local_path/$local_repo\n"
    git clone "file://$remote_path/$remote_repo" "$local_path/$local_repo";
  fi

done


# Pull the latest commit for each repo, and check for changes.
for local_repo in $(ls $local_path); do

  repo_path="$local_path/$local_repo"
  cd "$repo_path"

  commit_before="$(git rev-parse HEAD)"
  echo -e "\nPulling $repo_path"
  git pull origin main
  commit_after="$(git rev-parse HEAD)"

  if [[ "$commit_before" != "$commit_after" ]]; then
    echo -e "\nGIT REPO CHANGED: $repo_path"
  fi

done
