#!/bin/bash
# set -eou pipefail

SCRIPT_ROOT=$(realpath $(dirname "${BASH_SOURCE[0]}"))
SCRIPT_NAME=$(basename "${BASH_SOURCE[0]}")

GITHUB_USER=${GITHUB_USER:-1gtm}
PR_BRANCH=kubevault-repo-refresher # -$(date +%s)
COMMIT_MSG="Update dependencies"

REPO_ROOT=/tmp/kubevault-repo-refresher

KUBEDB_API_REF=${KUBEDB_API_REF:-master}

repo_uptodate() {
    # gomodfiles=(go.mod go.sum vendor/modules.txt)
    gomodfiles=(go.sum vendor/modules.txt)
    changed=($(git diff --name-only))
    changed+=("${gomodfiles[@]}")
    # https://stackoverflow.com/a/28161520
    diff=($(echo ${changed[@]} ${gomodfiles[@]} | tr ' ' '\n' | sort | uniq -u))
    return ${#diff[@]}
}

refresh() {
    echo "refreshing repository: $1"
    rm -rf $REPO_ROOT
    mkdir -p $REPO_ROOT
    pushd $REPO_ROOT
    git clone --no-tags --no-recurse-submodules --depth=1 https://${GITHUB_USER}:${GITHUB_TOKEN}@$1.git
    cd $(ls -b1)
    git checkout -b $PR_BRANCH
    if [ -f go.mod ]; then
        if [ "$1" != "github.com/kubevault/apimachinery" ]; then
            go mod edit \
                -require kubevault.dev/apimachinery@${KUBEDB_API_REF}
            go mod tidy
        fi
        go mod edit \
            -require=kmodules.xyz/client-go@54ead9c6225fd51239935aeedbbb61ec85a3e91f \
            -require=kmodules.xyz/monitoring-agent-api@d00b079c067bbc1a23e898e4fbd10a95f6ca9f0b \
            -require=kmodules.xyz/webhook-runtime@5c602fd5cf06e13243a079a7cbd5dc50b9059b08 \
            -require=kmodules.xyz/resource-metadata@ed8d9b48f9162a40f083d31dc94c994dbcb85fc2 \
            -require=kmodules.xyz/custom-resources@1631fae03a1aa8ea79f1321f133b1255a71e025e \
            -require=kmodules.xyz/objectstore-api@df749235585ee17334acaba77bf7eed7b4e91e26 \
            -require=go.bytebuilders.dev/license-verifier@v0.9.3 \
            -require=go.bytebuilders.dev/license-verifier/kubernetes@v0.9.3 \
            -require=gomodules.xyz/x@v0.0.7 \
            -replace=github.com/satori/go.uuid=github.com/gofrs/uuid@v4.0.0+incompatible \
            -replace=helm.sh/helm/v3=github.com/kubepack/helm/v3@v3.6.1-0.20210518225915-c3e0ce48dd1b \
            -replace=k8s.io/apiserver=github.com/kmodules/apiserver@v0.21.2-0.20210716212718-83e5493ac170
        go mod tidy
        go mod vendor
    fi
    [ -z "$2" ] || (
        echo "$2"
        $2 || true
        # run an extra make fmt because when make gen fails, make fmt is not run
        make fmt || true
    )
    if repo_uptodate; then
        echo "Repository $1 is up-to-date."
    else
        git add --all
        if [[ "$1" == *"stashed"* ]]; then
            git commit -a -s -m "$COMMIT_MSG" -m "/cherry-pick"
        else
            git commit -a -s -m "$COMMIT_MSG"
        fi
        git push -u origin $PR_BRANCH -f
        hub pull-request \
            --labels automerge \
            --message "$COMMIT_MSG" \
            --message "Signed-off-by: $(git config --get user.name) <$(git config --get user.email)>" || true
        # gh pr create \
        #     --base master \
        #     --fill \
        #     --label automerge \
        #     --reviewer tamalsaha
    fi
    popd
}

if [ "$#" -ne 1 ]; then
    echo "Illegal number of parameters"
    echo "Correct usage: $SCRIPT_NAME <path_to_repos_list>"
    exit 1
fi

if [ -x $GITHUB_TOKEN ]; then
    echo "Missing env variable GITHUB_TOKEN"
    exit 1
fi

# ref: https://linuxize.com/post/how-to-read-a-file-line-by-line-in-bash/#using-file-descriptor
while IFS=, read -r -u9 repo cmd; do
    if [ -z "$repo" ]; then
        continue
    fi
    refresh "$repo" "$cmd"
    echo "################################################################################"
done 9<$1
