#!/bin/bash
RED='\e[1;31m'
BLUE='\e[1;34m'
NC='\e[0m'
ESC_SEQ="\E["
GREEN=$ESC_SEQ"32;01m"
YELLOW=$ESC_SEQ"33;01m"
MAGENTA=$ESC_SEQ"35;01m"
CYAN=$ESC_SEQ"36;01m"
WHITE=$ESC_SEQ"37;01m"
NE="\033[0m"
BOLD="\033[1m"
BLINK="\033[5m"
REVERSE="\033[7m"
UNDERLINE="\033[4m"

RUN_CONTROL_CONFIG=false;

upload() {
 scp $1 $WAS_HOST_USER@$WAS_HOST:$2
}

genericDeploy(){  
  ssh $WAS_HOST_USER@$WAS_HOST "$WAS_BIN_DIR/wsadmin.sh -lang jython -user $WAS_USER -password $WAS_PASS -c \"AdminApp.update('$1', 'app', '[ -operation update -contents $WAS_REMOTE_TMP_DIR/$APP_EAR -nopreCompileJSPs -installed.ear.destination \\\$(APP_INSTALL_ROOT)/$WAS_CELL -distributeApp -nouseMetaDataFromBinary -nodeployejb -createMBeansForResources -noreloadEnabled -nodeployws -validateinstall warn -noprocessEmbeddedConfig -filepermission .*\.dll=755#.*\.so=755#.*\.a=755#.*\.sl=755 -noallowDispatchRemoteInclude -noallowServiceRemoteInclude -asyncRequestDispatchType DISABLED -nouseAutoLink -noenableClientModule -clientMode isolated -novalidateSchema $2]' ) \"" 
}

postDeploy(){
  echo -e "SAVE CONFIG"
  ssh $WAS_HOST_USER@$WAS_HOST "$WAS_BIN_DIR/wsadmin.sh -lang jython -user $WAS_USER -password $WAS_PASS -c \"AdminConfig.save()\""
  echo -e "REMOVING OLD FILES"
  ssh $WAS_HOST_USER@$WAS_HOST "rm -fvr $WAS_REMOTE_TMP_DIR/*.ear"
}

