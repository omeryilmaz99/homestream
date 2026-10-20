// Package store is the SQLite persistence layer.
package store

import (
	"crypto/rand"
	"database/sql"
	"encoding/hex"
	"errors"
	"fmt"
	"strconv"
	"strings"
	"time"

	_ "modernc.org/sqlite"
)

// Store wraps the database.
type Store struct {
	DB *sql.DB
}

const schema = `
CREATE TABLE IF NOT EXISTS settings(key TEXT PRIMARY KEY, value TEXT NOT NULL);
CREATE TABLE IF NOT EXISTS folders(
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  path TEXT NOT NULL UNIQUE,
  name TEXT NOT NULL,
  is_default INTEGER NOT NULL DEFAULT 0,
  available INTEGER NOT NULL DEFAULT 1,
  created_at INTEGER NOT NULL);
CREATE TABLE IF NOT EXISTS profiles(
  id TEXT PRIMARY KEY, name TEXT NOT NULL, color TEXT NOT NULL, avatar TEXT NOT NULL, created_at INTEGER NOT NULL);
CREATE TABLE IF NOT EXISTS user_data(
  profile_id TEXT NOT NULL, item_id TEXT NOT NULL,
  position REAL NOT NULL DEFAULT 0, played INTEGER NOT NULL DEFAULT 0, play_count INTEGER NOT NULL DEFAULT 0,
  last_played_at INTEGER NOT NULL DEFAULT 0, liked INTEGER NOT NULL DEFAULT 0,
  PRIMARY KEY(profile_id, item_id));
CREATE TABLE IF NOT EXISTS files(
  id TEXT PRIMARY KEY, type TEXT NOT NULL, folder_id INTEGER NOT NULL, rel_path TEXT NOT NULL,
  size INTEGER NOT NULL, mtime INTEGER NOT NULL, added_at INTEGER NOT NULL,
  title TEXT NOT NULL, year INTEGER NOT NULL DEFAULT 0,
  series_id TEXT NOT NULL DEFAULT '', season INTEGER NOT NULL DEFAULT 0, episode INTEGER NOT NULL DEFAULT 0,
  local_poster TEXT NOT NULL DEFAULT '', local_backdrop TEXT NOT NULL DEFAULT '',
  probe_state INTEGER NOT NULL DEFAULT 0, probe_size INTEGER NOT NULL DEFAULT -1, probe_mtime INTEGER NOT NULL DEFAULT -1,
  media TEXT NOT NULL DEFAULT '', duration REAL NOT NULL DEFAULT 0,
  subs TEXT NOT NULL DEFAULT '');
CREATE INDEX IF NOT EXISTS files_folder ON files(folder_id);
CREATE INDEX IF NOT EXISTS files_series ON files(series_id);
CREATE TABLE IF NOT EXISTS series(
  id TEXT PRIMARY KEY, title TEXT NOT NULL, year INTEGER NOT NULL DEFAULT 0, dir TEXT NOT NULL DEFAULT '',
  local_poster TEXT NOT NULL DEFAULT '', local_backdrop TEXT NOT NULL DEFAULT '');
CREATE TABLE IF NOT EXISTS meta(
  id TEXT PRIMARY KEY, query TEXT NOT NULL, status TEXT NOT NULL, tmdb_id INTEGER NOT NULL DEFAULT 0,
  title TEXT NOT NULL DEFAULT '', original_title TEXT NOT NULL DEFAULT '', overview TEXT NOT NULL DEFAULT '',
  genres TEXT NOT NULL DEFAULT '', rating REAL NOT NULL DEFAULT 0, year INTEGER NOT NULL DEFAULT 0,
  poster TEXT NOT NULL DEFAULT '', backdrop TEXT NOT NULL DEFAULT '', fetched_at INTEGER NOT NULL DEFAULT 0);
`

// Open opens (and migrates) the database.
func Open(path string) (*Store, error) {
	dsn := "file:" + path + "?_pragma=journal_mode(WAL)&_pragma=busy_timeout(10000)&_pragma=synchronous(NORMAL)&_pragma=foreign_keys(0)"
	db, err := sql.Open("sqlite", dsn)
	if err != nil {
		return nil, err
	}
	db.SetMaxOpenConns(8)
	db.SetMaxIdleConns(4)
	if _, err := db.Exec(schema); err != nil {
		db.Close()
		return nil, fmt.Errorf("schema: %w", err)
	}
	// migrations (ignore "duplicate column" on databases that already have them)
	for _, m := range []string{
		`ALTER TABLE folders ADD COLUMN kind TEXT NOT NULL DEFAULT 'auto'`,
	} {
		if _, err := db.Exec(m); err != nil && !strings.Contains(err.Error(), "duplicate column") {
			db.Close()
			return nil, fmt.Errorf("migrate: %w", err)
		}
	}
	return &Store{DB: db}, nil
}

func (s *Store) Close() error { return s.DB.Close() }

