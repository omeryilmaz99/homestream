package music

import (
	"database/sql"
	"errors"
	"time"

	"homestream/internal/store"
)

// Plays is a profile's listening history of one track.
type Plays struct {
	Count int   `json:"playCount"`
	Last  int64 `json:"lastPlayedAt"`
}

// UserData is a profile's likes (liked at, unix ms) and plays.
type UserData struct {
	Likes map[string]int64
	Plays map[string]Plays
}

// LoadUserData reads a profile's likes and plays ("" → empty).
func (l *Library) LoadUserData(profile string) UserData {
	u := UserData{Likes: map[string]int64{}, Plays: map[string]Plays{}}
	if profile == "" {
		return u
	}
	if rows, err := l.db.Query(`SELECT track_id, liked_at FROM music_likes WHERE profile_id=?`, profile); err == nil {
		for rows.Next() {
			var id string
			var at int64
			if rows.Scan(&id, &at) == nil {
				u.Likes[id] = at
			}
		}
		rows.Close()
	}
	if rows, err := l.db.Query(`SELECT track_id, play_count, last_played_at FROM music_plays WHERE profile_id=?`, profile); err == nil {
		for rows.Next() {
			var id string
			var p Plays
			if rows.Scan(&id, &p.Count, &p.Last) == nil {
				u.Plays[id] = p
			}
		}
		rows.Close()
	}
	return u
}

// SetLiked likes or unlikes tracks.
func (l *Library) SetLiked(profile string, ids []string, liked bool) error {
	tx, err := l.db.Begin()
	if err != nil {
		return err
	}
	defer tx.Rollback()
	now := time.Now().UnixMilli()
	for i, id := range ids {
		if liked {
			// keep the order of a batch: later ones count as newer
			if _, err := tx.Exec(`INSERT INTO music_likes(profile_id,track_id,liked_at) VALUES(?,?,?) ON CONFLICT DO NOTHING`, profile, id, now+int64(i)); err != nil {
				return err
			}
		} else if _, err := tx.Exec(`DELETE FROM music_likes WHERE profile_id=? AND track_id=?`, profile, id); err != nil {
			return err
		}
	}
	return tx.Commit()
}

// AddPlay counts a play of a track.
func (l *Library) AddPlay(profile, id string, at int64) (Plays, error) {
	if at <= 0 || at > time.Now().Unix()+60 {
		at = time.Now().Unix()
	}
	_, err := l.db.Exec(`INSERT INTO music_plays(profile_id,track_id,play_count,last_played_at) VALUES(?,?,1,?)
		ON CONFLICT(profile_id,track_id) DO UPDATE SET play_count=play_count+1,
		last_played_at=MAX(last_played_at, excluded.last_played_at)`, profile, id, at)
	if err != nil {
		return Plays{}, err
	}
	var p Plays
	_ = l.db.QueryRow(`SELECT play_count,last_played_at FROM music_plays WHERE profile_id=? AND track_id=?`, profile, id).Scan(&p.Count, &p.Last)
	return p, nil
}

// DeleteProfileData removes everything a profile stored in the music app.
func (l *Library) DeleteProfileData(profile string) error {
	tx, err := l.db.Begin()
	if err != nil {
		return err
	}
	defer tx.Rollback()
	for _, q := range []string{
		`DELETE FROM music_likes WHERE profile_id=?`,
		`DELETE FROM music_plays WHERE profile_id=?`,
		`DELETE FROM music_playlist_tracks WHERE playlist_id IN (SELECT id FROM music_playlists WHERE profile_id=?)`,
		`DELETE FROM music_playlists WHERE profile_id=?`,
	} {
		if _, err := tx.Exec(q, profile); err != nil {
			return err
		}
	}
	return tx.Commit()
}

// ---------- playlists ----------

// Playlist is a profile's list of tracks.
type Playlist struct {
	ID        string
	Profile   string
	Name      string
	CreatedAt int64
	UpdatedAt int64
	TrackIDs  []string
}

// ErrNotFound is returned for unknown playlists.
var ErrNotFound = errors.New("not found")

func randomID() string { return "pl_" + store.RandomHex(6) }

// Playlists returns the profile's playlists (newest change first).
func (l *Library) Playlists(profile string) ([]Playlist, error) {
	rows, err := l.db.Query(`SELECT id,name,created_at,updated_at FROM music_playlists WHERE profile_id=? ORDER BY updated_at DESC, id`, profile)
	if err != nil {
		return nil, err
	}
	var out []Playlist
	for rows.Next() {
		p := Playlist{Profile: profile}
		if err := rows.Scan(&p.ID, &p.Name, &p.CreatedAt, &p.UpdatedAt); err != nil {
			rows.Close()
			return nil, err
		}
		out = append(out, p)
	}
	rows.Close()
	for i := range out {
		out[i].TrackIDs, _ = l.playlistTracks(out[i].ID)
	}
	return out, nil
}

