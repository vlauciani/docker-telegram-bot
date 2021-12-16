#!/bin/bash

# Check software
for PROGRAM in sed awk docker docker-compose date ; do
    command -v ${PROGRAM} >/dev/null 2>&1 || { echo >&2 " \"${PROGRAM}\" program doesn't exist.  Aborting."; exit 1; }
done

# Variables
DATE_NOW=$( date +%Y%m%dT%H%M%S )
DIR_WORK=$( cd $(dirname $0) ; cd .. ; pwd)
CURRENT_BRANCH="$(cd ${DIR_WORK} && git rev-parse --abbrev-ref HEAD)"
PROJECT_NAME="$(cd ${DIR_WORK} && basename $(git rev-parse --show-toplevel) )"

DIR_SUBMODULE_LARADOCK=laradock
FILE_ENV_LARADOCK=${DIR_WORK}/${DIR_SUBMODULE_LARADOCK}/.env.example
if [[ "${CURRENT_BRANCH}" == "master" ]] || [[ "${CURRENT_BRANCH}" == "main" ]]; then
    LARADOCK_HTTP_PORT=80
    LARADOCK_REDIS_PORT=6379
elif [[ "${CURRENT_BRANCH}" == "develop" ]]; then
    LARADOCK_HTTP_PORT=8087
    LARADOCK_REDIS_PORT=6380
else
    LARADOCK_HTTP_PORT=8089
    LARADOCK_REDIS_PORT=6385
fi

# Functions
function cleanLaradock() {
	#echo "cd ${DIR_WORK}/${DIR_SUBMODULE_LARADOCK} ; docker-compose down ; cd - ; mv -v ${DIR_WORK}/${DIR_SUBMODULE_LARADOCK}/.env ${DIR_WORK}/${DIR_SUBMODULE_LARADOCK}/.env.bck ; rm -fv ${DIR_WORK}/database/ingvDb.sqlite ${DIR_WORK}/storage/framework/views/*.php ${DIR_WORK}/storage/logs/*.log"
    echo " \"cleanLaradock\" function placeholder!"
}

function checkReturnCode() {
	RET=${1}
	if (( ${RET} != 0 )); then
		echo ""
		echo "Last command return: ${RET}"
		eval $( cleanLaradock )
		echo ""
		exit 1
	fi
}

# Check OS type
OSNAME=$( uname -s )
if [ ${OSNAME} == "Darwin" ] || [ ${OSNAME} == "Linux" ]; then
	echo ""
else
	echo "OS must be Linux or Darwin (Mac); your is ${OSNAME}"
	echo ""
	exit 1
fi

# Check that the branch contains module
FILE_GIT_MODULE=${DIR_WORK}/.gitmodules
if [ ! -f ${FILE_GIT_MODULE} ]; then
	echo ""
	echo "No \".gitmodules\" file presents"
	echo ""
	exit 1
fi

# Check that .gitmodules contains 'laradock'
if ! grep -q ${DIR_SUBMODULE_LARADOCK} ${FILE_GIT_MODULE}; then
	echo ""
	echo "The file \"${FILE_GIT_MODULE}\" does not contain \"${DIR_SUBMODULE_LARADOCK}\"."
	echo ""
	exit 1
fi

# Clone submodule
cd ${DIR_WORK}
git submodule update --init --recursive
checkReturnCode ${?}

#
echo "Restore laradock files with 'git checkout -- .':"
cd ${DIR_SUBMODULE_LARADOCK}
git checkout -- .
checkReturnCode ${?}
echo "Done"
echo ""

# Update Laradock 'docker-compose.yml'. Issue: https://github.com/laradock/laradock/issues/2947
echo "Update Laradock 'docker-compose.yml':"
FILE_DOCKERCOMPOSE="docker-compose.yml"
if [[ -f ${FILE_DOCKERCOMPOSE} ]]; then
    # this is use only to format original docker-compose.yml file
    docker run --rm -v $( pwd ):$( pwd ) -w $( pwd ) mikefarah/yq e -i 'del(.dante8fakeline)' ${FILE_DOCKERCOMPOSE}
    checkReturnCode ${?}

    echo " copy \"${FILE_DOCKERCOMPOSE}\" to \"${FILE_DOCKERCOMPOSE}.${DATE_NOW}\":"
    cp -v ${FILE_DOCKERCOMPOSE} ${FILE_DOCKERCOMPOSE}.${DATE_NOW}
    checkReturnCode ${?}
    
    echo " removing: services.workspace.ports"
    docker run --rm -v $( pwd ):$( pwd ) -w $( pwd ) mikefarah/yq e -i 'del(.services.workspace.ports)' ${FILE_DOCKERCOMPOSE}
    checkReturnCode ${?}

    echo " removing: services.php-fpm.ports"
    docker run --rm -v $( pwd ):$( pwd ) -w $( pwd ) mikefarah/yq e -i 'del(.services.php-fpm.ports)' ${FILE_DOCKERCOMPOSE}
    checkReturnCode ${?}

    echo " setting: .services.nginx.ports = [\"\${NGINX_HOST_HTTP_PORT}:80\"]"
    docker run --rm -v $( pwd ):$( pwd ) -w $( pwd ) mikefarah/yq e -i '.services.nginx.ports = ["${NGINX_HOST_HTTP_PORT}:80"]' ${FILE_DOCKERCOMPOSE}
    checkReturnCode ${?}
fi
cd -
echo "Done"
echo ""

# Create sqlite DB and configure Laravel .env file
DB_NAME="telegram-bot.sqlite"
echo "Create sqlite db:"
touch database/${DB_NAME}
echo "Done"
echo ""

