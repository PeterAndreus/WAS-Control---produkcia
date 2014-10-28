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

#-------------------------------------------------------------------------------------------------------------------
#--------------------------------------------------HELPERS----------------------------------------------------------
#-------------------------------------------------------------------------------------------------------------------

show_help(){
  echo -e " $BOLD usage: $NC wasCoreDeploy.sh <options> \n\n
    \t $BOLD -d,  --deploy <config_file> $NC
      \t\t deploy EAR application with configuration from application config file\n
    \t $BOLD -w,  --deploy-war <config_file> $NC
      \t\t deploy WAR application with configuration from application config file\n
    \t $BOLD -v<deployment options>$NC
      \t\t run deployment with validation of configuration file \n 
      \t\t$UNDERLINE EXAMPLE:$NC wasDeployCore.sh -vd app.config \n 
    \t $BOLD -v,  --validate <validate options>$NC
      \t\t run validation of configuration file \n 
      \t\t$UNDERLINE OPTIONS:$NC 
      \t\t$BOLD ear <config_file> $NC- control Ear configuration file 
      \t\t$BOLD war <config_file> $NC- control War configuration file 
      \t\t$BOLD jar <config_file> $NC- control Jar configuration file \n
    \t $BOLD -j, --jar-files <config_file>$NC
      \t\t replace shared libraries defined by configuration file \n
    \t $BOLD -g,  --gui  $NC
      \t\t show GUI \n
    \t $BOLD -h,  --help $NC
      \t\t show this help \n
  "
}

upload() {
 scp $1 $WAS_HOST_USER@$WAS_HOST:$2
}


#-------------------------------------------------------------------------------------------------------------------
#--------------------------------------------------DEPLOYMENT-------------------------------------------------------
#-------------------------------------------------------------------------------------------------------------------

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

  echo -e "UPLOADING $APP_EAR from $APP_PATH"
  upload "$APP_PATH/$APP_EAR" "$WAS_REMOTE_TMP_DIR/$APP_EAR"

  
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

deploy(){  
  loadConfig $1
  
  if [ $RUN_CONTROL_CONFIG == "true" ]
  then
   controlEarConfig
  fi
   
  genericPreDeploy
  postDeploy
}

warDeploy(){
  loadConfig $1
  
  if [ $RUN_CONTROL_CONFIG == "true" ]
  then
   controlWarConfig
  fi
  
  echo -e "<request xmlns:xsi=\"http://www.w3.org/2001/XMLSchema-instance\" xsi:noNamespaceSchemaLocation=\"PortalConfig_1.4.xsd\" type=\"update\" create-oids=\"true\">
	  <portal action=\"locate\">
	    <web-app action=\"update\" active=\"true\" uid=\"$APP_WEBMOD\">
	      <url>file:///\$server_root\$/installableApps/$APP_NAME</url>
	      <portlet-app action=\"update\" active=\"true\" uid=\"$APP_MODULE\"></portlet-app>
	    </web-app>	
	  </portal>
	</request>" > tmpUpdate.xmlaccess
	
  scp $APP_PATH/$APP_NAME $PORTAL_HOST_USER@$PORTAL_HOST:$PORTAL_SERVER_DIR/installableApps/
  scp tmpUpdate.xmlaccess $PORTAL_HOST_USER@$PORTAL_HOST:$PORTAL_SERVER_DIR/installableApps/
 
  echo "- DEPLOY START"
  ssh $PORTAL_HOST_USER@$PORTAL_HOST "$PORTAL_SERVER_DIR/bin/xmlaccess.sh" -in "$PORTAL_SERVER_DIR/installableApps/tmpUpdate.xmlaccess" -user $PORTAL_USER -pwd $PORTAL_PASS -url $WPS_ADMIN_URL -out "$PORTAL_SERVER_DIR/deploymentresults.xmlaccess"  
  
  echo "- CLEANING"
  ssh $PORTAL_HOST_USER@$PORTAL_HOST "rm -fv $PORTAL_SERVER_DIR/installableApps/$APP_NAME"
  ssh $PORTAL_HOST_USER@$PORTAL_HOST "rm -fv $PORTAL_SERVER_DIR/installableApps/tmpUpdate.xmlaccess"

}

#-------------------------------------------------------------------------------------------------------------------
#----------------------------------------------------JAR------------------------------------------------------------
#-------------------------------------------------------------------------------------------------------------------

removeOldJar(){
  ssh $3 "rm -fvr $4/$1" < /dev/null
}

sendNewJar(){
  scp $2/$1 $3:$4 < /dev/null
}

