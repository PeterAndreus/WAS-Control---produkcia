#!/bin/bash


genericDeploy(){  
  ssh $HOST_USER@$HOST "$BIN/wsadmin.sh -lang jython -user $USER -password $PASS -c \"AdminApp.update('$1', 'app', '[ -operation update -contents $2 -nopreCompileJSPs -installed.ear.destination \\\$(APP_INSTALL_ROOT)/$CELL -distributeApp -nouseMetaDataFromBinary -nodeployejb -createMBeansForResources -noreloadEnabled -nodeployws -validateinstall warn -noprocessEmbeddedConfig -filepermission .*\.dll=755#.*\.so=755#.*\.a=755#.*\.sl=755 -noallowDispatchRemoteInclude -noallowServiceRemoteInclude -asyncRequestDispatchType DISABLED -nouseAutoLink -noenableClientModule -clientMode isolated -novalidateSchema $3]' ) \"" 
}

genericPreDeploy(){

  echo "- UPLOADING ${1}"
  upload "$ISIS_DEVEL/${1}" "$EAR_REMOTE_DIR/${2}"

  local modulesToServersName=("${!4}")
  local modulesToServersValues=("${!5}")
  
  local finalMapForIBM="-MapModulesToServers [";
  local hostingMap="";
  for (( t=0; t<${#modulesToServersName[@]}; t++ ))
  do
    finalMapForIBM+="[ "    
    finalMapForIBM+="\\\"${modulesToServersName[$t]}\\\" ${modulesToServersValues[$t]}"
    if [[ "${modulesToServersValues[$t]}" == *war ]]; 
    then 
      finalMapForIBM+=",WEB-INF/web.xml " 
      hostingMap+="[\\\"${modulesToServersName[$t]}\\\" ${modulesToServersValues[$t]},WEB-INF/web.xml default_host ]"
    else 
      finalMapForIBM+=",META-INF/ejb-jar.xml " 
    fi
    
    if [ "$CLUSTER" == "" ]
    then
      finalMapForIBM+="WebSphere:cell=$CELL,node=$NODE,server=$SERVER ]"
    else
      finalMapForIBM+="WebSphere:cell=$CELL,cluster=$CLUSTER ]"
    fi
  done
  finalMapForIBM+="]"
  if [ "$hostingMap" != "" ]; 
  then 
    finalMapForIBM+=" -MapWebModToVH ["
    finalMapForIBM+="$hostingMap"
    finalMapForIBM+="]"
  fi
    
  genericDeploy $3 "$EAR_REMOTE_DIR/${2}" "$finalMapForIBM"
}

show_help(){
  echo -e "usage: wasCoreDeploy.sh <options> \n
    \t-d,  --deploy <config_file>
      \t\t deploy with configuration from application config file\n
    \t-h,  --help
      \t\t show this help
  "
}

main(){  
  while :; do
    case $1 in
        -h|-\?|--help)
            show_help
            exit
            ;;
        -d|--deploy)
            if [ "$2" ]; then
                file=$2
                shift 2
                continue
            else
                show_help
                exit 1
            fi
            ;;
        --deploy=?*)
            file=${1#*=} # Delete everything up to "=" and assign the remainder.
            ;;
        --deploy=)         # Handle the case of an empty --deploy=
            show_help
            exit 1
            ;;
        --)
            shift
            break
            ;;
        -?*)
            printf 'WARN: Unknown option (ignored): %s\n' "$1" >&2
            ;;
        *)
            break
    esac
    shift
  done
}

main $@