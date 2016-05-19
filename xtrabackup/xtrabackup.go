package xtrabackup

import (
	"io"
	"log"
	"os/exec"
	"strconv"
)

type Config struct {
	DataDir  string
	User     string
	Password string
	Path     string
	Socket   string

	Log io.Writer
}

type XB struct {
	args   []string
	config *Config
}

// func NewBackup(cmd, dataDir, socket, user, password, lsn string, logWriter io.Writer) (*backup, error) {
func New(config *Config) *XB {
	args := []string{
		"--no-defaults",
		"--datadir=" + config.DataDir,
		"--socket=" + config.Socket,
		"--stream=xbstream",
	}
	for k, v := range map[string]string{
		"--user":     config.User,
		"--password": config.Password,
	} {
		if v == "" {
			continue
		}
		args = append(args, k, v)
	}
	return &XB{args: args, config: config}
}

type Backup struct {
	*exec.Cmd
	Reader io.ReadCloser
}

// Backup starts a new backup. Setting lsn triggers a incremental backup.
func (x *XB) Backup(lsn int) (*Backup, error) {
	args := append([]string{"--backup"}, x.args...)
	if lsn > 0 {
		args = append(args, "--incremental-lsn", strconv.Itoa(lsn))
	}
	log.Printf("running %v", args)
	command := exec.Command(x.config.Path, args...)
	command.Stderr = x.config.Log
	stdout, err := command.StdoutPipe()
	if err != nil {
		return nil, err
	}
	return &Backup{Cmd: command, Reader: stdout}, command.Start()
}
