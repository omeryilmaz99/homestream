package music

import (
	"database/sql"
	"errors"
	"fmt"
	"strings"
	"time"

	"homestream/internal/store"
)

const schema = `
CREATE TABLE IF NOT EXISTS music_folders(
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  path TEXT NOT NULL UNIQUE,
  name TEXT NOT NULL,
  is_default INTEGER NOT NULL DEFAULT 0,
  available INTEGER NOT NULL DEFAULT 1,
  created_at INTEGER NOT NULL);
CREATE TABLE IF NOT EXISTS music_tracks(
  id TEXT PRIMARY KEY, folder_id INTEGER NOT NULL, rel_path TEXT NOT NULL,
  size INTEGER NOT NULL, mtime INTEGER NOT NULL, added_at INTEGER NOT NULL,
  dir_cover TEXT NOT NULL DEFAULT '',
  probe_state INTEGER NOT NULL DEFAULT 0, probe_size INTEGER NOT NULL DEFAULT -1, probe_mtime INTEGER NOT NULL DEFAULT -1,
  title TEXT NOT NULL DEFAULT '', artist TEXT NOT NULL DEFAULT '', album_artist TEXT NOT NULL DEFAULT '',
  album TEXT NOT NULL DEFAULT '', track_no INTEGER NOT NULL DEFAULT 0, disc_no INTEGER NOT NULL DEFAULT 0,
  year INTEGER NOT NULL DEFAULT 0, genre TEXT NOT NULL DEFAULT '', duration REAL NOT NULL DEFAULT 0,
  codec TEXT NOT NULL DEFAULT '', bitrate INTEGER NOT NULL DEFAULT 0, sample_rate INTEGER NOT NULL DEFAULT 0,
  bit_depth INTEGER NOT NULL DEFAULT 0, channels INTEGER NOT NULL DEFAULT 0,
  is_video INTEGER NOT NULL DEFAULT 0, has_pic INTEGER NOT NULL DEFAULT 0);
CREATE INDEX IF NOT EXISTS music_tracks_folder ON music_tracks(folder_id);
CREATE TABLE IF NOT EXISTS music_likes(
  profile_id TEXT NOT NULL, track_id TEXT NOT NULL, liked_at INTEGER NOT NULL,
  PRIMARY KEY(profile_id, track_id));
CREATE TABLE IF NOT EXISTS music_plays(
  profile_id TEXT NOT NULL, track_id TEXT NOT NULL, play_count INTEGER NOT NULL DEFAULT 0,
  last_played_at INTEGER NOT NULL DEFAULT 0, PRIMARY KEY(profile_id, track_id));
CREATE TABLE IF NOT EXISTS music_playlists(
  id TEXT PRIMARY KEY, profile_id TEXT NOT NULL, name TEXT NOT NULL,
  created_at INTEGER NOT NULL, updated_at INTEGER NOT NULL);
CREATE INDEX IF NOT EXISTS music_playlists_profile ON music_playlists(profile_id);
CREATE TABLE IF NOT EXISTS music_playlist_tracks(
  playlist_id TEXT NOT NULL, pos INTEGER NOT NULL, track_id TEXT NOT NULL, added_at INTEGER NOT NULL,
  PRIMARY KEY(playlist_id, pos));
CREATE TABLE IF NOT EXISTS music_covers(
  key TEXT PRIMARY KEY, status TEXT NOT NULL, path TEXT NOT NULL DEFAULT '', fetched_at INTEGER NOT NULL);
`

func migrate(db *sql.DB) error {
	if _, err := db.Exec(schema); err != nil {
		return fmt.Errorf("music schema: %w", err)
	}
	return nil
}

// ---------- folders ----------

// Folder is a music library folder.
type Folder struct {
	ID        int64  `json:"id"`
	Path      string `json:"path"`
	Name      string `json:"name"`
	IsDefault bool   `json:"isDefault"`
	Available bool   `json:"available"`
	CreatedAt int64  `json:"createdAt"`
}