# Set 'laravel' .env file for sqlite DB
if [[ -f .env ]]; then
    sed \
        -e 's|DB_DANTE_GENERAL_PURPOSE_PATH=.*|DB_DANTE_GENERAL_PURPOSE_PATH=/var/www/database/${DB_NAME}|' \
        .env > .env.update
        mv .env.update .env
fi

# Create 'laradock' .env file
cd ${DIR_WORK}
if [ "${OSNAME}" == "Linux" ] && [ "$(whoami)" != "root" ]; then
	sed \
	-e "s|WORKSPACE_PUID=.*|WORKSPACE_PUID=$( id -u )|" \
	-e "s|WORKSPACE_PGID=.*|WORKSPACE_PGID=$( id -g )|" \
	${FILE_ENV_LARADOCK} > ${DIR_SUBMODULE_LARADOCK}/.env.tmp
	LARADOCK_USER_FOR_WORKSPACE="laradock"

	# Set 777 'database' dir and 'ingvDb/sqlite' file
	chmod 777 database/
	chmod 777 database/${DB_NAME}

else
	cp ${FILE_ENV_LARADOCK} ${DIR_SUBMODULE_LARADOCK}/.env.tmp
	LARADOCK_USER_FOR_WORKSPACE="root"
fi
sed \
-e "s|REDIS_PORT=.*|REDIS_PORT=${LARADOCK_REDIS_PORT}|" \
-e "s|NGINX_HOST_HTTP_PORT=.*|NGINX_HOST_HTTP_PORT=${LARADOCK_HTTP_PORT}|" \
-e "s|WORKSPACE_INSTALL_YAML=.*|WORKSPACE_INSTALL_YAML=true|" \
-e "s|WORKSPACE_INSTALL_PHPREDIS=.*|WORKSPACE_INSTALL_PHPREDIS=true|" \
-e "s|PHP_FPM_INSTALL_PHPREDIS=.*|PHP_FPM_INSTALL_PHPREDIS=true|" \
-e "s|PHP_FPM_INSTALL_YAML=.*|PHP_FPM_INSTALL_YAML=true|" \
-e "s|PHP_WORKER_INSTALL_PGSQL=.*|PHP_WORKER_INSTALL_PGSQL=true|" \
-e "s|PHP_FPM_INSTALL_PGSQL=.*|PHP_FPM_INSTALL_PGSQL=true|" \
-e "s|PHP_VERSION=.*|PHP_VERSION=8.0|" \
-e "s|PHP_FPM_INSTALL_DOCKER_CLIENT=.*|PHP_FPM_INSTALL_DOCKER_CLIENT=false|" \
-e "s|LARAVEL_HORIZON_INSTALL_PHPREDIS=.*|LARAVEL_HORIZON_INSTALL_PHPREDIS=true|" \
-e "s|LARAVEL_HORIZON_INSTALL_YAML=.*|LARAVEL_HORIZON_INSTALL_YAML=true|" \
-e "s|LARAVEL_HORIZON_INSTALL_SOCKETS=.*|LARAVEL_HORIZON_INSTALL_SOCKETS=true|" \
-e "s|WORKSPACE_INSTALL_NPM_VUE_CLI=.*|WORKSPACE_INSTALL_NPM_VUE_CLI=false|" \
-e "s|WORKSPACE_INSTALL_MYSQL_CLIENT=.*|WORKSPACE_INSTALL_MYSQL_CLIENT=true|" \
-e "s|COMPOSE_PROJECT_NAME=.*|COMPOSE_PROJECT_NAME=laradock-${PROJECT_NAME}-${CURRENT_BRANCH}|" \
${DIR_SUBMODULE_LARADOCK}/.env.tmp > ${DIR_SUBMODULE_LARADOCK}/.env
rm ${DIR_SUBMODULE_LARADOCK}/.env.tmp

# Set NGINX
echo "Set NGINX conf:"
if [[ -f ${DIR_SUBMODULE_LARADOCK}/nginx/sites/default.conf ]]; then
	mv -f ${DIR_SUBMODULE_LARADOCK}/nginx/sites/default.conf ${DIR_SUBMODULE_LARADOCK}/nginx/sites/default.conf.original
fi
sed \
    -e "s|^\([ \t]*\)server_name.*$|\1server_name $( hostname -f );|" \
    -e "s|^\([ \t]*\)root.*$|\1root /var/www/public;|" \
    ${DIR_SUBMODULE_LARADOCK}/nginx/sites/laravel.conf.example > ${DIR_SUBMODULE_LARADOCK}/nginx/sites/laravel.conf
echo "Done"
echo ""

# Set PHP-FPM
echo "Set PHP-FPM conf:"
FILE_PHPFPM_LARAVELINI=${DIR_SUBMODULE_LARADOCK}/php-fpm/laravel.ini
if [[ -f ${FILE_PHPFPM_LARAVELINI} ]]; then
    mv -f ${FILE_PHPFPM_LARAVELINI} ${FILE_PHPFPM_LARAVELINI}.${DATE_NOW}
fi
sed \
    -e "s|memory_limit\ \=.*|memory_limit = 512M|" \
    ${FILE_PHPFPM_LARAVELINI}.${DATE_NOW} > ${FILE_PHPFPM_LARAVELINI}
echo "Done"
echo ""

# 
echo "Now, run:"
echo " $ cd laradock-dante"
echo " $ docker-compose build --no-cache --pull nginx redis workspace "
echo " $ docker-compose up -d nginx redis workspace "
echo ""
