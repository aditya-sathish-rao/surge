#!/usr/bin/env bash
# Fail when a pull request changes files outside its declared package boundary.
#
# Usage: check-pr-boundary.sh <branch> [file ...]
#
# Branch mapping:
#   feat/<package>  Packages/<package>/** only (package names match case- and
#                   separator-insensitively, so feat/surge-ingest-proxy maps to
#                   Packages/SurgeIngestProxy)
#   app/*           App/** only
#   widget/*        Widget/** only
#   scaffold/*      exempt, no package boundary
#   anything else   exempt, no package boundary
#
# docs/** fails for every branch.
#
# Files come from the remaining arguments, or from stdin when none are given:
#   git diff --name-only origin/main...HEAD | check-pr-boundary.sh feat/surge-core

set -euo pipefail

if [ "$#" -lt 1 ]; then
  echo "usage: $0 <branch> [file ...]" >&2
  exit 2
fi

branch=$1
shift

files=()
if [ "$#" -gt 0 ]; then
  files=("$@")
else
  while IFS= read -r line || [ -n "$line" ]; do
    if [ -n "$line" ]; then
      files+=("$line")
    fi
  done
fi

failures=0

fail() {
  printf 'boundary: %s\n' "$1" >&2
  failures=$((failures + 1))
}

allowed=
if [ -z "$branch" ]; then
  fail "branch name is empty"
else
  case "$branch" in
    feat/*)
      slug=${branch#feat/}
      if [ -z "$slug" ] || [ "${slug#*/}" != "$slug" ]; then
        fail "branch $branch must be named feat/<package>"
      else
        wanted=$(printf '%s' "$slug" | tr '[:upper:]' '[:lower:]' | sed 's/[-_]//g')
        matches=0
        for dir in Packages/*/; do
          [ -d "$dir" ] || continue
          name=${dir#Packages/}
          name=${name%/}
          normalised=$(printf '%s' "$name" | tr '[:upper:]' '[:lower:]' | sed 's/[-_]//g')
          if [ "$normalised" = "$wanted" ]; then
            allowed="Packages/$name/"
            matches=$((matches + 1))
          fi
        done
        if [ "$matches" -eq 0 ]; then
          fail "branch $branch does not match any package under Packages/"
        elif [ "$matches" -gt 1 ]; then
          fail "branch $branch matches more than one package under Packages/"
        fi
      fi
      ;;
    app/*)
      allowed="App/"
      ;;
    widget/*)
      allowed="Widget/"
      ;;
  esac
fi

if [ "${#files[@]}" -gt 0 ]; then
  for file in "${files[@]}"; do
    case "$file" in
      docs/*)
        fail "docs/ is read-only: $file"
        continue
        ;;
    esac
    if [ -n "$allowed" ]; then
      case "$file" in
        "$allowed"*) ;;
        *) fail "$file is outside $allowed for branch $branch" ;;
      esac
    fi
  done
fi

if [ "$failures" -gt 0 ]; then
  exit 1
fi

printf 'boundary: %s stays inside its declared boundary\n' "$branch"
