//go:build android || artex_android_sqlite_test

package traffic

import (
	"database/sql"

	sqlite3 "github.com/mattn/go-sqlite3"
)

func init() {
	// modernc's Linux syscall layer can issue legacy syscalls forbidden by
	// Android's app seccomp policy. CGO uses Bionic's supported interfaces.
	// Keep the driver name, database format and per-connection settings shared
	// with desktop builds. The Android build enables SQLite FTS5 explicitly.
	sql.Register("sqlite", &sqlite3.SQLiteDriver{
		ConnectHook: func(conn *sqlite3.SQLiteConn) error {
			for _, pragma := range []string{"PRAGMA busy_timeout=5000", "PRAGMA journal_mode=WAL"} {
				if _, err := conn.Exec(pragma, nil); err != nil {
					return err
				}
			}
			return nil
		},
	})
}