// RandomHex returns n random bytes hex-encoded.
func RandomHex(n int) string {
	b := make([]byte, n)
	_, _ = rand.Read(b)
	return hex.EncodeToString(b)
}

// ---------- settings ----------

func (s *Store) GetSetting(key string) string {
	var v string
	_ = s.DB.QueryRow(`SELECT value FROM settings WHERE key=?`, key).Scan(&v)
	return v
}

func (s *Store) SetSetting(key, value string) error {
	_, err := s.DB.Exec(`INSERT INTO settings(key,value) VALUES(?,?) ON CONFLICT(key) DO UPDATE SET value=excluded.value`, key, value)
	return err
}

// ---------- folders ----------

type Folder struct {
	ID        int64
	Path      string
	Name      string
	IsDefault bool
	Available bool
	Kind      string // FolderAuto, FolderMovies or FolderSeries
	CreatedAt int64
}

// Folder kinds: how video files in a folder are classified.
const (
	FolderAuto   = "auto"   // decided per file from names and folders
	FolderMovies = "movies" // every video is a movie
	FolderSeries = "series" // every video is an episode
)

// ValidFolderKind normalises a kind string ("" → auto); ok is false for unknown values.
func ValidFolderKind(k string) (string, bool) {
	switch k {
	case "", FolderAuto:
		return FolderAuto, true
	case FolderMovies, FolderSeries:
		return k, true
	}
	return "", false
}

func (f Folder) IDString() string { return strconv.FormatInt(f.ID, 10) }

func (s *Store) Folders() ([]Folder, error) {
	rows, err := s.DB.Query(`SELECT id,path,name,is_default,available,created_at,kind FROM folders ORDER BY is_default DESC, id`)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	var out []Folder
	for rows.Next() {
		var f Folder
		if err := rows.Scan(&f.ID, &f.Path, &f.Name, &f.IsDefault, &f.Available, &f.CreatedAt, &f.Kind); err != nil {
			return nil, err
		}
		out = append(out, f)
	}
	return out, rows.Err()
}

// EnsureDefaultFolder makes sure the default library folder row exists and points to path.
func (s *Store) EnsureDefaultFolder(path, name string) error {
	var id int64
	err := s.DB.QueryRow(`SELECT id FROM folders WHERE is_default=1`).Scan(&id)
	if errors.Is(err, sql.ErrNoRows) {
		// a non-default folder with the same path becomes the default
		res, err := s.DB.Exec(`UPDATE folders SET is_default=1 WHERE path=?`, path)
		if err != nil {
			return err
		}
		if n, _ := res.RowsAffected(); n > 0 {
			return nil
		}
		_, err = s.DB.Exec(`INSERT INTO folders(path,name,is_default,available,created_at) VALUES(?,?,1,1,?)`, path, name, time.Now().Unix())
		return err
	}
	if err != nil {
		return err
	}
	_, err = s.DB.Exec(`UPDATE folders SET path=? WHERE id=? AND path<>?`, path, id, path)
	return err
}

var ErrExists = errors.New("exists")

func (s *Store) AddFolder(path, name, kind string) (Folder, error) {
	now := time.Now().Unix()
	kind, _ = ValidFolderKind(kind)
	res, err := s.DB.Exec(`INSERT INTO folders(path,name,is_default,available,created_at,kind) VALUES(?,?,0,1,?,?)`, path, name, now, kind)
	if err != nil {
		if strings.Contains(err.Error(), "UNIQUE") {
			return Folder{}, ErrExists
		}
		return Folder{}, err
	}
	id, _ := res.LastInsertId()
	return Folder{ID: id, Path: path, Name: name, Available: true, CreatedAt: now, Kind: kind}, nil
}

// DeleteFolder removes a folder and its files (user data is kept).
func (s *Store) DeleteFolder(id int64) error {
	tx, err := s.DB.Begin()
	if err != nil {
		return err
	}
	defer tx.Rollback()
	if _, err := tx.Exec(`DELETE FROM meta WHERE id IN (SELECT id FROM files WHERE folder_id=?)`, id); err != nil {
		return err
	}
	if _, err := tx.Exec(`DELETE FROM files WHERE folder_id=?`, id); err != nil {
		return err
	}
	if _, err := tx.Exec(`DELETE FROM folders WHERE id=? AND is_default=0`, id); err != nil {
		return err
	}
	return tx.Commit()
}

// SetFolderKind changes how a folder's videos are classified.
func (s *Store) SetFolderKind(id int64, kind string) error {
	_, err := s.DB.Exec(`UPDATE folders SET kind=? WHERE id=?`, kind, id)
	return err
}

func (s *Store) SetFolderAvailable(id int64, avail bool) error {
	_, err := s.DB.Exec(`UPDATE folders SET available=? WHERE id=?`, avail, id)
	return err
}

func (s *Store) FolderFileCount(id int64) int {
	var n int
	_ = s.DB.QueryRow(`SELECT COUNT(*) FROM files WHERE folder_id=?`, id).Scan(&n)
	return n
}

