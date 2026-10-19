package api

import "homestream/internal/store"

// PlayedRatio and remaining-time thresholds for marking an item played.
const (
	playedRatio     = 0.92
	playedRemaining = 120.0
	playedMinLength = 600.0
)

// isFinished reports whether a progress report means "watched".
func isFinished(pos, dur float64) bool {
	if dur <= 0 {
		return false
	}
	return pos/dur >= playedRatio || (dur > playedMinLength && dur-pos < playedRemaining)
}

// applyProgress applies a progress report to user data.
func applyProgress(u store.UserData, pos, dur float64, now int64) store.UserData {
	if pos < 0 {
		pos = 0
	}
	u.LastPlayedAt = now
	if isFinished(pos, dur) {
		// count a play only on the transition (repeated reports during the
		// credits must not increment playCount again)
		if !u.Played || u.Position > 0 {
			u.PlayCount++
		}
		u.Played = true
		u.Position = 0
		return u
	}
	u.Position = pos
	return u
}

// applyPlayed marks an item played/unplayed.
func applyPlayed(u store.UserData, played bool, now int64) store.UserData {
	if played {
		if !u.Played {
			u.PlayCount++
		}
		u.Played = true
		u.Position = 0
		u.LastPlayedAt = now
	} else {
		u.Played = false
		u.Position = 0
	}
	return u
}
