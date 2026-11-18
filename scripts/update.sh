#!/usr/bin/env bash
# Update FCC's release version and wheel hash. DRY_RUN=1 only reports changes.
set -euo pipefail
cd "$(dirname "$0")/.."

file=packages/free-claude-code.nix
cur=$(grep -oP '^\s*version = "\K[^"]+' "$file" | head -1)
url=$(grep -oP '^\s*url = "\K[^"]+' "$file" | head -1)
re='github\.com/([^/]+)/([^/]+)/releases/download/([^$]*)\$\{version\}'

[[ $url =~ $re ]] || { echo "Unrecognized release URL: $url" >&2; exit 1; }
owner=${BASH_REMATCH[1]}
repo=${BASH_REMATCH[2]}
prefix=${BASH_REMATCH[3]}

curl_args=(-fsSL)
if [[ -n ${GH_TOKEN:-} ]]; then
  curl_args+=(-H "Authorization: Bearer $GH_TOKEN")
fi

tag=$(curl "${curl_args[@]}" \
  "https://api.github.com/repos/$owner/$repo/releases/latest" | jq -r .tag_name)
new=${tag#"$prefix"}

if [[ -z $new || $new == null || $new == "$cur" ]]; then
  echo "free-claude-code is up to date ($cur)"
  exit 0
fi

echo "free-claude-code: $cur -> $new"
[[ -n ${DRY_RUN:-} ]] && exit 0

new_url=${url//\$\{version\}/$new}
new_hash=$(nix store prefetch-file --json "$new_url" | jq -r .hash)
URL=$url NEW_HASH=$new_hash perl -0pi -e \
  's|(\Q$ENV{URL}\E.*?hash = ")[^"]+(")|${1}$ENV{NEW_HASH}${2}|s' "$file"
sed -i "s|version = \"$cur\";|version = \"$new\";|" "$file"
