package store

import "database/sql"

// FileRow is a movie or episode video file.
type FileRow struct {
	ID            string
	Type          string
	FolderID      int64
	RelPath       string
	Size          int64
	MTime         int64
	AddedAt       int64
	Title         string
	Year          int
	SeriesID      string
	Season        int
	Episode       int
	LocalPoster   string
	LocalBackdrop string
	ProbeState    int // 0 = never probed, 1 = ok, 2 = failed
	ProbeSize     int64
	ProbeMTime    int64
	Media         string
	Duration      float64
	Subs          string
}

// FileState is the subset of FileRow used for incremental scans.
type FileState struct {
	FolderID   int64
	AddedAt    int64
	ProbeState int
	ProbeSize  int64
	ProbeMTime int64
}

func (s *Store) FileStates() (map[string]FileState, error) {
	rows, err := s.DB.Query(`SELECT id,folder_id,added_at,probe_state,probe_size,probe_mtime FROM files`)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	out := map[string]FileState{}
	for rows.Next() {
		var id string
		var f FileState
		if err := rows.Scan(&id, &f.FolderID, &f.AddedAt, &f.ProbeState, &f.ProbeSize, &f.ProbeMTime); err != nil {
			return nil, err
		}
		out[id] = f
	}
	return out, rows.Err()
}

// UpsertFiles writes scan results in small transactions (probe columns untouched for existing rows).
func (s *Store) UpsertFiles(rows []FileRow) error {
	const batch = 300
	for start := 0; start < len(rows); start += batch {
		end := min(start+batch, len(rows))
		if err := s.upsertBatch(rows[start:end]); err != nil {
			return err
		}
	}
	return nil
}

func (s *Store) upsertBatch(rows []FileRow) error {
	tx, err := s.DB.Begin()
	if err != nil {
		return err
	}
	defer tx.Rollback()
	st, err := tx.Prepare(`INSERT INTO files(id,type,folder_id,rel_path,size,mtime,added_at,title,year,series_id,season,episode,local_poster,local_backdrop,subs)
		VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)
		ON CONFLICT(id) DO UPDATE SET type=excluded.type, folder_id=excluded.folder_id, rel_path=excluded.rel_path,
		size=excluded.size, mtime=excluded.mtime, title=excluded.title, year=excluded.year, series_id=excluded.series_id,
		season=excluded.season, episode=excluded.episode, local_poster=excluded.local_poster,
		local_backdrop=excluded.local_backdrop, subs=excluded.subs`)
	if err != nil {
		return err
	}
	defer st.Close()
	for _, r := range rows {
		if _, err := st.Exec(r.ID, r.Type, r.FolderID, r.RelPath, r.Size, r.MTime, r.AddedAt, r.Title, r.Year,
			r.SeriesID, r.Season, r.Episode, r.LocalPoster, r.LocalBackdrop, r.Subs); err != nil {
			return err
		}
	}
	return tx.Commit()
}

func (s *Store) DeleteFiles(ids []string) error {
	if len(ids) == 0 {
		return nil
	}
	tx, err := s.DB.Begin()
	if err != nil {
		return err
	}
	defer tx.Rollback()
	for _, id := range ids {
		if _, err := tx.Exec(`DELETE FROM files WHERE id=?`, id); err != nil {
			return err
		}
		if _, err := tx.Exec(`DELETE FROM meta WHERE id=?`, id); err != nil {
			return err
		}
	}
	return tx.Commit()
}

func (s *Store) SetProbe(id string, state int, size, mtime int64, media string, duration float64) error {
	_, err := s.DB.Exec(`UPDATE files SET probe_state=?, probe_size=?, probe_mtime=?, media=?, duration=? WHERE id=?`,
		state, size, mtime, media, duration, id)
	return err
}

func (s *Store) LoadFiles() ([]FileRow, error) {
	rows, err := s.DB.Query(`SELECT id,type,folder_id,rel_path,size,mtime,added_at,title,year,series_id,season,episode,
		local_poster,local_backdrop,probe_state,probe_size,probe_mtime,media,duration,subs FROM files`)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	var out []FileRow
	for rows.Next() {
		var r FileRow
		if err := rows.Scan(&r.ID, &r.Type, &r.FolderID, &r.RelPath, &r.Size, &r.MTime, &r.AddedAt, &r.Title, &r.Year,
			&r.SeriesID, &r.Season, &r.Episode, &r.LocalPoster, &r.LocalBackdrop, &r.ProbeState, &r.ProbeSize,
			&r.ProbeMTime, &r.Media, &r.Duration, &r.Subs); err != nil {
			return nil, err
		}
		out = append(out, r)
	}
	return out, rows.Err()
}

// SeriesRow is a TV series grouping.
type SeriesRow struct {
	ID            string
	Title         string
	Year          int
	Dir           string
	LocalPoster   string
	LocalBackdrop string
}