func loadFolders(db *sql.DB) ([]Folder, error) {
	rows, err := db.Query(`SELECT id,path,name,is_default,available,created_at FROM music_folders ORDER BY is_default DESC, id`)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	var out []Folder
	for rows.Next() {
		var f Folder
		if err := rows.Scan(&f.ID, &f.Path, &f.Name, &f.IsDefault, &f.Available, &f.CreatedAt); err != nil {
			return nil, err
		}
		out = append(out, f)
	}
	return out, rows.Err()
}

func ensureDefaultFolder(db *sql.DB, path, name string) error {
	var id int64
	err := db.QueryRow(`SELECT id FROM music_folders WHERE is_default=1`).Scan(&id)
	if errors.Is(err, sql.ErrNoRows) {
		res, err := db.Exec(`UPDATE music_folders SET is_default=1 WHERE path=?`, path)
		if err != nil {
			return err
		}
		if n, _ := res.RowsAffected(); n > 0 {
			return nil
		}
		_, err = db.Exec(`INSERT INTO music_folders(path,name,is_default,available,created_at) VALUES(?,?,1,1,?)`, path, name, time.Now().Unix())
		return err
	}
	if err != nil {
		return err
	}
	_, err = db.Exec(`UPDATE music_folders SET path=? WHERE id=? AND path<>?`, path, id, path)
	return err
}

// ErrExists is returned when a folder is already in the library.
var ErrExists = store.ErrExists

func addFolder(db *sql.DB, path, name string) (Folder, error) {
	now := time.Now().Unix()
	res, err := db.Exec(`INSERT INTO music_folders(path,name,is_default,available,created_at) VALUES(?,?,0,1,?)`, path, name, now)
	if err != nil {
		if strings.Contains(err.Error(), "UNIQUE") {
			return Folder{}, ErrExists
		}
		return Folder{}, err
	}
	id, _ := res.LastInsertId()
	return Folder{ID: id, Path: path, Name: name, Available: true, CreatedAt: now}, nil
}

func deleteFolder(db *sql.DB, id int64) error {
	tx, err := db.Begin()
	if err != nil {
		return err
	}
	defer tx.Rollback()
	if _, err := tx.Exec(`DELETE FROM music_tracks WHERE folder_id=?`, id); err != nil {
		return err
	}
	if _, err := tx.Exec(`DELETE FROM music_folders WHERE id=? AND is_default=0`, id); err != nil {
		return err
	}
	return tx.Commit()
}

func setFolderAvailable(db *sql.DB, id int64, avail bool) {
	_, _ = db.Exec(`UPDATE music_folders SET available=? WHERE id=?`, avail, id)
}

// ---------- tracks ----------

// trackRow mirrors music_tracks.
type trackRow struct {
	ID         string
	FolderID   int64
	RelPath    string
	Size       int64
	MTime      int64
	AddedAt    int64
	DirCover   string
	ProbeState int // 0 = never, 1 = ok, 2 = failed
	ProbeSize  int64
	ProbeMTime int64
	Tags
}

const trackCols = `id,folder_id,rel_path,size,mtime,added_at,dir_cover,probe_state,probe_size,probe_mtime,
title,artist,album_artist,album,track_no,disc_no,year,genre,duration,codec,bitrate,sample_rate,bit_depth,channels,is_video,has_pic`

func scanTrack(sc interface{ Scan(...any) error }) (trackRow, error) {
	var r trackRow
	err := sc.Scan(&r.ID, &r.FolderID, &r.RelPath, &r.Size, &r.MTime, &r.AddedAt, &r.DirCover, &r.ProbeState,
		&r.ProbeSize, &r.ProbeMTime, &r.Title, &r.Artist, &r.AlbumArtist, &r.Album, &r.TrackNo, &r.DiscNo, &r.Year,
		&r.Genre, &r.Duration, &r.Codec, &r.Bitrate, &r.SampleRate, &r.BitDepth, &r.Channels, &r.IsVideo, &r.HasPic)
	return r, err
}

func loadTracks(db *sql.DB) ([]trackRow, error) {
	rows, err := db.Query(`SELECT ` + trackCols + ` FROM music_tracks`)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	var out []trackRow
	for rows.Next() {
		r, err := scanTrack(rows)
		if err != nil {
			return nil, err
		}
		out = append(out, r)
	}
	return out, rows.Err()
}

