#!/bin/zsh -eu
#
# Copyright 2022 Google LLC
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#      http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

# Git Rebase (and run) Easy (GREasy)

# Installs Chrome's very handy depot management tools.
# https://dev.chromium.org/developers/how-tos/install-depot-tools
HOME="$(cd;pwd)"
DEPOT_TOOLS="$HOME/depot_tools"
function get_depot_tools() {
  git clone https://chromium.googlesource.com/chromium/tools/depot_tools.git "$DEPOT_TOOLS"
}
if [[ -d "$DEPOT_TOOLS" ]]; then
  export PATH="$PATH:$DEPOT_TOOLS"
fi

function root() {
    git rev-parse --show-toplevel
}

# 'Stash' changes on the current branch using temporary commits. Roughly eq to `git stash`.
function mtmp() {
  MSG=" - $*"
  if [[ -z $1 ]]; then
    MSG=""
  fi
  git commit -m "TMP$MSG - added" --no-verify
  git add --all
  git commit -m "TMP$MSG - modified" --no-verify
}

function is_tmp() {
  git log | grep -v "\(commit\|[A-Za-z]*:\|^$\)" | head -n 1 | sed "s/^ *//" | grep 'TMP - '
}

# Un-does an `mtmp` roughly eq to `git stash pop`.
function unmtmp() {
  cmt="$(is_tmp)"
  if [[ -z $cmt ]]; then
    echo 'No tmps found'; return
  fi
  git reset 'HEAD~'
  git stash
  cmt="$(is_tmp)"
  if [[ -n $cmt ]]; then
    git reset 'HEAD~'
    git add --all
  fi
  git stash pop
}

function fetch_all() {
  for r in $(git remote); do
    git fetch "$r"
  done
}

# Checks out a branch and rebases against the parent branch.
# Optional argument is which branch to checkout (otherwise the current branch will be used).
function p() {
  fetch_all
  if [[ -n $1 ]]; then
    git checkout "$1" || git checkout -b "$1"
    git rebase --onto origin/$1
  else
    git pull --rebase
  fi
}


# Auto completer for P. Can be used with zsh's `compdef _P P`.
function _p() {
  export branches=($(git branch -a --format='%(refname:short)'))
  compadd -l -a -- branches
}

# Just like P, but for all branches and fetches the upstream. Note: Requires depot_tools.
function pa() {
  fetch_all
  from_branch=$(branch)
  for b in $(git branch --no-color | sed "s/^[* ]*//"); do
    echo "Pulling $b"
    git checkout "$b" || git checkout -b "$b"
    git pull --rebase || return 1
  done
  git checkout "$from_branch"
}

# Returns the current branch for short commands like `git push origin $(branch) -f`.
alias branch="git branch --color=never | grep '\*' | sed 's/* \(.*\)$/\1/' | sed 's/(HEAD detached at [^\/]*\///' | sed 's/)//' | head -n 1"
# Shows all git branches (works best with depot_tools).
alias map="(git status 1&> /dev/null 2&>/dev/null && git --no-pager branch -vv) || ls"
alias gcontinue="git rebase --continue || git merge --continue"
alias abort="git rebase --abort || git merge --abort"
alias skip="git rebase --skip"

# Easy cloning
alias -s git='git clone'

# Grep for git for:
alias gg="git grep" # lines
alias gf="git ls-files | grep" # files
alias gt="git ls-tree -r --name-only HEAD | tree --fromfile"
alias gdt="git ls-tree --name-only -r HEAD | sed 's|\/[^\/]*$||' | sort | uniq | tree --fromfile"
alias gl="git log --all --decorate --graph" # git log
alias glo="git log --all --decorate --oneline --graph" # git log
# git log reverse
alias glr="git log --color=always --all --decorate --oneline --graph | tac | sed 's|\\/|\\$\\\\|' | sed 's|\\\\|\\/|' | sed 's|\\$\\/|\\\\|'"
# Takes the output from gg or gl and opens each file in your editor of choice.
# Example: `gg " wat " | ge` will open all files stored in git containing ' wat '.
function ge() {
  files=( $(grep "[/\\\.]" | sed "s/.*-> //" | sed "s/:.*//" | sed "s/ *|.*//" | sort | uniq) )
  $EDITOR "${files[@]}"
}
# List authors
alias ga="git ls-files | while read f; do git blame --line-porcelain \"\$f\" | grep \"^author \" | sed \"s/author //\"; done | sort -f | uniq -ic | sort -n"
alias gb="git blame"
ggb() {
  # from i8ramin - http://getintothis.com/blog/2012/04/02/git-grep-and-blame-bash-function/
  # runs git grep on a pattern, and then uses git blame to who did it
  git grep -E -n $1 | while IFS=: read i j k; do git blame -L $j,$j $i | cat; done
}

# Rename a branch
alias gm="git branch -m"
# Single letter shortenings for extremely common git commands
alias s="git status -sb 2> /dev/null || ls"
alias a="git add"
alias m="git commit -m "
alias d="git diff --diff-algorithm=patience"
alias D="git diff --staged --diff-algorithm=patience"
alias P="git push origin HEAD"

function hub() {
  remote=$(git remote -v | grep origin | tr '\t' ' ' | cut -f2 -d' ' | head -n1)
  xdg-open "$(echo "$remote" | sed "s|git@|http://|" | sed "s/com:/com\\//")"
}

function edit() {
    ROOT="$(root)"
    TAB="$(echo "\t")"
    cd $ROOT
    files=( $(git status --porcelain | grep -o "[^ $TAB]*$" | sed "s|^|$ROOT/|") )
    $EDITOR "${files[@]}"
}

function last() {
    ROOT="$(root)"
    TAB="$(echo "\t")"
    cd $ROOT
    files=( $(git diff HEAD~1 --raw | grep -o "[^ $TAB]*$" | sed "s|^|$ROOT/|") )
    $EDITOR "${files[@]}"
}

function __run() {
  declare -A project_type=( ["package.json"]="npm run" ["cargo.toml"]="cargo" ["Cargo.toml"]="cargo" ["run.sh"]="bash ./run.sh" ["test.sh"]="bash ./test.sh" ["BUILD"]="blaze")

  for config_file manager in ${(kv)project_type}; do
    if [[ -f "./$config_file" ]]; then
      echo "${manager} @ $(pwd)"
      eval "$manager $*"
      exit
    fi
  done
  if [ "$(pwd)" = "/" ]; then
    echo "<Unknown project>" && exit 1
  fi
}
function run() {(
  while true; do
    __run "$@"; cd ".."
  done
)}

alias r="run"
alias t="run test"
alias b="run build"
