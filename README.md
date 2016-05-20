# xtrabackup-http
[![Build Status](https://travis-ci.org/imgix/xtrabackup-http.svg?branch=master)](https://travis-ci.org/imgix/xtrabackup-http)

HTTP service around xtrabackup, allows to request backups.

## Usage
```
Usage of ./xtrabackup-http:
  -d string
    	Path to MySQL data dir (default "/var/lib/mysql")
  -l string
    	Address to listen on (default ":8080")
  -p string
    	MySQL password
  -s string
    	Path to MySQL socket (default "/var/run/mysqld/mysqld.sock")
  -u string
    	MySQL user (default "root")
  -x string
    	Name of xtrabackup binary (default "xtrabackup")
```

### Example
This retrieves a full backup and extract it locally:

```
curl -Lsf http://mysql-server:8080/api/backup  | xbstream -x
```

## API
### `/api/backup/*lsn`
This endpoint streams a backup in *xbstream* format.
If `lsn` is given, a incremental backup is streamed.

To extract a backup, you need to install
[xbstream](https://www.percona.com/doc/percona-xtrabackup/2.2/xbstream/xbstream.html).


## Tests
There is a (big) shell script to end-to-end test backup and restore.

Running `run_integration_tests.sh` will:

- bring up a local mysqld instance
- download and import [test_db](https://github.com/datacharmer/test_db)
- start xtrabackup-http
- fetch a backup
- modify the db
- fetch an incremental backup
- load backup in new db and compare to test_db
- load backup + incrementals and verify some checksum