genericPreDeploy(){

  echo -e "UPLOADING $APP_EAR from $APP_PATH_TO_EAR"
  upload "$APP_PATH_TO_EAR" "$WAS_REMOTE_TMP_DIR/$APP_EAR"

  
  local finalMapForIBM="-MapModulesToServers [";
  local hostingMap="";
  for (( t=0; t<${#MODULES_TO_SERVER_NAMES[@]}; t++ ))
  do
    finalMapForIBM+="[ "    
    finalMapForIBM+="\\\"${MODULES_TO_SERVER_NAMES[$t]}\\\" ${MODULES_TO_SERVER_VALUES[$t]}"
    if [[ "${MODULES_TO_SERVER_VALUES[$t]}" == *war ]]; 
    then 
      finalMapForIBM+=",WEB-INF/web.xml " 
      hostingMap+="[\\\"${MODULES_TO_SERVER_NAMES[$t]}\\\" ${MODULES_TO_SERVER_VALUES[$t]},WEB-INF/web.xml default_host ]"
    else 
      finalMapForIBM+=",META-INF/ejb-jar.xml " 
    fi
    
    if [ "$WAS_CLUSTER" == "" ]
    then
      finalMapForIBM+="WebSphere:cell=$WAS_CELL,node=$WAS_NODE,server=$WAS_SERVER ]"
    else
      finalMapForIBM+="WebSphere:cell=$WAS_CELL,cluster=$WAS_CLUSTER ]"
    fi
  done
  finalMapForIBM+="]"
  if [ "$hostingMap" != "" ]; 
  then 
    finalMapForIBM+=" -MapWebModToVH ["
    finalMapForIBM+="$hostingMap"
    finalMapForIBM+="]"
  fi
    
  genericDeploy $APP_NAME "$finalMapForIBM"
  
}

show_help(){
  echo -e " $BOLD usage: $NC wasCoreDeploy.sh <options> \n\n
    \t $BOLD -d,  --deploy <config_file> $NC
      \t\t deploy with configuration from application config file\n
    \t $BOLD -h,  --help $NC
      \t\t show this help \n
    \t $BOLD -v,  --validate \n $NC
      \t\t run deployment with validation of configuration file \n
  "
}

loadConfig(){
  if [ -f $SCRIPT_DIR/global.config ];
  then
    echo -e "Global configuration file exists. Mixing in."
    . $SCRIPT_DIR/global.config
  else
    echo -e "Global configuration does not exist. Using user configuration ONLY!."
  fi
  . $1
}

controlConfig(){
  local variablesForCheck=("$WAS_HOST" "WAS_HOST" "$WAS_HOST_USER" "WAS_HOST_USER" "$WAS_PROFILE" "WAS_PROFILE" "$WAS_CELL" "WAS_CELL" "$WAS_USER" "WAS_USER" "$WAS_PASS" "WAS_PASS" "$WAS_REMOTE_TMP_DIR" "WAS_REMOTE_TMP_DIR" "$WAS_BIN_DIR" "WAS_BIN_DIR" "$PORTAL_HOST" "PORTAL_HOST" "$PORTAL_HOST_USER" "PORTAL_HOST_USER" "$PORTAL_USER" "PORTAL_USER" "$PORTAL_PASS" "PORTAL_PASS" "$APP_VERSION" "APP_VERSION" "$APP_EAR" "APP_EAR" "$APP_PATH_TO_EAR" "APP_PATH_TO_EAR" "$APP_NAME" "APP_NAME");
  
  local validate=true;
  
  for (( t=0; t<${#variablesForCheck[@]}; t+=2 ))
  do
  echo -e "
  $BOLD Variable:$NE ${variablesForCheck[$t+1]}$BOLD  	
      value:$NE \"${variablesForCheck[$t]}\"  "  
    if [ -z "${variablesForCheck[$t]}" ] 
    then 
      validate=false;
      echo -e "$RED Variable ${variablesForCheck[$t+1]} is $BOLD NOT$NE$RED set! $NC"
    fi
  done
  
  if [ -z "$WAS_CLUSTER" ] 
  then 
    if [ -z "$WAS_NODE" -o -z "$WAS_SERVER" ] 
    then
      validate=false;
      echo -e "$RED Cluster nor server/node is set! $NC"
    fi
  fi
  
  if [ -z "$MODULES_TO_SERVER_NAMES" -o -z "$MODULES_TO_SERVER_VALUES" ] 
  then 
    validate=false;
    echo -e "$RED Modules to deploy are not set! $NC"
  fi
  
  if [ $validate == "false" ]
  then
    echo -e "$RED \n Press ENTER to exit $NC \n"
    read
    exit;
  fi
}

deploy(){  
  loadConfig $1
  
  if [ $RUN_CONTROL_CONFIG == "true" ]
  then
   controlConfig
  fi
   
  genericPreDeploy
  postDeploy
}

main(){
  SCRIPT_DIR="$(dirname "$0")"
  while :; do
    case $1 in
        -h|-\?|--help)
            show_help
            exit
            ;;
        -d|--deploy)
            if [ "$2" ]; then
                file=$2
                deploy $file
                shift 2
                continue
            else
                show_help
                exit 1
            fi
            ;;
        --deploy=?*)
            file=${1#*=} # Delete everything up to "=" and assign the remainder.
            deploy $file
            ;;
        --deploy=)         # Handle the case of an empty --deploy=
            show_help
            exit 1
            ;;
	-v)
	    RUN_CONTROL_CONFIG=true;
	    ;;
	-vd | -dv )
	    RUN_CONTROL_CONFIG=true;  
	    if [ "$2" ]; then
                file=$2
                deploy $file
                shift 2
                continue
            else
                show_help
                exit 1
            fi          
            ;;
        --validate )
	    RUN_CONTROL_CONFIG=true;  
	    ;;
	   
            
        --)
	    echo -e "No option set";
            shift
            break
            ;;
        -?*)
            echo -e 'WARN: Unknown option (ignored): %s\n' "$1" >&2
            ;;
        *)
            break
    esac
    shift
  done
}

main $@