// upsertWalked writes file system facts; probe/tag columns of existing rows
// are only replaced when the row carries probe results (ProbeState != 0).
func upsertTracks(db *sql.DB, rows []trackRow) error {
	const batch = 300
	for start := 0; start < len(rows); start += batch {
		end := min(start+batch, len(rows))
		if err := upsertBatch(db, rows[start:end]); err != nil {
			return err
		}
	}
	return nil
}

func upsertBatch(db *sql.DB, rows []trackRow) error {
	tx, err := db.Begin()
	if err != nil {
		return err
	}
	defer tx.Rollback()
	st, err := tx.Prepare(`INSERT INTO music_tracks(` + trackCols + `) VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)
		ON CONFLICT(id) DO UPDATE SET folder_id=excluded.folder_id, rel_path=excluded.rel_path, size=excluded.size,
		mtime=excluded.mtime, dir_cover=excluded.dir_cover`)
	if err != nil {
		return err
	}
	defer st.Close()
	for _, r := range rows {
		if _, err := st.Exec(r.ID, r.FolderID, r.RelPath, r.Size, r.MTime, r.AddedAt, r.DirCover, r.ProbeState,
			r.ProbeSize, r.ProbeMTime, r.Title, r.Artist, r.AlbumArtist, r.Album, r.TrackNo, r.DiscNo, r.Year,
			r.Genre, r.Duration, r.Codec, r.Bitrate, r.SampleRate, r.BitDepth, r.Channels, r.IsVideo, r.HasPic); err != nil {
			return err
		}
	}
	return tx.Commit()
}

func setProbe(db *sql.DB, id string, state int, size, mtime int64, t Tags) error {
	_, err := db.Exec(`UPDATE music_tracks SET probe_state=?, probe_size=?, probe_mtime=?, title=?, artist=?,
		album_artist=?, album=?, track_no=?, disc_no=?, year=?, genre=?, duration=?, codec=?, bitrate=?, sample_rate=?,
		bit_depth=?, channels=?, is_video=?, has_pic=? WHERE id=?`,
		state, size, mtime, t.Title, t.Artist, t.AlbumArtist, t.Album, t.TrackNo, t.DiscNo, t.Year, t.Genre,
		t.Duration, t.Codec, t.Bitrate, t.SampleRate, t.BitDepth, t.Channels, t.IsVideo, t.HasPic, id)
	return err
}

func deleteTracks(db *sql.DB, ids []string) error {
	if len(ids) == 0 {
		return nil
	}
	tx, err := db.Begin()
	if err != nil {
		return err
	}
	defer tx.Rollback()
	st, err := tx.Prepare(`DELETE FROM music_tracks WHERE id=?`)
	if err != nil {
		return err
	}
	defer st.Close()
	for _, id := range ids {
		if _, err := st.Exec(id); err != nil {
			return err
		}
	}
	return tx.Commit()
}

// ---------- cover lookups ----------

type coverRow struct {
	Status    string // "ok" | "notfound" | "error"
	Path      string
	FetchedAt int64
}

func getCoverRow(db *sql.DB, key string) (coverRow, bool) {
	var c coverRow
	err := db.QueryRow(`SELECT status,path,fetched_at FROM music_covers WHERE key=?`, key).Scan(&c.Status, &c.Path, &c.FetchedAt)
	return c, err == nil
}

func allCoverRows(db *sql.DB) map[string]coverRow {
	out := map[string]coverRow{}
	rows, err := db.Query(`SELECT key,status,path,fetched_at FROM music_covers`)
	if err != nil {
		return out
	}
	defer rows.Close()
	for rows.Next() {
		var k string
		var c coverRow
		if rows.Scan(&k, &c.Status, &c.Path, &c.FetchedAt) == nil {
			out[k] = c
		}
	}
	return out
}

func putCoverRow(db *sql.DB, key string, c coverRow) {
	_, _ = db.Exec(`INSERT INTO music_covers(key,status,path,fetched_at) VALUES(?,?,?,?)
		ON CONFLICT(key) DO UPDATE SET status=excluded.status, path=excluded.path, fetched_at=excluded.fetched_at`,
		key, c.Status, c.Path, c.FetchedAt)
}
