#!/bin/bash
# set -eou pipefail

SCRIPT_ROOT=$(realpath $(dirname "${BASH_SOURCE[0]}"))
SCRIPT_NAME=$(basename "${BASH_SOURCE[0]}")

GITHUB_USER=${GITHUB_USER:-1gtm}
PR_BRANCH=kdbdeps # -$(date +%s)
COMMIT_MSG="Update deps"

REPO_ROOT=/tmp/licup22

KUBEDB_API_REF=${KUBEDB_API_REF:-7263b50309d2e37f83f763f0448a4faeac1d5687}

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
    git clone --no-tags --no-recurse-submodules --depth=1 git@github.com:$1.git
    name=$(ls -b1)
    cd $name
    git checkout -b $PR_BRANCH

    if [ -f go.mod ]; then
        go mod edit \
            -require=gomodules.xyz/logs@v0.0.7 \
            -require=kubedb.dev/apimachinery@8e2aab0c176e12bc3c0ff0ee4b732bd7faddd0ed \
            -require=kubedb.dev/db-client-go@6ddd035705ef3af7d835fb93611b92f9a1e729f5 \
            -require=k8s.io/kube-openapi@v0.0.0-20220803162953-67bda5d908f1 \
            -require=kmodules.xyz/client-go@v0.25.32 \
            -require=kmodules.xyz/resource-metadata@v0.17.12 \
            -require=kmodules.xyz/go-containerregistry@v0.0.11 \
            -replace=github.com/Masterminds/sprig/v3=github.com/gomodules/sprig/v3@v3.2.3-0.20220405051441-0a8a99bac1b8 \
            -require=gomodules.xyz/password-generator@v0.2.9 \
            -require=go.bytebuilders.dev/license-verifier@v0.13.2 \
            -require=go.bytebuilders.dev/license-verifier/kubernetes@v0.13.2 \
            -require=go.bytebuilders.dev/audit@v0.0.27 \
            -require=stash.appscode.dev/apimachinery@v0.31.0 \
            -require=github.com/elastic/go-elasticsearch/v7@v7.15.1 \
            -require=go.mongodb.org/mongo-driver@v1.10.2 \
            -replace=sigs.k8s.io/controller-runtime=github.com/kmodules/controller-runtime@ac-0.13.0 \
            -replace=github.com/imdario/mergo=github.com/imdario/mergo@v0.3.6 \
            -replace=k8s.io/apiserver=github.com/kmodules/apiserver@ac-1.25.1 \
            -replace=k8s.io/kubernetes=github.com/kmodules/kubernetes@ac-1.25.1

        # sed -i 's|NewLicenseEnforcer|MustLicenseEnforcer|g' `grep 'NewLicenseEnforcer' -rl *`
        go mod tidy
        go mod vendor
    fi
    [ -z "$2" ] || (
        echo "$2"
        $2 || true
        # run an extra make fmt because when make gen fails, make fmt is not run
        make fmt || true
    )
    make fmt || true
    if repo_uptodate; then
        echo "Repository $1 is up-to-date."
    else
        git add --all
        if [[ "$1" == *"stashed"* ]]; then
            git commit -a -s -m "$COMMIT_MSG" -m "/cherry-pick"
        else
            git commit -a -s -m "$COMMIT_MSG"
        fi
        git push -u origin HEAD -f
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
