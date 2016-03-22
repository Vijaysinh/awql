#!/usr/bin/env bash

# @includeBy /core/query.sh
# Load configuration file if is not already loaded
if [[ -z "${AWQL_ROOT_DIR}" ]]; then
    declare -r AWQL_CUR_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    source "${AWQL_CUR_DIR}/../../conf/awql.sh"
fi


##
# Get query sort order
# @param string $1 Requested sort order
# @return int 1 for DESC, 0 for ASC
function __queryOrder ()
{
    if [[ "$1" == ${AWQL_QUERY_DESC} ]]; then
        echo "${AWQL_SORT_ORDER_DESC}"
    else
        echo "${AWQL_SORT_ORDER_ASC}"
    fi
}

##
# Return sort order (n for numeric, d for others)
# @param $1 Column data type
# @return string
function __queryOrderType ()
{
    if inArray "$1" "${AWQL_SORT_NUMERICS}"; then
        # Numeric order
        echo "n"
    else
        echo "d"
    fi
}

##
# Parse a AWQL SELECT query to split it by its component
#
# Order: SELECT...FROM...WHERE...DURING...ORDER BY...LIMIT...
#
# @response
# > STATEMENT       : SELECT
# > FIELD_NAMES     : Id Name Status Impressions Clicks Conversions Cost AverageCpc
# > FIELDS          : CampaignId CampaignName CampaignStatus Impressions Clicks Conversions Cost AverageCpc
# > TABLE           : CAMPAIGN_PERFORMANCE_REPORT
# > WHERE           : Impressions > O
# > DURING          :
# > ORDER           : Clicks DESC
# > LIMIT           : 5
# > QUERY           : SELECT Id, Name, Status, Impressions, Clicks FROM CAMPAIGN_PERFORMANCE_REPORT WHERE Impressions > O ORDER BY Clicks DESC;
# > AWQL_QUERY      : SELECT CampaignId, CampaignName, CampaignStatus, Impressions, Clicks FROM CAMPAIGN_PERFORMANCE_REPORT WHERE Impressions > O;
#
# @param string $1 Query
# @param string $2 Api version
# @return arrayToString Query component
# @returnStatus 1 If query is malformed
# @returnStatus 1 If api version is invalid
# @returnStatus 1 If query is empty
function awqlSelectQuery ()
{
    local queryStr="$(trim "$1")"
    if [[ -z "$queryStr" ]]; then
        echo "${AWQL_INTERNAL_ERROR_QUERY}"
        return 1
    fi
    local apiVersion="$2"
    if [[ ! "$apiVersion" =~ ${AWQL_API_VERSION_REGEX} ]]; then
        echo "${AWQL_INTERNAL_ERROR_API_VERSION}"
        return 1
    fi

    # Query components
    declare -i queryLength=${#queryStr}
    declare -A components
    declare -a fieldNames

    # During literal dates
    local duringLiteral="${AWQL_COMPLETE_DURING[@]}"

    # Parse query char by char
    local name="${AWQL_REQUEST_STATEMENT}"
    local char part
    declare -i pos
    for (( pos = 0; pos <= ${queryLength}; ++pos )); do
        # Manage end of query
        if [[ ${pos} -lt ${queryLength} ]]; then
            char="${queryStr:$pos:1}"
            if [[ "$char" == [[:space:]] ]]; then
                char=" "
            fi
        else
            char=" "
        fi
        # Split by components
        case "$name" in
            ${AWQL_REQUEST_STATEMENT})
                if [[ "$char" == " " && -n "$part" ]]; then
                    if [[ "$part" == ${AWQL_QUERY_SELECT} ]]; then
                        components["$name"]="$part"
                        part=""
                        name=${AWQL_REQUEST_FIELDS}
                    else
                        echo "${AWQL_QUERY_ERROR_METHOD}"
                        return 2
                    fi
                elif [[ "$char" != " " ]]; then
                    part+="$char"
                fi
                ;;
            ${AWQL_REQUEST_FIELDS})
                if [[ "$part" == *[[:space:]]*${AWQL_QUERY_FROM} ]]; then
                    # Get rest of fields without from method
                    fieldNames+=("${part%% *}")
                    part=""
                    name=${AWQL_REQUEST_TABLE}
                elif [[ "$char" == "," ]]; then
                    if [[ -n "$part" ]]; then
                        fieldNames+=("$part")
                        part=""
                    fi
                elif [[ -n "$part" || "$char" != " " ]]; then
                    part+="$char"
                fi
                ;;
            ${AWQL_REQUEST_TABLE})
                if [[ "$char" == " " && -n "$part" ]]; then
                    if [[ -z "${components["$name"]}" ]]; then
                        components["$name"]="$part"
                    elif [[ "$part" == ${AWQL_QUERY_WHERE} ]]; then
                        name=${AWQL_REQUEST_WHERE}
                    elif [[ "$part" == ${AWQL_QUERY_DURING} ]]; then
                        name=${AWQL_REQUEST_DURING}
                    elif [[ "$part" == ${AWQL_QUERY_ORDER} ]]; then
                        name=${AWQL_REQUEST_ORDER}
                    elif [[ "$part" == ${AWQL_QUERY_LIMIT} ]]; then
                        name=${AWQL_REQUEST_LIMIT}
                    fi
                    part=""
                elif [[ "$char" != " " ]]; then
                    part+="$char"
                fi
                ;;
            ${AWQL_REQUEST_WHERE})
                 if [[ "$char" == " " && -n "$part" ]]; then
                    if [[ "$part" == ${AWQL_QUERY_DURING} ]]; then
                        name=${AWQL_REQUEST_DURING}
                    elif [[ "$part" == ${AWQL_QUERY_ORDER} ]]; then
                        name=${AWQL_REQUEST_ORDER}
                    elif [[ "$part" == ${AWQL_QUERY_LIMIT} ]]; then
                        name=${AWQL_REQUEST_LIMIT}
                    elif [[ -n "${components["$name"]}" ]]; then
                        components["$name"]+=" $part"
                    else
                        components["$name"]="$part"
                    fi
                    part=""
                elif [[ "$char" != " " ]]; then
                    part+="$char"
                fi
                ;;
            ${AWQL_REQUEST_DURING})
                if ([[ "$char" == " " || "$char" == "," ]]) && [[ -n "$part" ]]; then
                    if [[ "$part" == ${AWQL_QUERY_ORDER} ]]; then
                        name=${AWQL_REQUEST_ORDER}
                    elif [[ "$part" == ${AWQL_QUERY_LIMIT} ]]; then
                        name=${AWQL_REQUEST_LIMIT}
                    elif inArray "$part" "$duringLiteral"; then
                        components["$name"]="$part"
                    elif [[ "$part" =~ ^[[:digit:]]{8}$ ]]; then
                        if [[ -n "${components["$name"]}" ]]; then
                            components["$name"]+=" $part"
                        else
                            components["$name"]="$part"
                        fi
                    else
                        echo "${AWQL_QUERY_ERROR_DURING}"
                        return 2
                    fi
                    part=""
                elif [[ "$char" != " " && "$char" != "," ]]; then
                    part+="$char"
                fi
                ;;
            ${AWQL_REQUEST_ORDER})
                if [[ "$char" == " " && -n "$part" ]]; then
                    if [[ "$part" == ${AWQL_QUERY_LIMIT} ]]; then
                        name=${AWQL_REQUEST_LIMIT}
                    elif [[ ! ${components["$name"]+rv} ]]; then
                        if [[ "$part" != ${AWQL_QUERY_BY} ]]; then
                            echo "QueryError.ORDER_BY"
                            return 2
                        else
                            components["$name"]=""
                        fi
                    else
                        if [[ -n "${components["$name"]}" ]]; then
                            components["$name"]+=" "
                        fi
                        components["$name"]+="$part"
                    fi
                    part=""
                elif [[ "$char" == "," ]]; then
                    # Multiple order by is not supported for the moment
                    echo "${AWQL_QUERY_ERROR_MULTIPLE_ORDER}"
                    return 2
                elif [[ "$char" != " " ]]; then
                    part+="$char"
                fi
                ;;
            ${AWQL_REQUEST_LIMIT})
                if ([[ "$char" == " " || "$char" == "," ]]) && [[ -n "$part" ]]; then
                    if [[ "$part" =~ ^[0-9]+$ ]]; then
                        if [[ -n "${components["$name"]}" ]]; then
                            components["$name"]+=" $part"
                        else
                            components["$name"]="$part"
                        fi
                    else
                        echo "${AWQL_QUERY_ERROR_LIMIT}"
                        return 2
                    fi
                    part=""
                elif [[ "$char" != " " ]]; then
                    part+="$char"
                fi
                ;;
            *)
                echo "${AWQL_INTERNAL_ERROR_QUERY_COMPONENT}"
                return 1
                ;;
        esac
    done

    # Empty query
    declare -i fieldSize="${#fieldNames[@]}"
    if [[ -z "${components["${AWQL_REQUEST_TABLE}"]}" || ${fieldSize} -eq 0 ]]; then
        echo "${AWQL_QUERY_ERROR_SYNTAX}"
        return 2
    fi

    # Check if it is a valid report table or view
    declare -i isView=0
    declare -A -r tables="$(awqlTables "$apiVersion")"
    if [[ "${#tables[@]}" -eq 0 ]]; then
        echo "${AWQL_INTERNAL_ERROR_INVALID_TABLES}"
        return 1
    fi
    local tableNames="${!tables[@]}"
    if ! inArray "${components["${AWQL_REQUEST_TABLE}"]}" "$tableNames"; then
        # Here also check for view
        echo "${AWQL_QUERY_ERROR_TABLE}"
        return 2
    fi

    # Awql fields
    declare -a fields
    for field in "${fieldNames[@]}"; do
        if [[ ${isView} -eq 0 && "$field" == *"*"* ]]; then
            # All fields query pattern not allowed on AWQL table
            echo "${AWQL_QUERY_ERROR}"
            return 2
        fi
        # Manage alias name (AS)

        # Manage methods like SUM  or COUNT
        if [[ "$field" == *[\(\)]* ]]; then
            # Get only column name: SUM(Cost)
            field="${field%%\(*}"
            field="${field##*\)}"
        fi
        fields+=("$field")
    done
    components["${AWQL_REQUEST_FIELDS}"]="${fields[@]}"
    components["${AWQL_REQUEST_FIELD_NAME}"]="${fieldNames[@]}"

    # During check
    local during="${components["${AWQL_REQUEST_DURING}"]}"
    if ([[ "${#during[@]}" -eq 1 && "${during[0]}" =~ ^[[:digit:]]{8}$ ]]) || [[ "${#during[@]}" -gt 2 ]]; then
        echo "${AWQL_QUERY_ERROR_DURING}"
        return 2
    fi

    # Sort order by
    if [[ -n "${components["${AWQL_REQUEST_ORDER}"]}" ]]; then
        declare -a order="(${components["${AWQL_REQUEST_ORDER}"]})"
        declare -i orderColumn
        if [[ "${order[0]}" =~ ^[0-9]+$ ]]; then
            # Order by 1
            orderColumn="${order[0]}"
            if [[ ${orderColumn} -eq 0 || ${orderColumn} -gt ${fieldSize} ]]; then
                echo "${AWQL_QUERY_ERROR_ORDER}"
                return 2
            fi
            orderColumn+=-1
        else
            # Order by columnName
            orderColumn=$(arraySearch "${order[0]}" "${components["${AWQL_REQUEST_FIELD_NAME}"]}")
            if [[ $? -ne 0 ]]; then
                echo "${AWQL_QUERY_ERROR_ORDER}"
                return 2
            fi
        fi
        declare -A -r fieldsType="$(awqlFields "$apiVersion")"
        local type="${fieldsType[${fields[${orderColumn}]}]}"
        if [[ -z "$type" ]]; then
            echo "${AWQL_QUERY_ERROR_COLUMN_TYPE}"
            return 1
        fi
        orderColumn+=1

        # @fields CampaignId, CampaignName
        # @orderBy CampaignName ASC
        # @example d 2 0
        components["${AWQL_REQUEST_SORT_ORDER}"]="$(__queryOrderType "$type") $orderColumn $(__queryOrder "${order[1]}")"
    fi

    # Build AWQL query
    # SELECT...FROM...WHERE...DURING...
    declare -a awqlQuery
    awqlQuery+=("${components["${AWQL_REQUEST_STATEMENT}"]}")
    awqlQuery+=("${components["${AWQL_REQUEST_FIELD_NAME}"]// /,}")
    awqlQuery+=("FROM ${components["${AWQL_REQUEST_TABLE}"]}")
    if [[ -n "${components["${AWQL_REQUEST_WHERE}"]}" ]]; then
        awqlQuery+=("${AWQL_REQUEST_WHERE} ${components["${AWQL_REQUEST_WHERE}"]}")
    fi
    if [[ -n "${components["${AWQL_REQUEST_DURING}"]}" ]]; then
        awqlQuery+=("${AWQL_REQUEST_DURING} ${components["${AWQL_REQUEST_DURING}"]// /,}")
    fi
    components["${AWQL_REQUEST_QUERY}"]="${awqlQuery[@]}"
    components["${AWQL_REQUEST_QUERY_SOURCE}"]="$queryStr"
    components["${AWQL_REQUEST_TYPE}"]="select"

    arrayToString "$(declare -p components)"
}