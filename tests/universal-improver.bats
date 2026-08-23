#!/usr/bin/env bats

bats_require_minimum_version 1.5.0

setup() {
  export TEST_DIR="$(mktemp -d)"
  export REPO_DIR="$TEST_DIR/repo"

  mkdir -p "$REPO_DIR"
  git -C "$REPO_DIR" init -q -b main
  git -C "$REPO_DIR" config user.email "test@example.com"
  git -C "$REPO_DIR" config user.name "Test"
  git -C "$REPO_DIR" config core.autocrlf false
  echo "initial" > "$REPO_DIR/file.txt"
  git -C "$REPO_DIR" add file.txt
  git -C "$REPO_DIR" commit -q -m "initial commit"
  cd "$REPO_DIR" || exit 1

  export UNIVERSAL_IMPROVER="$BATS_TEST_DIRNAME/../universal-improver.sh"
  export FIXTURES_DIR="$BATS_TEST_DIRNAME/fixtures"
  export FINDER="$FIXTURES_DIR/test_finder.sh"
  export FIXER="$FIXTURES_DIR/test_fixer.sh"
  export PASSING_BUILD="$FIXTURES_DIR/test_passing-build-and-test.sh"
}

teardown() {
  rm -rf "$TEST_DIR"
}

@test "fixes a single item and commits with the fixer's message" {
  TEST_FINDER_ITEMS="a" run "$UNIVERSAL_IMPROVER" "$FINDER" "$FIXER" --build-and-test "$PASSING_BUILD"
  [ "$status" -eq 0 ]

  [ "$(git log -1 --format=%s)" = ". t fix a" ]
  grep -q "^fixed-a$" file.txt
}

@test "--count N fixes N items and stops" {
  TEST_FINDER_ITEMS="a b c" run "$UNIVERSAL_IMPROVER" "$FINDER" "$FIXER" --count 2 --build-and-test "$PASSING_BUILD"
  [ "$status" -eq 0 ]

  [ "$(git log --oneline | wc -l)" -eq 3 ]
  grep -q "^fixed-a$" file.txt
  grep -q "^fixed-b$" file.txt
  run ! grep -q "^fixed-c$" file.txt
}

@test "processes items top-to-bottom by default" {
  TEST_FINDER_ITEMS="a b c" run "$UNIVERSAL_IMPROVER" "$FINDER" "$FIXER" --count 1 --build-and-test "$PASSING_BUILD"
  [ "$status" -eq 0 ]

  [ "$(git log -1 --format=%s)" = ". t fix a" ]
  grep -q "^fixed-a$" file.txt
}

@test "fixer failure on an item: skip it, no commit, move to the next item" {
  TEST_FINDER_ITEMS="a b" FAIL_ITEMS="a" run "$UNIVERSAL_IMPROVER" "$FINDER" "$FIXER" --count 2 --build-and-test "$PASSING_BUILD"
  [ "$status" -eq 0 ]

  [ "$(git log --oneline | wc -l)" -eq 2 ]
  run ! grep -q "^fixed-a$" file.txt
  grep -q "^fixed-b$" file.txt
}

@test "build-and-test failure: skip it, no commit, move to the next item" {
  TEST_FINDER_ITEMS="a b" FAIL_PATTERN="fixed-a" run "$UNIVERSAL_IMPROVER" "$FINDER" "$FIXER" --count 2 --build-and-test "$FIXTURES_DIR/test_build-and-test-fails-on-pattern.sh"
  [ "$status" -eq 0 ]

  [ "$(git log --oneline | wc -l)" -eq 2 ]
  run ! grep -q "^fixed-a$" file.txt
  grep -q "^fixed-b$" file.txt
}

@test "build-and-test failure leaves a clean working tree (fully reverted)" {
  TEST_FINDER_ITEMS="a" FAIL_PATTERN="fixed-a" run "$UNIVERSAL_IMPROVER" "$FINDER" "$FIXER" --count 1 --build-and-test "$FIXTURES_DIR/test_build-and-test-fails-on-pattern.sh"
  [ "$status" -eq 0 ]

  [ -z "$(git status --porcelain)" ]
}

@test "finder failure is fatal" {
  run "$UNIVERSAL_IMPROVER" "$FIXTURES_DIR/test_failing-finder.sh" "$FIXER" --build-and-test "$PASSING_BUILD"
  [ "$status" -ne 0 ]

  [ "$(git log --oneline | wc -l)" -eq 1 ]
}

@test "--random processes every item, just not guaranteed top-to-bottom" {
  TEST_FINDER_ITEMS="a b c d e" run "$UNIVERSAL_IMPROVER" "$FINDER" "$FIXER" --count 5 --random --build-and-test "$PASSING_BUILD"
  [ "$status" -eq 0 ]

  [ "$(git log --oneline | wc -l)" -eq 6 ]
  for item in a b c d e; do
    grep -q "^fixed-$item$" file.txt
  done
}

@test "--parallel fixes independent items concurrently and commits both" {
  TEST_FINDER_ITEMS="a b" run "$UNIVERSAL_IMPROVER" "$FINDER" "$FIXTURES_DIR/test_independent-fixer.sh" --count 2 --parallel 2 --build-and-test "$PASSING_BUILD"
  [ "$status" -eq 0 ]

  [ "$(git log --oneline | wc -l)" -eq 3 ]
  grep -q "^fixed-a$" file-a.txt
  grep -q "^fixed-b$" file-b.txt
}

@test "--parallel discards a fix that conflicts on merge, keeps the other" {
  TEST_FINDER_ITEMS="a b" run "$UNIVERSAL_IMPROVER" "$FINDER" "$FIXTURES_DIR/test_conflicting-fixer.sh" --count 2 --parallel 2 --build-and-test "$PASSING_BUILD"
  [ "$status" -eq 0 ]

  [ "$(git log --oneline | wc -l)" -eq 2 ]
  [ -z "$(git status --porcelain)" ]

  if grep -q "^fixed-by-a$" file.txt; then
    run ! grep -q "^fixed-by-b$" file.txt
  else
    grep -q "^fixed-by-b$" file.txt
  fi
}