// ReplaceSeries stores the full set of series and deletes the rest.
func (s *Store) ReplaceSeries(rows []SeriesRow) error {
	tx, err := s.DB.Begin()
	if err != nil {
		return err
	}
	defer tx.Rollback()
	keep := map[string]bool{}
	st, err := tx.Prepare(`INSERT INTO series(id,title,year,dir,local_poster,local_backdrop) VALUES(?,?,?,?,?,?)
		ON CONFLICT(id) DO UPDATE SET title=excluded.title, year=excluded.year, dir=excluded.dir,
		local_poster=excluded.local_poster, local_backdrop=excluded.local_backdrop`)
	if err != nil {
		return err
	}
	defer st.Close()
	for _, r := range rows {
		keep[r.ID] = true
		if _, err := st.Exec(r.ID, r.Title, r.Year, r.Dir, r.LocalPoster, r.LocalBackdrop); err != nil {
			return err
		}
	}
	existing, err := tx.Query(`SELECT id FROM series`)
	if err != nil {
		return err
	}
	var del []string
	for existing.Next() {
		var id string
		if existing.Scan(&id) == nil && !keep[id] {
			del = append(del, id)
		}
	}
	existing.Close()
	for _, id := range del {
		if _, err := tx.Exec(`DELETE FROM series WHERE id=?`, id); err != nil {
			return err
		}
		if _, err := tx.Exec(`DELETE FROM meta WHERE id=?`, id); err != nil {
			return err
		}
	}
	return tx.Commit()
}

func (s *Store) LoadSeries() ([]SeriesRow, error) {
	rows, err := s.DB.Query(`SELECT id,title,year,dir,local_poster,local_backdrop FROM series`)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	var out []SeriesRow
	for rows.Next() {
		var r SeriesRow
		if err := rows.Scan(&r.ID, &r.Title, &r.Year, &r.Dir, &r.LocalPoster, &r.LocalBackdrop); err != nil {
			return nil, err
		}
		out = append(out, r)
	}
	return out, rows.Err()
}

// MetaRow holds TMDB metadata for a movie, series or episode.
type MetaRow struct {
	ID            string
	Query         string
	Status        string // "ok" | "notfound"
	TMDBID        int
	Title         string
	OriginalTitle string
	Overview      string
	Genres        string // JSON array
	Rating        float64
	Year          int
	Poster        string // local cached file path
	Backdrop      string // local cached file path (episode: still)
	FetchedAt     int64
}

func (s *Store) PutMeta(m MetaRow) error {
	_, err := s.DB.Exec(`INSERT INTO meta(id,query,status,tmdb_id,title,original_title,overview,genres,rating,year,poster,backdrop,fetched_at)
		VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?) ON CONFLICT(id) DO UPDATE SET query=excluded.query, status=excluded.status,
		tmdb_id=excluded.tmdb_id, title=excluded.title, original_title=excluded.original_title, overview=excluded.overview,
		genres=excluded.genres, rating=excluded.rating, year=excluded.year, poster=excluded.poster,
		backdrop=excluded.backdrop, fetched_at=excluded.fetched_at`,
		m.ID, m.Query, m.Status, m.TMDBID, m.Title, m.OriginalTitle, m.Overview, m.Genres, m.Rating, m.Year,
		m.Poster, m.Backdrop, m.FetchedAt)
	return err
}

func (s *Store) GetMeta(id string) (MetaRow, bool) {
	var m MetaRow
	err := s.DB.QueryRow(`SELECT id,query,status,tmdb_id,title,original_title,overview,genres,rating,year,poster,backdrop,fetched_at
		FROM meta WHERE id=?`, id).Scan(&m.ID, &m.Query, &m.Status, &m.TMDBID, &m.Title, &m.OriginalTitle, &m.Overview,
		&m.Genres, &m.Rating, &m.Year, &m.Poster, &m.Backdrop, &m.FetchedAt)
	if err == sql.ErrNoRows || err != nil {
		return m, false
	}
	return m, true
}

func (s *Store) AllMeta() (map[string]MetaRow, error) {
	rows, err := s.DB.Query(`SELECT id,query,status,tmdb_id,title,original_title,overview,genres,rating,year,poster,backdrop,fetched_at FROM meta`)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	out := map[string]MetaRow{}
	for rows.Next() {
		var m MetaRow
		if err := rows.Scan(&m.ID, &m.Query, &m.Status, &m.TMDBID, &m.Title, &m.OriginalTitle, &m.Overview,
			&m.Genres, &m.Rating, &m.Year, &m.Poster, &m.Backdrop, &m.FetchedAt); err != nil {
			return nil, err
		}
		out[m.ID] = m
	}
	return out, rows.Err()
}

// ClearMetaQueries forces metadata to be refetched on the next metadata pass.
func (s *Store) ClearMetaQueries() error {
	_, err := s.DB.Exec(`UPDATE meta SET query=''`)
	return err
}
