#!/bin/bash
# setup-source.sh must never delete an existing core source checkout because
# it could not read, or did not recognise, the checkout's origin URL. A git
# that refuses the repo ("dubious ownership" on a root-owned checkout) makes
# `git remote get-url origin` fail; that used to read as "Repository URL
# changed" and trigger rm -rf of the whole tree. Runs the real script in a
# temp project against local bare repos. No docker or network needed.
#
# Usage: scripts/bash/tests/test-setup-source-origin.sh
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1 GIT_TERMINAL_PROMPT=0
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t

PASS=0
FAIL=0
check(){ if [ "$2" = "$3" ]; then PASS=$((PASS + 1)); echo "  ok   $1"; else FAIL=$((FAIL + 1)); echo "  FAIL $1 (expected '$3', got '$2')"; fi; }

# make_bare <name>: bare repo $WORK/<name>.git with a Playerbot branch.
make_bare(){
  git init -q -b Playerbot "$WORK/src-$1"
  echo "$1 v1" > "$WORK/src-$1/content.txt"
  git -C "$WORK/src-$1" add content.txt
  git -C "$WORK/src-$1" commit -q -m v1
  git clone -q --bare "$WORK/src-$1" "$WORK/$1.git"
}
# push_commit <name> <text>: new upstream commit on Playerbot.
push_commit(){
  echo "$2" > "$WORK/src-$1/content.txt"
  git -C "$WORK/src-$1" commit -q -am "$2"
  git -C "$WORK/src-$1" push -q "$WORK/$1.git" Playerbot
}
make_bare up
make_bare other

# A git shim that fails `remote get-url` the way git does for a repo owned by
# another user, and passes everything else through.
REAL_GIT="$(command -v git)"
mkdir -p "$WORK/shim"
cat > "$WORK/shim/git" <<EOF
#!/bin/bash
case " \$* " in *" remote get-url "*)
  [ -e "$WORK/root-owned" ] || exec "$REAL_GIT" "\$@"
  echo "fatal: detected dubious ownership in repository at '\$PWD'" >&2
  exit 128;;
esac
exec "$REAL_GIT" "\$@"
EOF
chmod +x "$WORK/shim/git"

PROJECT="$WORK/project"
SRC="$PROJECT/local-storage/source/azerothcore-playerbots"
mkdir -p "$PROJECT"

# run_setup <repo url> [PATH prefix]: run setup-source.sh in the temp project.
run_setup(){
  printf 'STACK_SOURCE_VARIANT=playerbots\nACORE_REPO_PLAYERBOTS=%s\n' "$1" > "$PROJECT/.env"
  (cd "$PROJECT" && PATH="${2:+$2:}$PATH" bash "$REPO_ROOT/scripts/bash/setup-source.sh") > "$WORK/out.log" 2>&1
}

echo "first run clones"
run_setup "$WORK/up.git"
check "exit status" "$?" "0"
check "content" "$(cat "$SRC/content.txt" 2>/dev/null)" "up v1"
touch "$SRC/marker"   # stands in for build output and local files

echo "unreadable origin: fail, keep the tree"
push_commit up "up v2"
touch "$WORK/root-owned"
if run_setup "$WORK/up.git" "$WORK/shim"; then r=no; else r=yes; fi
check "exit status is non-zero" "$r" "yes"
check "tree kept" "$([ -f "$SRC/marker" ] && [ -d "$SRC/.git" ] && echo yes)" "yes"
check "no re-clone message" "$(grep -c 'Repository URL changed' "$WORK/out.log")" "0"
check "explains why" "$(grep -c 'Cannot read the origin' "$WORK/out.log")" "1"

echo "unreadable origin, ownership fixed through docker: retry and update"
# chown fails (shim), so the script falls back to a root container (shim).
cat > "$WORK/shim/chown" <<EOF
#!/bin/bash
exit 1
EOF
cat > "$WORK/shim/docker" <<EOF
#!/bin/bash
echo "docker \$*" >> "$WORK/docker.log"
[ -e "$WORK/docker-fails" ] && exit 1
rm -f "$WORK/root-owned"
EOF
chmod +x "$WORK/shim/chown" "$WORK/shim/docker"
run_setup "$WORK/up.git" "$WORK/shim"
check "exit status" "$?" "0"
check "chowned only the checkout" "$(grep -c -- "-v $SRC:/workspace .* chown -R $(id -u):$(id -g) /workspace" "$WORK/docker.log" 2>/dev/null)" "1"
check "updated" "$(cat "$SRC/content.txt")" "up v2"
check "tree kept" "$([ -f "$SRC/marker" ] && echo yes)" "yes"
push_commit up "up v2b"

echo "ownership can't be fixed: fail, keep the tree"
touch "$WORK/root-owned" "$WORK/docker-fails"
if run_setup "$WORK/up.git" "$WORK/shim"; then r=no; else r=yes; fi
check "exit status is non-zero" "$r" "yes"
check "tree kept" "$([ -f "$SRC/marker" ] && echo yes)" "yes"
check "explains why" "$(grep -c 'Cannot read the origin' "$WORK/out.log")" "1"
rm -f "$WORK/root-owned" "$WORK/docker-fails" "$WORK/shim/chown" "$WORK/shim/docker"

echo "origin differs only by scheme/case/.git/slash: update in place"
run_setup "FILE://$WORK/up.git/"
check "exit status" "$?" "0"
check "updated" "$(cat "$SRC/content.txt")" "up v2b"
check "tree kept" "$([ -f "$SRC/marker" ] && echo yes)" "yes"

echo "origin is a different repo: fail, keep the tree"
if run_setup "$WORK/other.git"; then r=no; else r=yes; fi
check "exit status is non-zero" "$r" "yes"
check "tree kept" "$([ -f "$SRC/marker" ] && echo yes)" "yes"
check "still on the old repo" "$(cat "$SRC/content.txt")" "up v2b"
check "explains why" "$(grep -c 'points at a different repository' "$WORK/out.log")" "1"

echo "same origin: update in place"
push_commit up "up v3"
run_setup "$WORK/up.git"
check "exit status" "$?" "0"
check "updated" "$(cat "$SRC/content.txt")" "up v3"
check "tree kept" "$([ -f "$SRC/marker" ] && echo yes)" "yes"

echo "only file modes changed (e.g. a container chmod-ed the tree): restore them, update"
push_commit up "up v4"
chmod 755 "$SRC/content.txt"
run_setup "$WORK/up.git"
check "exit status" "$?" "0"
check "updated" "$(cat "$SRC/content.txt")" "up v4"
check "mode restored" "$(stat -c %a "$SRC/content.txt")" "644"
check "says so" "$(grep -c 'file-mode changes' "$WORK/out.log")" "1"
check "tree kept" "$([ -f "$SRC/marker" ] && echo yes)" "yes"

echo "real local edit: fail, keep the edit"
push_commit up "up v5"
echo "local edit" > "$SRC/content.txt"
chmod 755 "$SRC/content.txt"
if run_setup "$WORK/up.git"; then r=no; else r=yes; fi
check "exit status is non-zero" "$r" "yes"
check "edit kept" "$(cat "$SRC/content.txt")" "local edit"
check "mode left alone" "$(stat -c %a "$SRC/content.txt")" "755"

echo
echo "passed: $PASS  failed: $FAIL"
[ "$FAIL" -eq 0 ]
