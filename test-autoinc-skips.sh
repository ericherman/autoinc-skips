#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2021-2024 Stichting Open Electronics Lab

# set -x
set -e
set -o pipefail

DB_PORT_EXTERNAL=$(perl -E 'use IO::Socket::INET;
say IO::Socket::INET->new(Listen => 1)->sockport');
echo DB_PORT_EXTERNAL=$DB_PORT_EXTERNAL

MARIADB_VERSION=10.6
DB_SCHEMA_NAME=autoincskips
DB_CONTAINER_NAME=${DB_SCHEMA_NAME}_${DB_PORT_EXTERNAL}_mariadb
# echo "#    creating new password from /dev/urandom"
DB_ROOT_PASSWORD=$(cat /dev/urandom \
		| tr --delete --complement 'a-zA-Z0-9' \
		| fold --width=32 \
		| head --lines=1 \
		| xargs || true
)
DB_USER_NAME=$DB_SCHEMA_NAME
DB_USER_PASSWORD=$DB_ROOT_PASSWORD
DB_DEFAULTS_FILE=${DB_SCHEMA_NAME}.root.my.cnf

rm -f ./container.env
touch ./container.env
chmod -v 600 ./container.env
cat > container.env << EOF
DB_PORT_EXTERNAL=$DB_PORT_EXTERNAL
DB_SCHEMA_NAME=$DB_SCHEMA_NAME
DB_CONTAINER_NAME=$DB_CONTAINER_NAME
DB_ROOT_PASSWORD=$DB_ROOT_PASSWORD
DB_USER_NAME=$DB_USER_NAME
DB_USER_PASSWORD=$USER_PASSWORD
DB_DEFAULTS_FILE=$DB_DEFAULTS_FILE
EOF
ls -l container.env

# echo "# check user '$USER' for group 'docker' membership"
if groups | grep -q docker; then
	echo "#    user '$USER' is member of 'docker' group (ok)"
else
	echo
	echo '# ------------------------------------------'
	echo "# user $USER not in group 'docker'"
	echo "# groups are: $(groups | sed -e's/\s/\n\t/g')"
	echo '# consider:'
	echo "    sudo usermod -a -G docker $USER"
	echo '# ------------------------------------------'
	echo
fi

# echo '# ensure db container is not already running'
docker stop ${DB_CONTAINER_NAME} 2>/dev/null || true

# echo '# start db container'
docker run -d \
	-p 127.0.0.1:$DB_PORT_EXTERNAL:3306 \
	--name $DB_CONTAINER_NAME \
	--env MYSQL_DATABASE=$DB_SCHEMA_NAME \
	--env MYSQL_USER=$DB_USER_NAME \
	--env MYSQL_PASSWORD=$DB_USER_PASSWORD \
	--env MYSQL_ROOT_PASSWORD=$DB_ROOT_PASSWORD \
	--rm \
	mariadb:$MARIADB_VERSION

function cleanup-info()
{
	cat <<-EOF

	#
	# Connect to the database with:
	#
		 docker exec -it ${DB_CONTAINER_NAME} mariadb \\
			  --defaults-file=/$DB_DEFAULTS_FILE \\
			  --host=127.0.0.1 \\
			  --port=3306 \\
			  $DB_SCHEMA_NAME
	#
	#
	#
	# stop the instance with:
	     docker stop ${DB_CONTAINER_NAME}
	#
	#
	EOF
}
trap 'EXIT_CODE=$?; cleanup-info; exit $EXIT_CODE' EXIT

# docker exec -it ${DB_CONTAINER_NAME} bash

cat > $DB_DEFAULTS_FILE << EOF
[client]
user=root
password=$DB_ROOT_PASSWORD
EOF
docker cp -L $DB_DEFAULTS_FILE ${DB_CONTAINER_NAME}:/$DB_DEFAULTS_FILE
docker exec ${DB_CONTAINER_NAME} ls -l /$DB_DEFAULTS_FILE

function run-sql()
{
	SQL=$1
	SCHEMA=$2
	BATCH=$3
	if [ -z "$SCHEMA" ]; then
		SCHEMA=$DB_SCHEMA_NAME
	fi
	echo
	echo "$SQL"
	docker exec ${DB_CONTAINER_NAME} mariadb \
		--defaults-file=/$DB_DEFAULTS_FILE \
		--host=127.0.0.1 \
		--port=3306 \
		$DB_SCHEMA_NAME \
		-e "$SQL"
}

function run-sql-file()
{
	SQL_FILE=$1
	BASE_SQL=$(basename $SQL_FILE)
	echo "# $BASE_SQL"
	docker cp -L $SQL_FILE ${DB_CONTAINER_NAME}:/$BASE_SQL
	docker exec ${DB_CONTAINER_NAME} ls -l /$BASE_SQL
	run-sql "source /$BASE_SQL"
}

RETRIES_LEFT=10
while [ $RETRIES_LEFT -gt 0 ]; do
	if run-sql "SELECT 1" >/dev/null 2>&1; then
		RETRIES_LEFT=0
	else
		RETRIES_LEFT=$(( $RETRIES_LEFT - 1 ))
		sleep 1;
	fi
done

run-sql "SHOW DATABASES;" mysql

# docker exec -it ${DB_CONTAINER_NAME} bash

echo "Loading initial data ..."
run-sql-file ./autoinc-skips-setup.sql
echo "Loading initial data .... Done."

echo "Running create statements for table bp_pid ..."
run-sql-file ./autoinc-skips.sql
echo "Running create statements for table bp_pid .... Done."

RESULTS=$(
	run-sql "SELECT COUNT(*), MAX(row_id) FROM bp_pid;" \
	| tail -n1 \
	| sed -e 's/\s\s*/ /g'
)
ROW_COUNT=$(echo "$RESULTS" | cut -f1 -d' ')
MAX_ROW_ID=$(echo "$RESULTS" | cut -f2 -d' ')

if [ $ROW_COUNT -ne $MAX_ROW_ID ]; then
	ERRORS=1
	cat <<-EOF

	####################################################
	FAILURE!
	  row count does not match the max id
	  auto-inc ids were skipped
	####################################################

	EOF
	run-sql "SELECT COUNT(*), MAX(row_id) FROM bp_pid;"
else
	ERRORS=0
	cat <<-EOF

	####################################################
	SUCCESS
	####################################################
	EOF
fi
exit $ERRORS
