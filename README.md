# xtrabackup-http
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


