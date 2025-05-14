#!/usr/bin/env bash

set -xEeuo pipefail

function handle_error {
    echo "Error occurred at line $1"
    kill 0 # kill the master shell and all subshells
}

trap 'handle_error $LINENO' ERR

RELEASE_VERSION=${1:?Release version is required}
PREVIOUS_VERSION=${2:-}

echo "Running ${0} from $(pwd)"

SCRIPT_PATH="$(cd -- "$(dirname "$0")" >/dev/null 2>&1 ; pwd -P)"
PACKAGE_NAME='strimzi-kafka-operator'
CP=${CP:-$(which cp)}
SED=${SED:-$(which sed)}
SKOPEO=$(which skopeo)

main() {
    setup_environment
    generate_olm_bundle
    rm -rvf ${WORKDIR}
}

setup_environment() {
    # TODO: use the packaging/install/cluster-operator resources
    BUNDLE_RESOURCES=${SCRIPT_PATH}/../../install/cluster-operator

    # Temporary directory for the tool binaries
    WORKDIR=$(mktemp -d 2>/dev/null || mktemp -d -t 'bundletmpdir')
    tmpbin_dir=${WORKDIR}/bin
    mkdir -p $tmpbin_dir

    export ARCH=$(case $(uname -m) in x86_64) echo -n amd64 ;; aarch64) echo -n arm64 ;; *) echo -n $(uname -m) ;; esac)
    export OS=$(uname | awk '{print tolower($0)}')

    YQ=$(which yq || true)
    MIN_YQ=4.44.3

    # Download `yq` if not present or less than the min version
    if [ -z "${YQ}" ] || [ "$(printf "${MIN_YQ}\n$(yq -V | grep -Eo '[0-9]+\.[0-9]+\.[0-9]+')\n" | sort -V | head -1)" != "${MIN_YQ}" ] ; then
        download_binary https://github.com/mikefarah/yq/releases/download/v${MIN_YQ} yq_${OS}_${ARCH} yq
        YQ=$tmpbin_dir/yq
    fi

    OPERATOR_SDK=$(which operator-sdk || true)

    # Download `operator-sdk` if not present
    if [ -z "${OPERATOR_SDK}" ] ; then
        export OPERATOR_SDK_DL_URL=https://github.com/operator-framework/operator-sdk/releases/download/v1.36.0
        download_binary ${OPERATOR_SDK_DL_URL} operator-sdk_${OS}_${ARCH} operator-sdk
        OPERATOR_SDK=$tmpbin_dir/operator-sdk
    fi
}