func (l *Library) playlistTracks(id string) ([]string, error) {
	rows, err := l.db.Query(`SELECT track_id FROM music_playlist_tracks WHERE playlist_id=? ORDER BY pos`, id)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	out := []string{}
	for rows.Next() {
		var t string
		if rows.Scan(&t) == nil {
			out = append(out, t)
		}
	}
	return out, rows.Err()
}

// GetPlaylist returns one of the profile's playlists.
func (l *Library) GetPlaylist(profile, id string) (Playlist, error) {
	p := Playlist{ID: id, Profile: profile}
	err := l.db.QueryRow(`SELECT name,created_at,updated_at FROM music_playlists WHERE id=? AND profile_id=?`, id, profile).
		Scan(&p.Name, &p.CreatedAt, &p.UpdatedAt)
	if errors.Is(err, sql.ErrNoRows) {
		return p, ErrNotFound
	}
	if err != nil {
		return p, err
	}
	p.TrackIDs, err = l.playlistTracks(id)
	return p, err
}

// CreatePlaylist makes a new playlist with optional tracks.
func (l *Library) CreatePlaylist(profile, name string, tracks []string) (Playlist, error) {
	now := time.Now().Unix()
	p := Playlist{ID: randomID(), Profile: profile, Name: name, CreatedAt: now, UpdatedAt: now}
	if _, err := l.db.Exec(`INSERT INTO music_playlists(id,profile_id,name,created_at,updated_at) VALUES(?,?,?,?,?)`,
		p.ID, profile, name, now, now); err != nil {
		return p, err
	}
	if len(tracks) > 0 {
		if err := l.SetPlaylistTracks(profile, p.ID, tracks); err != nil {
			return p, err
		}
	}
	return l.GetPlaylist(profile, p.ID)
}

// RenamePlaylist changes a playlist's name.
func (l *Library) RenamePlaylist(profile, id, name string) error {
	res, err := l.db.Exec(`UPDATE music_playlists SET name=?, updated_at=? WHERE id=? AND profile_id=?`, name, time.Now().Unix(), id, profile)
	if err != nil {
		return err
	}
	if n, _ := res.RowsAffected(); n == 0 {
		return ErrNotFound
	}
	return nil
}

// DeletePlaylist removes a playlist.
func (l *Library) DeletePlaylist(profile, id string) error {
	tx, err := l.db.Begin()
	if err != nil {
		return err
	}
	defer tx.Rollback()
	res, err := tx.Exec(`DELETE FROM music_playlists WHERE id=? AND profile_id=?`, id, profile)
	if err != nil {
		return err
	}
	if n, _ := res.RowsAffected(); n == 0 {
		return ErrNotFound
	}
	if _, err := tx.Exec(`DELETE FROM music_playlist_tracks WHERE playlist_id=?`, id); err != nil {
		return err
	}
	return tx.Commit()
}

// SetPlaylistTracks replaces the playlist's tracks (used for add, remove and reorder).
func (l *Library) SetPlaylistTracks(profile, id string, tracks []string) error {
	tx, err := l.db.Begin()
	if err != nil {
		return err
	}
	defer tx.Rollback()
	var owner string
	if err := tx.QueryRow(`SELECT profile_id FROM music_playlists WHERE id=?`, id).Scan(&owner); err != nil || owner != profile {
		return ErrNotFound
	}
	old := map[string]int64{}
	if rows, err := tx.Query(`SELECT track_id, added_at FROM music_playlist_tracks WHERE playlist_id=?`, id); err == nil {
		for rows.Next() {
			var t string
			var at int64
			if rows.Scan(&t, &at) == nil {
				old[t] = at
			}
		}
		rows.Close()
	}
	if _, err := tx.Exec(`DELETE FROM music_playlist_tracks WHERE playlist_id=?`, id); err != nil {
		return err
	}
	now := time.Now().Unix()
	st, err := tx.Prepare(`INSERT INTO music_playlist_tracks(playlist_id,pos,track_id,added_at) VALUES(?,?,?,?)`)
	if err != nil {
		return err
	}
	defer st.Close()
	for i, t := range tracks {
		at := old[t]
		if at == 0 {
			at = now
		}
		if _, err := st.Exec(id, i, t, at); err != nil {
			return err
		}
	}
	if _, err := tx.Exec(`UPDATE music_playlists SET updated_at=? WHERE id=?`, now, id); err != nil {
		return err
	}
	return tx.Commit()
}