// ---------- profiles ----------

type Profile struct {
	ID        string `json:"id"`
	Name      string `json:"name"`
	Color     string `json:"color"`
	Avatar    string `json:"avatar"`
	CreatedAt int64  `json:"createdAt"`
}

func (s *Store) Profiles() ([]Profile, error) {
	rows, err := s.DB.Query(`SELECT id,name,color,avatar,created_at FROM profiles ORDER BY created_at, id`)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	out := []Profile{}
	for rows.Next() {
		var p Profile
		if err := rows.Scan(&p.ID, &p.Name, &p.Color, &p.Avatar, &p.CreatedAt); err != nil {
			return nil, err
		}
		out = append(out, p)
	}
	return out, rows.Err()
}

func (s *Store) Profile(id string) (Profile, bool) {
	var p Profile
	err := s.DB.QueryRow(`SELECT id,name,color,avatar,created_at FROM profiles WHERE id=?`, id).
		Scan(&p.ID, &p.Name, &p.Color, &p.Avatar, &p.CreatedAt)
	return p, err == nil
}

func (s *Store) CreateProfile(name, color, avatar string) (Profile, error) {
	p := Profile{ID: "p_" + RandomHex(4), Name: name, Color: color, Avatar: avatar, CreatedAt: time.Now().Unix()}
	_, err := s.DB.Exec(`INSERT INTO profiles(id,name,color,avatar,created_at) VALUES(?,?,?,?,?)`, p.ID, p.Name, p.Color, p.Avatar, p.CreatedAt)
	return p, err
}

func (s *Store) UpdateProfile(p Profile) error {
	_, err := s.DB.Exec(`UPDATE profiles SET name=?,color=?,avatar=? WHERE id=?`, p.Name, p.Color, p.Avatar, p.ID)
	return err
}

func (s *Store) DeleteProfile(id string) error {
	tx, err := s.DB.Begin()
	if err != nil {
		return err
	}
	defer tx.Rollback()
	if _, err := tx.Exec(`DELETE FROM user_data WHERE profile_id=?`, id); err != nil {
		return err
	}
	if _, err := tx.Exec(`DELETE FROM profiles WHERE id=?`, id); err != nil {
		return err
	}
	return tx.Commit()
}

// ---------- user data ----------

type UserData struct {
	Position     float64 `json:"position"`
	Played       bool    `json:"played"`
	PlayCount    int     `json:"playCount"`
	LastPlayedAt int64   `json:"lastPlayedAt"`
	Liked        bool    `json:"liked"`
}

func (s *Store) UserDataMap(profile string) (map[string]UserData, error) {
	out := map[string]UserData{}
	if profile == "" {
		return out, nil
	}
	rows, err := s.DB.Query(`SELECT item_id,position,played,play_count,last_played_at,liked FROM user_data WHERE profile_id=?`, profile)
	if err != nil {
		return out, err
	}
	defer rows.Close()
	for rows.Next() {
		var id string
		var u UserData
		if err := rows.Scan(&id, &u.Position, &u.Played, &u.PlayCount, &u.LastPlayedAt, &u.Liked); err != nil {
			return out, err
		}
		out[id] = u
	}
	return out, rows.Err()
}

func (s *Store) GetUserData(profile, item string) UserData {
	var u UserData
	_ = s.DB.QueryRow(`SELECT position,played,play_count,last_played_at,liked FROM user_data WHERE profile_id=? AND item_id=?`, profile, item).
		Scan(&u.Position, &u.Played, &u.PlayCount, &u.LastPlayedAt, &u.Liked)
	return u
}

// PutUserData writes several user data rows in one transaction.
func (s *Store) PutUserData(profile string, rows map[string]UserData) error {
	tx, err := s.DB.Begin()
	if err != nil {
		return err
	}
	defer tx.Rollback()
	st, err := tx.Prepare(`INSERT INTO user_data(profile_id,item_id,position,played,play_count,last_played_at,liked) VALUES(?,?,?,?,?,?,?)
		ON CONFLICT(profile_id,item_id) DO UPDATE SET position=excluded.position, played=excluded.played,
		play_count=excluded.play_count, last_played_at=excluded.last_played_at, liked=excluded.liked`)
	if err != nil {
		return err
	}
	defer st.Close()
	for id, u := range rows {
		if _, err := st.Exec(profile, id, u.Position, u.Played, u.PlayCount, u.LastPlayedAt, u.Liked); err != nil {
			return err
		}
	}
	return tx.Commit()
}

// LikeCounts returns how many profiles liked each item.
func (s *Store) LikeCounts() map[string]int {
	out := map[string]int{}
	rows, err := s.DB.Query(`SELECT item_id, COUNT(*) FROM user_data WHERE liked=1 GROUP BY item_id`)
	if err != nil {
		return out
	}
	defer rows.Close()
	for rows.Next() {
		var id string
		var n int
		if rows.Scan(&id, &n) == nil {
			out[id] = n
		}
	}
	return out
}
