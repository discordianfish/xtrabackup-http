#!/bin/bash
set -euo pipefail
SALARIES_CHECKSUM_EXPECT=3774506747
TITLES_CHECKSUM_EXPECT=1955358698

msc() {
	local prefix=$1
	shift
	mysqld --no-defaults -h "$prefix" \
		--socket "$prefix.sock" \
		--skip-grant \
		--skip-networking "$@"
}

# Do not depend on this, it's really brittle
cleanup_and_exit() {
	local root=$1
	local err=$?
	if [[ "$err" -gt 0 ]]; then
		echo "Build failed"
		tail -20 "$root"/*.log
		exit $err
	fi
	[[ -e "$root"/*.pid ]] && cat "$root"/*.pid | xargs pkill -P
	[[ -n ${TMP+x} ]] && rm -rf "$TMP"
	exit 0
}

stop_svc() {
	local pidfile=$1
	kill "$(cat "$pidfile")"
	rm "$pidfile"
}

wait_for_mysql() {
	local sock=$1
	local i=0
	echo "- waiting for $sock"
	while ! mysqladmin -s ping -u root -S "$sock"; do
		echo -n .
		if [[ "$i" -ge 10 ]]; then
			echo
			echo "Can't connect to $sock after $i attemps, aborting" >&2
			exit 1
		fi
		let i++ || true # I hate you bash.
		sleep 1
	done
	echo
}

create_backups() {
	local root=$1
	echo "Bringing up source mysql instance"
	mysql_install_db --no-defaults "--datadir=$root/source"
	# for mysql >=5.7
	# msc "$root/source" --initialize-insecure > "$root/source.mysql.init.log" 2>&1
	msc "$root/source" > "$root/source.mysql.log" 2>&1 &
	echo $! > "$root/source.mysql.pid"

	echo "Fetching test_db"
	curl -L -s "https://github.com/datacharmer/test_db/archive/master.tar.gz" \
		| tar -C "$root" -xzf -

	wait_for_mysql "$root/source.sock"
	echo "Loading test_db"
	(cd "$root/test_db-master" &&
		mysql -u root -S "$root/source.sock" < employees.sql > "$root/source.mysql.import.log" 2>&1)

	echo "Bringing up xtrabackup-http"
	./xtrabackup-http -s "$root/source.sock" -d "$root/source" \
		> "$root/source.xtrabackup.log" 2>&1 &
	echo $! > "$root/source.xtrabackup.pid"

	echo "Creating full backup"
	mkdir "$root/backup.full"
	curl -L -s -f http://localhost:8080/api/backup \
		| xbstream -vxC "$root/backup.full"
	LSN=$(awk '/to_lsn/ { print $3 }' < "$root/backup.full/xtrabackup_checkpoints")

	echo "Inserting new data"
	cat <<-EOF | mysql -u root -S "$root/source.sock"
	USE employees;
	UPDATE salaries SET salary = salary + 1000;
	UPDATE titles SET title = CONCAT("Senior ", title);
	EOF

	echo "Creating incremental backup"
	mkdir "$root/backup.incremental_diffs"
	curl -L -s -f "http://localhost:8080/api/backup/$LSN" \
		| xbstream -vxC "$root/backup.incremental_diffs"
	
	echo "Stopping source db"
	stop_svc "$root/source.mysql.pid"
}


main() {
	local root=""
	if [[ "$#" -ge 1 ]]; then
		root="$1"
	else
		root="$(mktemp -d)"
	fi
	mkdir -p "$root/source"

	# $root is local, so we want it expanded now
	# shellcheck disable=SC2064
	trap "cleanup_and_exit $root" EXIT INT TERM

	create_backups "$root"

	echo "Preparing backup"
	cp -r "$root/backup.full" "$root/backup.incremental"
	xtrabackup --prepare --target-dir="$root/backup.full"
	xtrabackup --prepare --target-dir="$root/backup.full"
	xtrabackup --prepare --target-dir="$root/backup.incremental" \
		--apply-log-only
	xtrabackup --prepare --target-dir="$root/backup.incremental" \
		--apply-log-only --incremental-dir "$root/backup.incremental_diffs"

	echo "Starting destination db on full backup"
	msc "$root/backup.full" > "$root/backup.full.mysql.log" 2>&1 &
	echo $! > "$root/backup.mysql.pid"

	wait_for_mysql "$root/backup.full.sock"
	echo "Comparing destination db to test_db"
	(cd "$root/test_db-master" &&
		mysql -u root -S "$root/backup.full.sock" -t < test_employees_md5.sql \
		> "$root/backup.full.diff.txt")
	if grep FAIL "$root/backup.full.diff.txt"; then
		echo "Restored database in unexpected state" >&2
		exit 1
	fi

	echo "Restarting destination db on incremental based backup"
	stop_svc "$root/backup.mysql.pid"
	msc "$root/backup.incremental" > "$root/backup.incremental.mysql.log" 2>&1 &
	echo $! > "$root/backup.mysql.pid"

	wait_for_mysql "$root/backup.incremental.sock"
	echo "Verifying checksums"
	local checksum
	checksum=$(echo "CHECKSUM TABLE salaries" | mysql -u root -S \
		"$root/backup.incremental.sock" employees \
		| tail -1 | cut -f2)
	if [[ "$checksum" != "$SALARIES_CHECKSUM_EXPECT" ]]; then
		echo "Checksum mismatch. Got: $checksum, Expected: $SALARIES_CHECKSUM_EXPECT"
		exit 1
	fi

	checksum=$(echo "CHECKSUM TABLE titles" | mysql -u root -S \
		"$root/backup.incremental.sock" employees \
		| tail -1 | cut -f2)
	if [[ "$checksum" != "$TITLES_CHECKSUM_EXPECT" ]]; then
		echo "Checksum mismatch. Got: $checksum, Expected: $SALARIES_CHECKSUM_EXPECT"
		exit 1
	fi
	echo "Test passed!"
	exit 0
}

main "$@"
