#!/usr/bin/env bash
RUN_CODESPACES_TESTS=${1:-false}

if [ ! -f $HOME/.ssh/test.id_rsa ]; then
    mkdir -p $HOME/.ssh
    chmod 700 $HOME/.ssh
    yes | ssh-keygen -q -b 2048 -t rsa -N '' -C "$(whoami)@localhost" -f $HOME/.ssh/test.id_rsa
    cat $HOME/.ssh/test.id_rsa.pub >> $HOME/.ssh/authorized_keys
    chmod 644 $HOME/.ssh/authorized_keys
fi

check_result() {
    local shell_to_test=$1
    local teset_result=$2
    local regex=$3
    if echo "$test_result" | grep -E "$regex" > /dev/null 2>&1; then
        echo " ✔️ $regex passed."
        return 0
    fi
    echo " ❌ $regex failed!"
    return 1
}

run_test() {
    local shell_to_test=$1
    local test_result="$(ssh -q -p 2222 -i $HOME/.ssh/test.id_rsa -o StrictHostKeyChecking=no -o GlobalKnownHostsFile=/dev/null -o UserKnownHostsFile=/dev/null $(whoami)@localhost $shell_to_test -lic 'env' 2> /dev/null)"
    echo -e "\n🧪 Run tests for $1...\n(*) Environment for $shell_to_test:\n$test_result"
    echo "(*) Running environment var tests for $1..."
    check_result "$shell_to_test" "$test_result" "this_var=true"
    check_result "$shell_to_test" "$test_result" "that_var=true"
    if [ "${RUN_CODESPACES_TESTS}" = "true" ]; then
        check_result "$shell_to_test" "$test_result" "CODESPACES=true"
        check_result "$shell_to_test" "$test_result" "RepositoryName=.*"
        check_result "$shell_to_test" "$test_result" "ContainerVersion=.*"
        check_result "$shell_to_test" "$test_result" "GITHUB_TOKEN=.*"
        check_result "$shell_to_test" "$test_result" "GITHUB_CODESPACE_TOKEN=.*"
        check_result "$shell_to_test" "$test_result" "GIT_COMMITTER_NAME=.*"
        check_result "$shell_to_test" "$test_result" "GIT_COMMITTER_EMAIL=.*"
    fi
    echo "(*) Running PATH tests for $1..."
    check_result "$shell_to_test" "$test_result" "PATH=.*/front-dockerfile-pre-script:.*:/back-dockerfile-pre-script.*"
    check_result "$shell_to_test" "$test_result" "PATH=.*/front-dockerfile-post-script:.*:/back-dockerfile-post-script.*"
    check_result "$shell_to_test" "$test_result" "PATH=.*(/front-profile-post-export:|/front-profile-begin:).*(:/back-profile-post-export|:/back-profile-begin).*"
    if [ "$shell_to_test" != "zsh" ]; then
        check_result "$shell_to_test" "$test_result" "PATH=.*/front-profile-pre-rc:.*:/back-profile-pre-rc.*"
        check_result "$shell_to_test" "$test_result" "PATH=.*/front-pre-profile\.d:.*:/back-pre-profile\.d.*"
    fi
    check_result "$shell_to_test" "$test_result" "PATH=.*/front-profile-end:.*:/back-profile-end.*"
    if [ "$shell_to_test" != "sh" ]; then
        check_result "$shell_to_test" "$test_result" "PATH=.*/front-rc:.*"
        check_result "$shell_to_test" "$test_result" "PATH=.*:/back-rc.*"
    fi
    echo "👍 All $1 tests passed! "
}

set -e
run_test sh
run_test bash
run_test zsh

echo -e "\n🏆💯 All shell tests passed!"