get_delegated_roles() {
    role_names="|"

    for file in "${BUNDLE_RESOURCES}"/*; do
        kind=$(${YQ} '.kind' "${file}")

        if [ "${kind}" == "ClusterRoleBinding" ] || [ "${kind}" == "RoleBinding" ] ; then
            purpose=$(${YQ} '.metadata.labels.purpose' "${file}")

            if [ "${purpose}" == "delegation" ] ; then
                refKind=$(${YQ} '.roleRef.kind' "${file}")

                if [ "${refKind}" == "ClusterRole" ] ; then
                    role_names="${role_names}$(${YQ} '.roleRef.name' "${file}")=delegation|"
                fi
            fi
        fi
    done

    echo "${role_names}"
}

generate_olm_bundle() {
    BUNDLE=$(pwd)/bundle

    if [ -d "${BUNDLE}" ] ; then
        rm -rvf ${BUNDLE}
    fi

    MANIFESTS=${BUNDLE}/manifests
    METADATA=${BUNDLE}/metadata

    mkdir -vp ${MANIFESTS} ${METADATA}
    delegated_roles="$(get_delegated_roles)"

    # Change the copied CRD names to the names traditionally used for OperatorHub
    for file in "${BUNDLE_RESOURCES}"/*; do
        name=$(${YQ} '.metadata.name' "${file}")
        kind=$(${YQ} '.kind' "${file}")
        copy=false

        if [ "${kind}" = "CustomResourceDefinition" ] ; then
            kind="crd"
            copy=true
        elif [ "${kind}" = "ConfigMap" ] ; then
            name=$(echo "${name}" | ${SED} 's/-//g')
            kind="configmap"
            copy=true
        elif [ "${kind}" = "ClusterRole" ] ; then
            # Only include cluster roles if they are meant for delegation
            if [[ "${delegated_roles}" == *"|${name}=delegation|"* ]] ; then
                name=$(echo "${name}" | ${SED} 's/-//g')
                kind="clusterrole"
                copy=true
            fi
        fi

        if [ "${copy}" == "true" ] ; then
            dest="${MANIFESTS}/${name}.${kind}.yaml"
            echo "Copy resource $(basename "${file}") -> $(basename "${dest}")"
            ${CP} "${file}" "${dest}"
        fi
    done

    CSV="${MANIFESTS}/strimzi-cluster-operator.v${RELEASE_VERSION}.clusterserviceversion.yaml"
    ${CP} clusterserviceversion.yaml ${CSV}

    IFS='.' read -r version_x version_y _ <<< "${RELEASE_VERSION}"
    local version_channel="strimzi-${version_x}.${version_y}.x"
    ${YQ} '.annotations."operators.operatorframework.io.bundle.channels.v1" = "stable,'${version_channel}'"' annotations.yaml \
      > ${METADATA}/annotations.yaml

    # Update name and version being replaced
    ${YQ} ea -i '.metadata.name = "strimzi-cluster-operator.v'${RELEASE_VERSION}'" | .metadata.name style=""' "${CSV}"
    ${YQ} ea -i '.metadata.annotations."createdAt" = "'"$(date -u +'%Y-%m-%dT%H:%M:%SZ')"'"' "${CSV}"

    #
    # Load alm-examples-metadata annotation value by reading all example
    # meta YAML files (for description) and obtaining the referenced CRD
    # name. Finally, reduce the loaded objects, keyed by CRD name.
    #
    EXAMPLES_META=$(for ex in fragments/alm-examples/*.yaml ; do
        ${YQ} -o=j '. as $meta
          | [load("'${SCRIPT_PATH}'/../" + $meta.source)]
          | flatten
          | .[ $meta.sourceIndex ]
          | {
              $meta.name // .metadata.name: {
                "description": $meta.description
              }
            }' ${ex}
    done | ${YQ} ea -p=j -o=j '. as $item ireduce ({}; . * $item )' -)

    #
    # Load alm-examples annotation value by reading all example meta YAML
    # files to load the referenced CRD. Finally, combine the loaded CRDs
    # into a single array.
    #
    EXAMPLES=$(for ex in fragments/alm-examples/*.yaml ; do
        ${YQ} -o=j '. as $meta
          | [load("'${SCRIPT_PATH}'/../" + $meta.source)]
          | flatten
          | .[ $meta.sourceIndex ]
          | .metadata.name = $meta.name // .metadata.name
          | .' ${ex}
    done | ${YQ} ea -p=j -o=j '[.]' -)

    EXAMPLES_META=${EXAMPLES_META} ${YQ} ea -i '.metadata.annotations."alm-examples-metadata" = strenv(EXAMPLES_META)' "${CSV}"
    EXAMPLES=${EXAMPLES} ${YQ} ea -i '.metadata.annotations."alm-examples" = strenv(EXAMPLES)' "${CSV}"

    ${YQ} ea -i '.spec.icon = [{ "base64data": "'$(base64 icon.svg -w0)'", "mediatype": "image/svg+xml" }]' "${CSV}"
    ${YQ} ea -i '.spec.version = "'${RELEASE_VERSION}'" | .spec.version style=""' "${CSV}"

    if [ -n "${PREVIOUS_VERSION}" ] ; then
        ${YQ} ea -i '.spec.replaces = "strimzi-cluster-operator.v'${PREVIOUS_VERSION}'"' "${CSV}"
    fi

    # Inject the description markdown file
    ${YQ} ea -i '.spec.description = load_str("fragments/spec.description.md")' "${CSV}"

    ${YQ} ea -i 'select(fi==0).spec.install.spec.permissions[0].rules += select(fi==1).rules | select(fi==0)' \
      "${CSV}" "${BUNDLE_RESOURCES}/020-ClusterRole-strimzi-cluster-operator-role.yaml"

    ${YQ} ea -i 'select(fi==0).spec.install.spec.permissions[0].rules += select(fi==1).rules | select(fi==0)' \
      "${CSV}" "${BUNDLE_RESOURCES}/022-ClusterRole-strimzi-cluster-operator-role.yaml"

    ${YQ} ea -i 'select(fi==0).spec.install.spec.permissions[0].rules += select(fi==1).rules | select(fi==0)' \
      "${CSV}" "${BUNDLE_RESOURCES}/023-ClusterRole-strimzi-cluster-operator-role.yaml"

    for file in "${BUNDLE_RESOURCES}"/*-ClusterRole-*.yaml; do
        name=$(${YQ} '.metadata.name' "${file}")
        # Grant the operator the access needed to delegate
        if [[ "${delegated_roles}" == *"|${name}=delegation|"* ]] ; then
            ${YQ} ea -i 'select(fi==0).spec.install.spec.permissions[0].rules += select(fi==1).rules | select(fi==0)' \
              "${CSV}" "${file}"
        fi
    done

    ${YQ} ea -i 'select(fi==0).spec.install.spec.clusterPermissions[0].rules += select(fi==1).rules | select(fi==0)' \
      "${CSV}" "${BUNDLE_RESOURCES}/021-ClusterRole-strimzi-cluster-operator-role.yaml"

    local DEPLOYMENT_INSTANCE="strimzi-cluster-operator-v${RELEASE_VERSION}"
    ${YQ} ea -i '.spec.install.spec.deployments[0].name = "'${DEPLOYMENT_INSTANCE}'"' "${CSV}"
    ${YQ} ea -i 'select(fi==0).spec.install.spec.deployments[0].spec = select(fi==1).spec | select(fi==0)' \
      "${CSV}" "${BUNDLE_RESOURCES}"/060-*

    ${YQ} -i '.spec.install.spec.deployments[0].spec.strategy = { "type": "Recreate" }' "${CSV}"
    ${YQ} -i '.spec.install.spec.deployments[0].spec.template.spec.containers[0].resources = {}' "${CSV}"

    ${YQ} -i '.spec.install.spec.deployments[0].spec.template.spec.containers[0].env |= map(
      select(.name == "STRIMZI_NAMESPACE").valueFrom.fieldRef.fieldPath = "metadata.annotations['"'olm.targetNamespaces'"']"
    ) | .' "${CSV}"

    update_image_references

    echo "Generated manifests in ${MANIFESTS}:"
    ls -l ${MANIFESTS}

    validate_olm_bundle ${BUNDLE}
}

update_image_references() {
    OPERATOR_CONTAINER=".spec.install.spec.deployments[0].spec.template.spec.containers[0]"

    image="$(${YQ} ${OPERATOR_CONTAINER}'.image' "${CSV}")"
    image_final="$(${SKOPEO} inspect --no-tags --tls-verify=false --format "{{ .Name }}@{{ .Digest }}" "docker://${image}")"

    # Add operator image
    ${YQ} -i '.metadata.annotations."containerImage" = "'${image_final}'"' "${CSV}"
    ${YQ} -i '.spec.relatedImages += { "name": "strimzi-cluster-operator", "image": "'${image_final}'" }' "${CSV}"
    ${YQ} -i ${OPERATOR_CONTAINER}'.image = "'${image_final}'"' "${CSV}"
    ${SED} -i.bak "s|${image}|${image_final}|g" "${CSV}";
    rm "${CSV}.bak"

    # Add Kafka images
    KAFKA_IMAGES="$(${YQ} ${OPERATOR_CONTAINER}'.env[] | (select (.name == "STRIMZI_KAFKA_IMAGES")).value' "${CSV}")"
    for img in ${KAFKA_IMAGES}; do
        name="strimzi-kafka-$(echo "${img}" | cut -d'=' -f1 | tr -d '.')"
        image=$(echo "${img}" | cut -d'=' -f2)
        image_final="$(${SKOPEO} inspect --no-tags --tls-verify=false --format "{{ .Name }}@{{ .Digest }}" "docker://${image}")"
        ${YQ} -i '.spec.relatedImages += { "name": "'${name}'", "image": "'${image_final}'" }' "${CSV}"
        ${SED} -i.bak "s|${image}|${image_final}|g" "${CSV}";
        rm "${CSV}.bak"
    done

    # Add auxiliary images
    ENV="*BRIDGE* *KANIKO_EXECUTOR* *MAVEN_BUILDER*"
    for env in $ENV; do
        name="strimzi-$(echo "${env}" | ${SED} 's/*//g' | ${SED} 's/_/-/g' | tr '[:upper:]' '[:lower:]')"
        image=$(${YQ} '.. | select(has("name")).env[] | (select (.name == "'${env}'")).value' "${CSV}")
        image_final="$(${SKOPEO} inspect --no-tags --tls-verify=false --format "{{ .Name }}@{{ .Digest }}" "docker://${image}")"
        ${YQ} -i '.spec.relatedImages += { "name": "'${name}'", "image": "'${image_final}'" }' "${CSV}"
        ${SED} -i.bak "s|${image}|${image_final}|g" "${CSV}";
        rm "${CSV}.bak"
    done
}

validate_olm_bundle() {
    local BUNDLE=${1}
    ${OPERATOR_SDK} bundle validate "${BUNDLE}" --select-optional name=operatorhub
}

main
