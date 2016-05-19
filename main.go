package main

import (
	"flag"
	"io"
	"log"
	"net/http"
	"os/exec"
	"strconv"
	"strings"

	"github.com/imgix/xtrabackup-http/xtrabackup"
	"github.com/julienschmidt/httprouter"
)

const (
	pathAPI       = "/api/"
	pathAPIBackup = pathAPI + "backup"
)

type server struct {
	xb *xtrabackup.XB
}

func main() {
	var (
		listenAddr = flag.String("l", ":8080", "Address to listen on")
		dataDir    = flag.String("d", "/var/lib/mysql", "Path to MySQL data dir")
		socket     = flag.String("s", "/var/run/mysqld/mysqld.sock", "Path to MySQL socket")
		user       = flag.String("u", "root", "MySQL user")
		password   = flag.String("p", "", "MySQL password")
		xbName     = flag.String("x", "xtrabackup", "Name of xtrabackup binary")
	)
	flag.Parse()

	xbPath, err := exec.LookPath(*xbName)
	if err != nil {
		log.Fatal(err)
	}

	server := &server{xb: xtrabackup.New(&xtrabackup.Config{
		DataDir:  *dataDir,
		User:     *user,
		Password: *password,
		Socket:   *socket,
		Path:     xbPath,
		Log:      &logWriter{},
	})}

	router := httprouter.New()
	router.GET("/api/backup/*lsn", server.handleBackup)
	log.Fatal(http.ListenAndServe(*listenAddr, router))
}

func (s *server) handleBackup(w http.ResponseWriter, r *http.Request, params httprouter.Params) {
	lsn := 0
	lsnStr := params.ByName("lsn")[1:]
	if lsnStr != "" {
		l, err := strconv.Atoi(params.ByName("lsn")[1:])
		if err != nil {
			logger(w, "Invalid lsn")
			return
		}
		lsn = l
	}

	backup, err := s.xb.Backup(lsn)
	if err != nil {
		logger(w, "Couldn't start backup:", err.Error())
		return
	}
	log.Printf("start copying")
	n, err := io.Copy(w, backup.Reader)
	log.Printf("done copying")
	if err != nil {
		logger(w, "Streaming backup failed:", err.Error())
		if err := backup.Cmd.Process.Kill(); err != nil {
			logger(w, "Couldn't kill process")
		}
	} else {
		log.Printf("Succesfully written %d bytes.", n)
	}

	if err := backup.Cmd.Wait(); err != nil {
		logger(w, "Backup didn't finish:", err.Error())
		return
	}
}

type logWriter struct{}

func (w *logWriter) Write(p []byte) (n int, err error) {
	log.Println(string(p))
	return len(p), nil
}

func logger(w http.ResponseWriter, msgs ...string) {
	text := strings.Join(msgs, " ")
	log.Println(text)
	http.Error(w, text, http.StatusInternalServerError)
}