replaceJarWithoutUser(){
  eval tmp=(\${${1}[@]})
  if [ ${#tmp[@]} == 4 ]
  then
    removeOldJar ${tmp[0]} ${tmp[1]} ${tmp[2]} ${tmp[3]}
    sendNewJar ${tmp[0]} ${tmp[1]} ${tmp[2]} ${tmp[3]}
  fi
  unset tmp
}

parseJarConfig(){
  . $1
  while read i || [[ -n "$i" ]]
  do
    if [[ $i != \#* ]]
    then
      eval name=$(echo $i | cut -d"=" -f1)
      if [ ! -z "$i" ]
      then
	declare -p $name | grep -q '^declare \-a' && replaceJarWithoutUser $name
      fi
    fi
  done < $1
  
  unset name
}

#-------------------------------------------------------------------------------------------------------------------
#----------------------------------------------CONFIG AND SETUP-----------------------------------------------------
#-------------------------------------------------------------------------------------------------------------------

loadConfig(){
  if [ -f $WORK_DIR/global.config ];
  then
    echo -e "Global configuration file exists. Mixing in."
    . $WORK_DIR/global.config
  else
    echo -e "Global configuration does not exist. Using user configuration ONLY!."
  fi
  . $1
}

controlWarConfig(){
  local variablesForCheck=("$PORTAL_HOST" "PORTAL_HOST" "$PORTAL_HOST_USER" "PORTAL_HOST_USER" "$PORTAL_USER" "PORTAL_USER" "$PORTAL_PASS" "PORTAL_PASS" "$PORTAL_SERVER_DIR" "PORTAL_SERVER_DIR"  "$APP_NAME" "APP_NAME" "$APP_PATH" "APP_PATH" "$APP_MODULE" "APP_MODULE" "$APP_WEBMOD" "APP_WEBMOD" "$WPS_ADMIN_URL" "WPS_ADMIN_URL");
  
  local validate=true
  
  for (( t=0; t<${#variablesForCheck[@]}; t+=2 ))
  do
  echo -e "
  $BOLD Variable:$NE ${variablesForCheck[$t+1]}$BOLD  	
      value:$NE \"${variablesForCheck[$t]}\"  "  
    if [ -z "${variablesForCheck[$t]}" ] 
    then 
      validate=false
      echo -e "$RED Variable ${variablesForCheck[$t+1]} is $BOLD NOT$NE$RED set! $NC"
    fi
  done
  
  if [ $validate == "false" ]
  then
    echo -e "$RED \n Press ENTER to exit $NC \n"
    read
    exit
  fi
}

controlEarConfig(){
  local variablesForCheck=("$WAS_HOST" "WAS_HOST" "$WAS_HOST_USER" "WAS_HOST_USER" "$WAS_PROFILE" "WAS_PROFILE" "$WAS_CELL" "WAS_CELL" "$WAS_USER" "WAS_USER" "$WAS_PASS" "WAS_PASS" "$WAS_REMOTE_TMP_DIR" "WAS_REMOTE_TMP_DIR" "$WAS_BIN_DIR" "WAS_BIN_DIR" "$APP_EAR" "APP_EAR" "$APP_PATH" "APP_PATH" "$APP_NAME" "APP_NAME");
  
  local validate=true
  
  for (( t=0; t<${#variablesForCheck[@]}; t+=2 ))
  do
  echo -e "
  $BOLD Variable:$NE ${variablesForCheck[$t+1]}$BOLD  	
      value:$NE \"${variablesForCheck[$t]}\"  "  
    if [ -z "${variablesForCheck[$t]}" ] 
    then 
      validate=false
      echo -e "$RED Variable ${variablesForCheck[$t+1]} is $BOLD NOT$NE$RED set! $NC"
    fi
  done
  
  if [ -z "$WAS_CLUSTER" ] 
  then 
    if [ -z "$WAS_NODE" -o -z "$WAS_SERVER" ] 
    then
      validate=false
      echo -e "$RED Cluster nor server/node is set! $NC"
    fi
  fi
  
  if [ -z "$MODULES_TO_SERVER_NAMES" -o -z "$MODULES_TO_SERVER_VALUES" ] 
  then 
    validate=false
    echo -e "$RED Modules to deploy are not set! $NC"
  fi
  
  if [ $validate == "false" ]
  then
    echo -e "$RED \n Press ENTER to exit $NC \n"
    read
    exit
  fi
}

controlGlobalConfig(){
local variablesForCheck=("$VERSION" "VERSION" "$WAS_HOST" "WAS_HOST" "$WAS_HOST_USER" "WAS_HOST_USER" "$WAS_PROFILE" "WAS_PROFILE" "$WAS_CELL" "WAS_CELL" "$WAS_USER" "WAS_USER" "$WAS_PASS" "WAS_PASS" "$WAS_BIN_DIR" "WAS_BIN_DIR" "$WAS_SERVER_DIR" "WAS_SERVER_DIR" "$PORTAL_HOST" "PORTAL_HOST" "$PORTAL_HOST_USER" "PORTAL_HOST_USER" "$PORTAL_USER" "PORTAL_USER" "$PORTAL_PASS" "PORTAL_PASS" "$PORTAL_CELL" "PORTAL_CELL" "$PORTAL_SERVER_DIR" "PORTAL_SERVER_DIR" "$SHARED_JAR_FOLDER" "SHARED_JAR_FOLDER" "$PATH_TO_EJB_FILES" "PATH_TO_EJB_FILES" "$LOCAL_EJB_URL" "LOCAL_EJB_URL" "$REMOTE_EJB_URL_PORTAL" "REMOTE_EJB_URL_PORTAL" "$REMOTE_EJB_URL_WAS" "REMOTE_EJB_URL_WAS");
  
  local validate=true
  
  for (( t=0; t<${#variablesForCheck[@]}; t+=2 ))
  do
  echo -e "
  $BOLD Variable:$NE ${variablesForCheck[$t+1]}$BOLD  	
      value:$NE \"${variablesForCheck[$t]}\"  "  
    if [ -z "${variablesForCheck[$t]}" ] 
    then 
      validate=false
      echo -e "$RED Variable ${variablesForCheck[$t+1]} is $BOLD NOT$NE$RED set! $NC"
    fi
  done
  
  if [ $validate == "false" ]
  then
    echo -e "$RED \n Press ENTER to exit $NC \n"
    read
    exit
  fi
}

controlParser(){

  if [ -f $WORK_DIR/global.config ];
  then
    . $WORK_DIR/global.config
  fi
    
  . $2
  case "$1" in
    "app" | "ear")
      controlEarConfig
      ;;
    "war")
      controlWarConfig
      ;;
    "jar")
      echo "Nothing to control"
      ;;
  esac  
  echo -e "$RED \n Press ENTER to continue $NC \n"
  read
}

setupAndRunGUI(){  
  setupGlobalConfig
  
  if [ -f $BASEDIR/guiConfig ];
  then
    . $BASEDIR/guiConfig
    clear
    menu
  else
    echo -e "$RED Script file guiConfig not found in $BASEDIR ! $NC"
    echo -e "$RED \n Press ENTER to exit $NC \n"
    read
    exit
  fi
}

setupGlobalConfig(){
 if [ -f $WORK_DIR/global.config ];
  then
    . $WORK_DIR/global.config
    if [ $RUN_CONTROL_CONFIG == "true" ]
    then
      controlGlobalConfig
    fi
  else
    echo -e "Global configuration does not exist."
    echo -e "$RED \n Press ENTER to exit $NC \n"
    read
    exit
  fi
}


#-------------------------------------------------------------------------------------------------------------------
#--------------------------------------------------MAIN-------------------------------------------------------------
#-------------------------------------------------------------------------------------------------------------------


main(){
  WORK_DIR="$(pwd)"
  BASEDIR=$(dirname $0)
  while :; do
    case $1 in
        -h|-\?|--help)
            show_help
            exit
            ;;
        -d| --deploy)
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
        -w| --deploy-war)
	  if [ "$2" ]; then
                file=$2
                warDeploy $file
                shift 2
                continue
            else
                show_help
                exit 1
            fi
            ;;
        --deploy-war=?*)
            file=${1#*=} # Delete everything up to "=" and assign the remainder.
            warDeploy $file
            ;;
        --deploy-war=)         # Handle the case of an empty --deploy-war=
            show_help
            exit 1
            ;;
	-v |  --validate )
	    RUN_CONTROL_CONFIG=true;
	    if [ "$2" ] && [ "$3" ]
	    then
		controlParser $2 $3
		shift 3
		continue
	    else	      
                show_help
                exit 1
	    fi
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
            
	-vw | -wv )
	    RUN_CONTROL_CONFIG=true;  
	    if [ "$2" ]; then
                file=$2
                warDeploy $file
                shift 2
                continue
            else
                show_help
                exit 1
            fi          
            ;;
	-g| --gui)
	    setupAndRunGUI;
	    ;;
	-j| --jar-files)	    
            if [ "$2" ]; then
		setupGlobalConfig
                jar_config=$2
                parseJarConfig $jar_config
                shift 2
                continue
            else
                show_help
                exit 1
            fi
            ;;            
        --jar-files=?*)
            jar_config=${1#*=} # Delete everything up to "=" and assign the remainder.
            setupGlobalConfig
            parseJarConfig $jar_config
            ;;
        --jar-filesr=)         # Handle the case of an empty --deploy-war=
            show_help
            exit 1
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