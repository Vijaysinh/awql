#!/usr/bin/env bash

# Load configuration file if is not already loaded
if [[ -z "${AWQL_ROOT_DIR}" ]]; then
    declare -r AWQL_CUR_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    source "${AWQL_CUR_DIR}/../conf/awql.sh"
fi

# > Packages
source "${AWQL_INC_DIR}/request.sh"
source "${AWQL_INC_DIR}/response.sh"

# > Statements
source "${AWQL_STATEMENT_DIR}/create.sh"
source "${AWQL_STATEMENT_DIR}/desc.sh"
source "${AWQL_STATEMENT_DIR}/select.sh"
source "${AWQL_STATEMENT_DIR}/show.sh"

##
# Get data from cache if available
# @param string $1 FilePath
# @param string $2 Caching enabled
# @return string
# @returnStatus 1 If data is not cached
function __getDataFromCache ()
{
    local file="$1"
    declare -i cache="$2"

    if [[ ${cache} -eq 0 ]]; then
        return 2
    elif [[ -z "$file" || ! -f "$file" ]]; then
        return 1
    fi

    echo "(["${AWQL_RESPONSE_FILE}"]=\"${file}\" ["${AWQL_RESPONSE_CACHED}"]=${cache})"
}

##
# Fetch internal cache or send request to Adwords to get results
# @param arrayToString $1 User request
# @param string
# @returnStatus 2 If query is invalid
# @returnStatus 1 If case of fatal error
function __getData ()
{
    local request="$1"
    if [[ -z "$request" || "$request" != "("*")" ]]; then
        return 1
    fi
    declare -A get="$request"

    # Overload caching mode for local database AWQL methods
    declare -i cache="${get["${AWQL_REQUEST_CACHED}"]}"
    if [[ "${get["${AWQL_REQUEST_TYPE}"]}" != ${AWQL_QUERY_SELECT} ]]; then
        cache=1
    fi
    local response
    local file="${AWQL_WRK_DIR}/${get["${AWQL_REQUEST_CHECKSUM}"]}${AWQL_FILE_EXT}"

    # Try to get date from cache
    response=$(__getDataFromCache "$file" ${cache})
    if [[ $? -eq 0 ]]; then
         echo "$response"
         return 0
    fi

    # Get data from Adwords to local database
    case "${get["${AWQL_REQUEST_TYPE}"]}" in
        ${AWQL_QUERY_CREATE})
            awqlCreate "$request"
            ;;
        ${AWQL_QUERY_DESC})
            awqlDesc "$request" "$file"
            ;;
        ${AWQL_QUERY_SELECT})
            awqlSelect "$request" "$file"
            ;;
        ${AWQL_QUERY_SHOW})
            awqlShow "$request" "$file"
            ;;
        *)
            echo "${AWQL_QUERY_ERROR_UNKNOWN_METHOD}"
            return 2
            ;;
    esac
}

##
# Build a call to Google Adwords and retrieve report for the AWQL query
# @param string $1 Query
# @param string $2 Api version
# @param string $3 Adwords ID
# @param string $4 Google Access Token
# @param string $5 Google Developer Token
# @param int $6 Caching mode
# @param int $7 Verbose
# @param int $8 Raw CSV mode
# @param string
# @returnStatus 1 If query is invalid
function awql ()
{
    local query="$1"
    local apiVersion="$2"
    if [[ ! "$apiVersion" =~ ${AWQL_API_VERSION_REGEX} ]]; then
        echo "${AWQL_INTERNAL_ERROR_API_VERSION}"
        return 1
    fi
    local adwordsId="$3"
    local accessToken="$4"
    local developerToken="$5"
    declare -i cache="$6"
    declare -i verbose="$7"
    declare -i raw="$8"

    # Prepare and validate query, manage all extended behaviors to AWQL basics
    local request
    request=$(awqlRequest "$adwordsId" "$query" "$apiVersion" ${cache} ${verbose} ${raw} "$accessToken" "$developerToken")
    if [[ $? -ne 0 ]]; then
        echo "$request"
        if [[ $? -eq 1 ]]; then
            exit 1
        else
            return 1
        fi
    fi

    # Send request to Adwords or local database to get report
    local response
    response=$(__getData "$request")
    if [[ $? -ne 0 ]]; then
        echo "$response"
        if [[ $? -eq 1 ]]; then
            exit 1
        else
            return 1
        fi
    fi

    awqlResponse "$request" "$response"
}